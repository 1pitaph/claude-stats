import Foundation
import Observation

@MainActor
protocol LocalAIChatEndpointProviding: AnyObject {
    var selectedChatModelID: String { get }
    var localLLMAvailable: Bool { get }
    var localAPIStatusText: String { get }
    func ensureChatEndpoint() -> LocalAIOpenAIEndpoint?
}

extension LocalAIStore: LocalAIChatEndpointProviding {
    var selectedChatModelID: String {
        modelStore.selectedLLMModel.id
    }
}

@MainActor
@Observable
final class ChatStore {
    private(set) var conversations: [ChatConversation] = []
    var selectedConversationID: UUID?
    var draft = ""
    private(set) var projectOptions: [ChatProjectOption] = []
    var selectedProjectID: String?
    private(set) var isLoading = false
    private(set) var isRefreshingProjects = false
    private(set) var isGenerating = false
    private(set) var lastError: String?

    @ObservationIgnored private let persistence: any ChatPersisting
    @ObservationIgnored private let chatClient: any LocalAIChatStreaming
    @ObservationIgnored private let contextBuilder: ChatContextBuilder
    @ObservationIgnored private var didLoad = false
    @ObservationIgnored private var generationTask: Task<Void, Never>?

    init(
        persistence: any ChatPersisting = ChatPersistenceStore(),
        chatClient: any LocalAIChatStreaming = LocalAIChatClient(),
        contextBuilder: ChatContextBuilder = ChatContextBuilder()
    ) {
        self.persistence = persistence
        self.chatClient = chatClient
        self.contextBuilder = contextBuilder
    }

    var selectedConversation: ChatConversation? {
        guard let selectedConversationID else { return nil }
        return conversations.first { $0.id == selectedConversationID }
    }

    var selectedProject: ChatProjectOption? {
        guard let selectedProjectID else { return nil }
        return projectOptions.first { $0.id == selectedProjectID }
    }

    var hasMessages: Bool {
        selectedConversation?.messages.isEmpty == false
    }

    func loadIfNeeded(defaultModelID: String) async {
        guard !didLoad else { return }
        didLoad = true
        isLoading = true
        let snapshot = await persistence.load()
        conversations = Self.sorted(snapshot.conversations)
        selectedConversationID = snapshot.selectedConversationID.flatMap { id in
            conversations.contains { $0.id == id } ? id : nil
        } ?? conversations.first?.id
        if conversations.isEmpty {
            createConversation(defaultModelID: defaultModelID, persist: false)
            await persistSnapshot()
        }
        isLoading = false
    }

    func newConversation(defaultModelID: String) {
        stopGenerating()
        createConversation(defaultModelID: defaultModelID, persist: true)
    }

    func selectConversation(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        selectedConversationID = id
        draft = ""
        schedulePersist()
    }

    func deleteConversation(_ id: UUID, defaultModelID: String) {
        if id == selectedConversationID {
            stopGenerating()
        }
        conversations.removeAll { $0.id == id }
        if conversations.isEmpty {
            createConversation(defaultModelID: defaultModelID, persist: false)
        } else if selectedConversationID == id || selectedConversationID == nil {
            selectedConversationID = conversations.first?.id
        }
        schedulePersist()
    }

    func refreshProjects(sessions: [Session], sourceIDs: Set<GitWorkspaceSourceID>) async {
        isRefreshingProjects = true
        let options = await contextBuilder.projectOptions(sessions: sessions, sourceIDs: sourceIDs)
        projectOptions = options
        if let selectedProjectID, options.contains(where: { $0.id == selectedProjectID }) {
            // Preserve explicit selection.
        } else {
            selectedProjectID = options.first?.id
        }
        isRefreshingProjects = false
    }

    func selectProject(_ id: String?) {
        selectedProjectID = id
    }

    func send(
        endpointProvider: any LocalAIChatEndpointProviding,
        sessions: [Session],
        sourceIDs: Set<GitWorkspaceSourceID>
    ) {
        guard generationTask == nil else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard endpointProvider.localLLMAvailable else {
            lastError = String(localized: "Download a local LLM model before starting a chat.")
            return
        }
        guard let endpoint = endpointProvider.ensureChatEndpoint() else {
            lastError = endpointProvider.localAPIStatusText
            return
        }

        if conversations.isEmpty {
            createConversation(defaultModelID: endpointProvider.selectedChatModelID, persist: false)
        }
        guard let index = selectedConversationIndex else { return }

        let now = Date()
        let userMessage = ChatMessage(role: .user, content: prompt, createdAt: now)
        let assistantMessage = ChatMessage(role: .assistant, content: "", createdAt: now)
        let modelID = endpointProvider.selectedChatModelID
        conversations[index].selectedModelID = modelID
        conversations[index].messages.append(userMessage)
        conversations[index].messages.append(assistantMessage)
        conversations[index].updatedAt = now
        if conversations[index].title == "New Chat" || conversations[index].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            conversations[index].title = Self.title(from: prompt)
        }
        let conversationID = conversations[index].id
        let assistantMessageID = assistantMessage.id
        let settings = conversations[index].settings
        let projectRoot = selectedProject?.rootPath

