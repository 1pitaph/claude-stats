import SwiftUI

struct ChatWorkspaceView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var store: ChatStore

    private struct RefreshKey: Equatable {
        let lastRefreshedAt: Date?
        let sourceIDs: String
    }

    private var refreshKey: RefreshKey {
        RefreshKey(
            lastRefreshedAt: env.store.lastRefreshedAt,
            sourceIDs: GitWorkspaceSourceCatalog.storageString(for: env.preferences.gitWorkspaceSourceIDs)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            messages
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            composer
        }
        .task(id: refreshKey) {
            await store.loadIfNeeded(defaultModelID: env.localAI.modelStore.selectedLLMModel.id)
            await store.refreshProjects(sessions: env.store.sessions, sourceIDs: env.preferences.gitWorkspaceSourceIDs)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CHAT")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Text(store.selectedConversation?.title ?? "Local LLM Chat")
                    .font(.sora(24, weight: .semibold))
                    .lineLimit(1)
                Text(headerSubtitle)
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if store.isRefreshingProjects {
                ProgressView()
                    .controlSize(.small)
                    .help("Refreshing Projects")
            }

            Button {
                Task {
                    await store.refreshProjects(sessions: env.store.sessions, sourceIDs: env.preferences.gitWorkspaceSourceIDs)
                }
            } label: {
                Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
            }
            .controlSize(.small)
            .disabled(store.isRefreshingProjects)

            Button {
                openLocalAISettings()
            } label: {
                Label("Local AI", systemImage: "brain")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }

    private var headerSubtitle: String {
        let model = env.localAI.modelStore.selectedLLMModel.displayName
        if let project = store.selectedProject {
            return "\(model) · \(project.displayName) · \(project.branchLabel)"
        }
        return "\(model) · \(String(localized: "No project context"))"
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if store.selectedConversation?.messages.isEmpty != false {
                        chatEmptyState
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 320)
                    } else {
                        ForEach(store.selectedConversation?.messages ?? []) { message in
                            ChatMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .onChange(of: store.selectedConversation?.messages.map(\.content) ?? []) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
            .onChange(of: store.selectedConversationID) { _, _ in
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
        .overlay(alignment: .top) {
            if let error = store.lastError {
                Text(error)
                    .font(.sora(11))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppSurface.panelFill, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.red.opacity(0.35), lineWidth: 1))
                    .padding(.top, 10)
            }
        }
    }

    private var chatEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: env.localAI.localLLMAvailable ? "bubble.left.and.bubble.right" : "arrow.down.circle")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            Text(env.localAI.localLLMAvailable ? "Ask the local model" : "Install a local LLM")
                .font(.sora(16, weight: .semibold))
            Text(env.localAI.localLLMAvailable ? "Start a private local conversation with read-only project context." : "Download an LLM in Local AI settings before chatting.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .multilineTextAlignment(.center)
            if !env.localAI.localLLMAvailable {
                Button {
                    openLocalAISettings()
                } label: {
                    Label("Open Local AI Settings", systemImage: "gearshape")
                }
                .controlSize(.small)
            }
        }
        .padding(24)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            StxRule()
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $store.draft)
                        .font(.sora(14))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 72, maxHeight: 118)
                        .disabled(store.isGenerating)
                    if store.draft.isEmpty {
                        Text("Ask anything")
                            .font(.sora(18, weight: .semibold))
                            .foregroundStyle(Color.stxMuted.opacity(0.55))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        store.newConversation(defaultModelID: env.localAI.modelStore.selectedLLMModel.id)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("New Chat")

                    projectMenu
                    modelMenu
                    settingsMenu

                    Spacer(minLength: 10)

                    if let project = store.selectedProject {
                        ChatComposerChip(symbol: "folder", text: project.displayName)
                        ChatComposerChip(symbol: "arrow.triangle.branch", text: project.branchLabel)
                    }
                    ChatComposerChip(symbol: "hand.raised", text: String(localized: "Read-only"))

                    Button {
                        if store.isGenerating {
                            store.stopGenerating()
                        } else {
                            store.send(
                                endpointProvider: env.localAI,
                                sessions: env.store.sessions,
                                sourceIDs: env.preferences.gitWorkspaceSourceIDs
                            )
                        }
                    } label: {
                        Image(systemName: store.isGenerating ? "stop.fill" : "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(sendButtonFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.isGenerating && !canSend)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .help(store.isGenerating ? "Stop" : "Send")
                }
            }
            .padding(14)
            .background(AppSurface.panelFill.opacity(0.78), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.stxStroke.opacity(0.8), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var canSend: Bool {
        env.localAI.localLLMAvailable && !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendButtonFill: Color {
        if store.isGenerating { return Color.red.opacity(0.82) }
        return canSend ? Color.stxAccent : Color.gray.opacity(0.55)
    }

    private var projectMenu: some View {
        Menu {
            Button("No Project Context") {
                store.selectProject(nil)
            }
            if !store.projectOptions.isEmpty {
                Divider()
            }
            ForEach(store.projectOptions) { project in
                Button {
                    store.selectProject(project.id)
                } label: {
                    Label(project.displayName, systemImage: store.selectedProjectID == project.id ? "checkmark" : "folder")
                }
            }
        } label: {
            Label(store.selectedProject?.displayName ?? "No Project", systemImage: "folder")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var modelMenu: some View {
        Menu {
            ForEach(env.localAI.modelStore.llmModels) { model in
                Button {
                    env.localAI.modelStore.select(modelID: model.id, kind: .llm)
                } label: {
                    Label(model.displayName, systemImage: model.id == env.localAI.modelStore.selectedLLMModel.id ? "checkmark" : "cpu")
                }
                .disabled(env.localAI.modelStore.installState(for: model.id).phase != .installed)
            }
        } label: {
            Label(env.localAI.modelStore.selectedLLMModel.displayName, systemImage: "cpu")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var settingsMenu: some View {
        Menu {
            Button("Temperature 0.2") { updateSettings(temperature: 0.2) }
            Button("Temperature 0.4") { updateSettings(temperature: 0.4) }
            Button("Temperature 0.7") { updateSettings(temperature: 0.7) }
            Divider()
            Button("512 tokens") { updateSettings(maxTokens: 512) }
            Button("768 tokens") { updateSettings(maxTokens: 768) }
            Button("1024 tokens") { updateSettings(maxTokens: 1024) }
        } label: {
            Label(settingsLabel, systemImage: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var settingsLabel: String {
        let settings = store.selectedConversation?.settings ?? .default
        return "\(String(format: "%.1f", settings.temperature)) · \(settings.maxTokens)"
    }

    private func updateSettings(temperature: Double? = nil, maxTokens: Int? = nil) {
        var settings = store.selectedConversation?.settings ?? .default
        if let temperature { settings.temperature = temperature }
        if let maxTokens { settings.maxTokens = maxTokens }
        store.updateSettings(settings)
    }

    private func openLocalAISettings() {
        NotificationCenter.default.post(name: .openSettingsInMainWindow, object: SettingsSection.localAI)
    }
}

private struct ChatMessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: isUser ? "person.crop.circle" : "cpu")
                        .font(.system(size: 11, weight: .semibold))
                    Text(message.role.displayName)
                        .font(.sora(11, weight: .semibold))
                }
                .foregroundStyle(isUser ? Color.white.opacity(0.82) : Color.stxMuted)

                Text(message.content.isEmpty ? "..." : message.content)
                    .font(.sora(13))
                    .foregroundStyle(isUser ? Color.white : Color.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: 680, alignment: .leading)
            .background(bubbleFill, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(bubbleStroke, lineWidth: 1))
            if !isUser { Spacer(minLength: 80) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var bubbleFill: Color {
        isUser ? Color.stxAccent.opacity(0.88) : Color.primary.opacity(0.055)
    }

    private var bubbleStroke: Color {
        isUser ? Color.white.opacity(0.16) : Color.stxStroke.opacity(0.75)
    }
}

private struct ChatComposerChip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.sora(11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.055), in: Capsule())
    }
}

#if DEBUG
#Preview("Chat workspace") {
    ChatWorkspaceView(store: AppEnvironment.preview().chat)
        .environment(AppEnvironment.preview())
        .frame(width: 900, height: 640)
        .background(Color.stxBackground)
}
#endif
