import Foundation
import Observation

struct MemoryModelSidecarLaunchConfiguration: Sendable, Hashable {
    var runtimeConfig: CodeMemoryModelRuntimeConfig?
    var legacyLocalAIEnvironment: CodeMemoryLocalAIEnvironment?

    var adaptersEnabled: Bool {
        runtimeConfig?.adaptersEnabled ?? legacyLocalAIEnvironment?.adaptersEnabled ?? false
    }
}

@MainActor
@Observable
final class MemoryModelSettingsStore {
    private(set) var settings = MemoryLLMSettings()
    var mode: MemoryLLMMode = .online
    var onlineExtractionEnabled = false
    var selectedProtocol: MemoryOnlineLLMProtocol = .openAIResponses
    var providerName = ""
    var providerBaseURL = ""
    var providerModel = ""
    var apiKey = ""
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var setupMessage: String?

    @ObservationIgnored private let store: MemoryLLMConfigurationStore
    @ObservationIgnored private var hasLoaded = false

    init(store: MemoryLLMConfigurationStore = MemoryLLMConfigurationStore()) {
        self.store = store
        apply(settings: settings)
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await store.loadSettings()
            settings = loaded
            apply(settings: loaded)
            hasLoaded = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func selectProtocol(_ nextProtocol: MemoryOnlineLLMProtocol) {
        selectedProtocol = nextProtocol
        let provider = settings.provider(for: nextProtocol) ?? MemoryOnlineLLMProvider.defaultProviders().first { $0.protocol == nextProtocol }
        if let provider {
            settings.selectedProviderID = provider.id
            apply(provider: provider)
        }
    }

    func saveDraft() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var next = settings
            next.mode = mode
            next.onlineExtractionEnabled = onlineExtractionEnabled
            let existing = next.provider(for: selectedProtocol)
                ?? MemoryOnlineLLMProvider.defaultProviders().first { $0.protocol == selectedProtocol }
                ?? MemoryOnlineLLMProvider(
                    id: selectedProtocol.defaultProviderID,
                    name: selectedProtocol.title,
                    protocol: selectedProtocol,
                    baseURL: selectedProtocol.defaultBaseURL,
                    model: selectedProtocol.defaultModel
                )
            let savedProvider = try store.providerBySavingDraft(
                existing: existing,
                name: providerName,
                baseURL: providerBaseURL,
                model: providerModel,
                rawAPIKey: apiKey
            )
            next.replaceProvider(savedProvider)
            try await store.saveSettings(next)
            settings = next
            apply(settings: next)
            setupMessage = "Saved Memory LLM settings."
            lastError = nil
            hasLoaded = true
        } catch {
            lastError = error.localizedDescription
            setupMessage = error.localizedDescription
        }
    }

    func useLocalModeAndSave() async {
        mode = .local
        await saveDraft()
    }

    func useOnlineSourceOnlyAndSave() async {
        mode = .online
        onlineExtractionEnabled = false
        await saveDraft()
    }

    func sidecarLaunchConfiguration(localAI: LocalAIStore) -> MemoryModelSidecarLaunchConfiguration {
        switch mode {
        case .online:
            guard onlineExtractionEnabled else {
                return MemoryModelSidecarLaunchConfiguration(runtimeConfig: nil, legacyLocalAIEnvironment: nil)
            }
            guard let provider = currentOnlineProvider(),
                  provider.isEnabled,
                  let llmBaseURL = URL(string: provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                  !provider.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return MemoryModelSidecarLaunchConfiguration(runtimeConfig: nil, legacyLocalAIEnvironment: nil)
            }
            let resolvedKey = currentAPIKey(for: provider)
            guard !resolvedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  localAI.semanticSearchAvailable
            else {
                return MemoryModelSidecarLaunchConfiguration(runtimeConfig: nil, legacyLocalAIEnvironment: nil)
            }
            guard let embeddingEnvironment = localAI.localAIEnvironment(adaptersEnabled: false, allowRestart: true) else {
                return MemoryModelSidecarLaunchConfiguration(runtimeConfig: nil, legacyLocalAIEnvironment: nil)
            }
            let runtime = CodeMemoryModelRuntimeConfig(
                mode: MemoryLLMMode.online.rawValue,
                llm: CodeMemoryLLMEndpoint(
                    protocolName: provider.protocol.codeMemoryProtocol,
                    baseURL: llmBaseURL,
                    apiKey: resolvedKey,
                    model: provider.model.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                embedding: CodeMemoryEmbeddingEndpoint(
                    baseURL: embeddingEnvironment.baseURL,
                    apiKey: embeddingEnvironment.token,
                    model: embeddingEnvironment.embeddingModelID,
                    dimensions: embeddingEnvironment.embeddingDimensions
                )
            )
            return MemoryModelSidecarLaunchConfiguration(runtimeConfig: runtime, legacyLocalAIEnvironment: nil)

        case .local:
            guard localAI.semanticSearchAvailable, localAI.localLLMAvailable else {
                return MemoryModelSidecarLaunchConfiguration(runtimeConfig: nil, legacyLocalAIEnvironment: nil)
            }
            guard let localEnvironment = localAI.localAIEnvironment(adaptersEnabled: true, allowRestart: true) else {
                return MemoryModelSidecarLaunchConfiguration(runtimeConfig: nil, legacyLocalAIEnvironment: nil)
            }
            let runtime = CodeMemoryModelRuntimeConfig(
                mode: MemoryLLMMode.local.rawValue,
                llm: CodeMemoryLLMEndpoint(
                    protocolName: .openAIChatCompletions,
                    baseURL: localEnvironment.baseURL,
                    apiKey: localEnvironment.token,
                    model: localEnvironment.llmModelID
                ),
                embedding: CodeMemoryEmbeddingEndpoint(
                    baseURL: localEnvironment.baseURL,
                    apiKey: localEnvironment.token,
                    model: localEnvironment.embeddingModelID,
                    dimensions: localEnvironment.embeddingDimensions
                )
            )
            return MemoryModelSidecarLaunchConfiguration(runtimeConfig: runtime, legacyLocalAIEnvironment: localEnvironment)
        }
    }

    func readinessSummary(localAI: LocalAIStore) -> String {
        switch mode {
        case .online:
            guard onlineExtractionEnabled else { return "Online extraction is off" }
            guard localAI.semanticSearchAvailable else { return "Local embedding model is missing" }
            guard let provider = currentOnlineProvider() else { return "Provider is missing" }
            guard !currentAPIKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "API key is missing" }
            guard !provider.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Model is missing" }
            return "Ready"
        case .local:
            if !localAI.semanticSearchAvailable { return "Local embedding model is missing" }
            if !localAI.localLLMAvailable { return "Local LLM is missing" }
            return "Ready"
        }
    }

    func hasRunnableAdapters(localAI: LocalAIStore) -> Bool {
        sidecarLaunchConfiguration(localAI: localAI).adaptersEnabled
    }

    private func apply(settings: MemoryLLMSettings) {
        var normalized = settings
        normalized.normalize()
        self.settings = normalized
        mode = normalized.mode
        onlineExtractionEnabled = normalized.onlineExtractionEnabled
        let provider = normalized.selectedProvider
            ?? normalized.provider(for: .openAIResponses)
            ?? MemoryOnlineLLMProvider.defaultProviders().first { $0.protocol == .openAIResponses }
        if let provider {
            selectedProtocol = provider.protocol
            apply(provider: provider)
        }
    }

    private func apply(provider: MemoryOnlineLLMProvider) {
        providerName = provider.name
        providerBaseURL = provider.baseURL
        providerModel = provider.model
        apiKey = store.resolvedAPIKey(for: provider.apiKey)
    }

    private func currentOnlineProvider() -> MemoryOnlineLLMProvider? {
        if let provider = settings.provider(for: selectedProtocol) {
            var edited = provider
            edited.name = providerName
            edited.baseURL = providerBaseURL
            edited.model = providerModel
            return edited
        }
        return MemoryOnlineLLMProvider.defaultProviders().first { $0.protocol == selectedProtocol }
    }

    private func currentAPIKey(for provider: MemoryOnlineLLMProvider) -> String {
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return apiKey
        }
        return store.resolvedAPIKey(for: provider.apiKey)
    }
}