        draft = ""
        lastError = nil
        isGenerating = true

        generationTask = Task { [weak self] in
            await self?.runGeneration(
                conversationID: conversationID,
                assistantMessageID: assistantMessageID,
                endpoint: endpoint,
                modelID: modelID,
                settings: settings,
                projectRoot: projectRoot
            )
        }
    }

    func stopGenerating() {
        generationTask?.cancel()
    }

    func updateSettings(_ settings: ChatGenerationSettings) {
        guard let index = selectedConversationIndex else { return }
        conversations[index].settings = settings
        conversations[index].updatedAt = Date()
        schedulePersist()
    }

    private func runGeneration(
        conversationID: UUID,
        assistantMessageID: UUID,
        endpoint: LocalAIOpenAIEndpoint,
        modelID: String,
        settings: ChatGenerationSettings,
        projectRoot: String?
    ) async {
        let snapshot: ChatContextSnapshot?
        if let projectRoot {
            snapshot = await contextBuilder.snapshot(for: projectRoot)
        } else {
            snapshot = nil
        }
        setContextSnapshot(snapshot, conversationID: conversationID)
        let request = makeRequest(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            modelID: modelID,
            settings: settings,
            context: snapshot
        )

        do {
            let stream = chatClient.streamChat(endpoint: endpoint, request: request)
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case .delta(let text):
                    appendAssistantDelta(text, conversationID: conversationID, assistantMessageID: assistantMessageID)
                case .completed:
                    break
                }
            }
            await finishGeneration(conversationID: conversationID, error: nil)
        } catch is CancellationError {
            await finishGeneration(conversationID: conversationID, error: nil)
        } catch {
            await finishGeneration(conversationID: conversationID, error: error.localizedDescription)
        }
    }

    private func makeRequest(
        conversationID: UUID,
        assistantMessageID: UUID,
        modelID: String,
        settings: ChatGenerationSettings,
        context: ChatContextSnapshot?
    ) -> LocalAIChatCompletionsRequest {
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else {
            return LocalAIChatCompletionsRequest(
                model: modelID,
                messages: [LocalAIChatMessage(role: "user", content: "")],
                temperature: settings.temperature,
                maxTokens: settings.maxTokens,
                stream: true
            )
        }
        let history = conversation.messages
            .filter { $0.id != assistantMessageID }
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(24)
        var messages = [
            LocalAIChatMessage(role: "system", content: ChatContextBuilder.systemPrompt(context: context)),
        ]
        messages.append(contentsOf: history.map {
            LocalAIChatMessage(role: $0.role.rawValue, content: $0.content)
        })
        return LocalAIChatCompletionsRequest(
            model: modelID,
            messages: messages,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens,
            stream: true
        )
    }

    private func appendAssistantDelta(_ delta: String, conversationID: UUID, assistantMessageID: UUID) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return
        }
        conversations[conversationIndex].messages[messageIndex].content += delta
        conversations[conversationIndex].updatedAt = Date()
        conversations = Self.sorted(conversations)
    }

    private func setContextSnapshot(_ snapshot: ChatContextSnapshot?, conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].contextSnapshot = snapshot
        conversations[index].updatedAt = Date()
        conversations = Self.sorted(conversations)
    }

    private func finishGeneration(conversationID: UUID, error: String?) async {
        if let error {
            lastError = error
        }
        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[index].updatedAt = Date()
            conversations = Self.sorted(conversations)
        }
        isGenerating = false
        generationTask = nil
        await persistSnapshot()
    }

    private func createConversation(defaultModelID: String, persist: Bool) {
        let conversation = ChatConversation(selectedModelID: defaultModelID)
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        draft = ""
        if persist {
            schedulePersist()
        }
    }

    private var selectedConversationIndex: Int? {
        guard let selectedConversationID else { return nil }
        return conversations.firstIndex { $0.id == selectedConversationID }
    }

    private func schedulePersist() {
        let snapshot = ChatLibrarySnapshot(conversations: conversations, selectedConversationID: selectedConversationID)
        Task { [persistence] in
            await persistence.save(snapshot)
        }
    }

    private func persistSnapshot() async {
        await persistence.save(ChatLibrarySnapshot(conversations: conversations, selectedConversationID: selectedConversationID))
    }

    private static func sorted(_ conversations: [ChatConversation]) -> [ChatConversation] {
        conversations.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.createdAt > $1.createdAt
        }
    }

    private static func title(from prompt: String) -> String {
        let collapsed = prompt
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard collapsed.count > 42 else { return collapsed }
        return "\(collapsed.prefix(39))..."
    }
}
