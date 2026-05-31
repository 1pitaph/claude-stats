import Foundation
import Observation

enum AppLLMSettingsStoreError: Error, LocalizedError, Sendable {
    case missingOnlineProvider
    case invalidBaseURL
    case missingModel
    case missingAPIKey
    case localLLMUnavailable
    case localEndpointUnavailable

    var errorDescription: String? {
        switch self {
        case .missingOnlineProvider: "LLM provider is missing."
        case .invalidBaseURL: "LLM base URL is invalid."
        case .missingModel: "LLM model is missing."
        case .missingAPIKey: "LLM API key is missing."
        case .localLLMUnavailable: "Local LLM model is not installed."
        case .localEndpointUnavailable: "Local OpenAI-compatible endpoint could not be started."
        }
    }
}

@MainActor
@Observable
final class AppLLMSettingsStore {
    private(set) var settings = AppLLMSettings()
    var mode: AppLLMMode = .online
    var selectedProtocol: AppLLMProtocol = .openAIResponses
    var providerName = ""
    var providerBaseURL = ""
    var providerModel = ""
    var apiKey = ""
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var setupMessage: String?

    @ObservationIgnored private let store: AppLLMConfigurationStore
    @ObservationIgnored private var hasLoaded = false

    init(store: AppLLMConfigurationStore = AppLLMConfigurationStore()) {
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

    func selectProtocol(_ nextProtocol: AppLLMProtocol) {
        selectedProtocol = nextProtocol
        let provider = settings.provider(for: nextProtocol)
            ?? AppLLMProvider.defaultProviders().first { $0.protocol == nextProtocol }
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
            let existing = next.provider(for: selectedProtocol)
                ?? AppLLMProvider.defaultProviders().first { $0.protocol == selectedProtocol }
                ?? AppLLMProvider(
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
            setupMessage = "Saved LLM settings."
            lastError = nil
            hasLoaded = true
        } catch {
            lastError = error.localizedDescription
            setupMessage = error.localizedDescription
        }
    }

    func useLocalModeAndSave() async {
        mode = .local
        await saveModeOnly()
    }

    func useOnlineModeAndSave() async {
        mode = .online
        await saveModeOnly()
    }

    func resolvedOnlineProvider() -> AppLLMResolvedOnlineProvider? {
        store.resolvedProvider(from: editedSettings())
    }

    func generationEndpoint(localAI: LocalAIStore) throws -> AppLLMGenerationEndpoint {
        switch mode {
        case .online:
            guard let resolved = resolvedOnlineProvider() else {
                throw AppLLMSettingsStoreError.missingOnlineProvider
            }
            let base = resolved.provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: base), url.scheme != nil, url.host != nil else {
                throw AppLLMSettingsStoreError.invalidBaseURL
            }
            let model = resolved.provider.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else { throw AppLLMSettingsStoreError.missingModel }
            guard !resolved.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppLLMSettingsStoreError.missingAPIKey
            }
            return AppLLMGenerationEndpoint(
                mode: .online,
                protocol: resolved.provider.protocol,
                baseURL: url,
                apiKey: resolved.apiKey,
                model: model,
                displayName: resolved.provider.name
            )

        case .local:
            guard localAI.localLLMAvailable else {
                throw AppLLMSettingsStoreError.localLLMUnavailable
            }
            guard let endpoint = localAI.ensureChatEndpoint() else {
                throw AppLLMSettingsStoreError.localEndpointUnavailable
            }
            return AppLLMGenerationEndpoint(
                mode: .local,
                protocol: .openAIChatCompletions,
                baseURL: endpoint.baseURL,
                apiKey: endpoint.token,
                model: localAI.modelStore.selectedLLMModel.id,
                displayName: "Local LLM"
            )
        }
    }

    func readinessSummary(localAI: LocalAIStore) -> String {
        switch mode {
        case .online:
            guard let resolved = resolvedOnlineProvider() else { return "Provider is missing" }
            guard !resolved.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "API key is missing" }
            guard !resolved.provider.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Model is missing" }
            return "Ready"
        case .local:
            guard localAI.localLLMAvailable else { return "Local LLM is missing" }
            return localAI.localAPIEndpoint == nil ? "Local endpoint stopped" : "Ready"
        }
    }

    private func saveModeOnly() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var next = settings
            next.mode = mode
            next.updatedAt = .now
            try await store.saveSettings(next)
            settings = next
            apply(settings: next)
            setupMessage = "Saved LLM mode."
            lastError = nil
            hasLoaded = true
        } catch {
            lastError = error.localizedDescription
            setupMessage = error.localizedDescription
        }
    }

    private func editedSettings() -> AppLLMSettings {
        var next = settings
        next.mode = mode
        if var provider = next.provider(for: selectedProtocol) {
            provider.name = providerName
            provider.baseURL = providerBaseURL
            provider.model = providerModel
            if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                provider.apiKey = .inline(apiKey)
            }
            next.replaceProvider(provider)
        }
        return next
    }

    private func apply(settings: AppLLMSettings) {
        var normalized = settings
        normalized.normalize()
        self.settings = normalized
        mode = normalized.mode
        let provider = normalized.selectedProvider
            ?? normalized.provider(for: .openAIResponses)
            ?? AppLLMProvider.defaultProviders().first { $0.protocol == .openAIResponses }
        if let provider {
            selectedProtocol = provider.protocol
            apply(provider: provider)
        }
    }

    private func apply(provider: AppLLMProvider) {
        providerName = provider.name
        providerBaseURL = provider.baseURL
        providerModel = provider.model
        apiKey = store.resolvedAPIKey(for: provider.apiKey)
    }
}
