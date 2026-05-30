import Foundation

enum MemoryLLMMode: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case online
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .online: "Online"
        case .local: "Local LLM"
        }
    }
}

enum MemoryOnlineLLMProtocol: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case openAIChatCompletions
    case openAIResponses
    case anthropicMessages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAIChatCompletions: "OpenAI Chat"
        case .openAIResponses: "OpenAI Responses"
        case .anthropicMessages: "Anthropic Messages"
        }
    }

    var subtitle: String {
        switch self {
        case .openAIChatCompletions: "/v1/chat/completions"
        case .openAIResponses: "/v1/responses"
        case .anthropicMessages: "/v1/messages"
        }
    }

    var codeMemoryProtocol: CodeMemoryLLMProtocol {
        switch self {
        case .openAIChatCompletions: .openAIChatCompletions
        case .openAIResponses: .openAIResponses
        case .anthropicMessages: .anthropicMessages
        }
    }

    var defaultProviderID: String {
        switch self {
        case .openAIChatCompletions: MemoryOnlineLLMProvider.openAIChatID
        case .openAIResponses: MemoryOnlineLLMProvider.openAIResponsesID
        case .anthropicMessages: MemoryOnlineLLMProvider.anthropicID
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAIChatCompletions, .openAIResponses: "https://api.openai.com/v1"
        case .anthropicMessages: "https://api.anthropic.com"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAIChatCompletions, .openAIResponses: "gpt-5-mini"
        case .anthropicMessages: "claude-haiku-4-5-latest"
        }
    }
}

struct MemoryOnlineLLMProvider: Codable, Identifiable, Sendable, Hashable {
    static let openAIChatID = "openai-chat-completions"
    static let openAIResponsesID = "openai-responses"
    static let anthropicID = "anthropic-messages"

    var id: String
    var name: String
    var `protocol`: MemoryOnlineLLMProtocol
    var baseURL: String
    var model: String
    var apiKey: APIProviderSecret
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        protocol: MemoryOnlineLLMProtocol,
        baseURL: String,
        model: String,
        apiKey: APIProviderSecret = .none,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.protocol = `protocol`
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func defaultProviders(now: Date = .now) -> [MemoryOnlineLLMProvider] {
        [
            MemoryOnlineLLMProvider(
                id: MemoryOnlineLLMProtocol.openAIChatCompletions.defaultProviderID,
                name: "OpenAI Chat Completions",
                protocol: .openAIChatCompletions,
                baseURL: MemoryOnlineLLMProtocol.openAIChatCompletions.defaultBaseURL,
                model: MemoryOnlineLLMProtocol.openAIChatCompletions.defaultModel,
                createdAt: now,
                updatedAt: now
            ),
            MemoryOnlineLLMProvider(
                id: MemoryOnlineLLMProtocol.openAIResponses.defaultProviderID,
                name: "OpenAI Responses",
                protocol: .openAIResponses,
                baseURL: MemoryOnlineLLMProtocol.openAIResponses.defaultBaseURL,
                model: MemoryOnlineLLMProtocol.openAIResponses.defaultModel,
                createdAt: now,
                updatedAt: now
            ),
            MemoryOnlineLLMProvider(
                id: MemoryOnlineLLMProtocol.anthropicMessages.defaultProviderID,
                name: "Anthropic",
                protocol: .anthropicMessages,
                baseURL: MemoryOnlineLLMProtocol.anthropicMessages.defaultBaseURL,
                model: MemoryOnlineLLMProtocol.anthropicMessages.defaultModel,
                createdAt: now,
                updatedAt: now
            ),
        ]
    }
}

struct MemoryLLMSettings: Codable, Sendable, Hashable {
    var mode: MemoryLLMMode
    var onlineExtractionEnabled: Bool
    var selectedProviderID: String
    var providers: [MemoryOnlineLLMProvider]
    var updatedAt: Date

    init(
        mode: MemoryLLMMode = .online,
        onlineExtractionEnabled: Bool = false,
        selectedProviderID: String = MemoryOnlineLLMProvider.openAIResponsesID,
        providers: [MemoryOnlineLLMProvider] = MemoryOnlineLLMProvider.defaultProviders(),
        updatedAt: Date = .now
    ) {
        self.mode = mode
        self.onlineExtractionEnabled = onlineExtractionEnabled
        self.selectedProviderID = selectedProviderID
        self.providers = providers
        self.updatedAt = updatedAt
        normalize()
    }

    var selectedProvider: MemoryOnlineLLMProvider? {
        providers.first { $0.id == selectedProviderID }
    }

    func provider(for protocol: MemoryOnlineLLMProtocol) -> MemoryOnlineLLMProvider? {
        providers.first { $0.protocol == `protocol` }
    }

    mutating func replaceProvider(_ provider: MemoryOnlineLLMProvider) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
        selectedProviderID = provider.id
        updatedAt = .now
        normalize()
    }

    mutating func normalize() {
        let now = updatedAt
        var merged = providers
        for defaultProvider in MemoryOnlineLLMProvider.defaultProviders(now: now) where !merged.contains(where: { $0.id == defaultProvider.id }) {
            merged.append(defaultProvider)
        }
        providers = merged.sorted { lhs, rhs in
            let lhsIndex = MemoryOnlineLLMProtocol.allCases.firstIndex(of: lhs.protocol) ?? 0
            let rhsIndex = MemoryOnlineLLMProtocol.allCases.firstIndex(of: rhs.protocol) ?? 0
            return lhsIndex < rhsIndex
        }
        if !providers.contains(where: { $0.id == selectedProviderID }) {
            selectedProviderID = MemoryOnlineLLMProvider.openAIResponsesID
        }
    }
}

struct MemoryResolvedOnlineLLMProvider: Sendable, Hashable {
    var provider: MemoryOnlineLLMProvider
    var apiKey: String
}

enum MemoryLLMConfigurationStoreError: Error, LocalizedError, Sendable {
    case invalidProviderURL

    var errorDescription: String? {
        switch self {
        case .invalidProviderURL: "Memory LLM base URL is invalid."
        }
    }
}

struct MemoryLLMConfigurationStore: Sendable {
    let rootDirectory: URL
    let secretStore: any APIProviderSecretStoring

    init(
        rootDirectory: URL = Self.defaultRootDirectory(),
        secretStore: any APIProviderSecretStoring = APIProviderKeychainStore.shared
    ) {
        self.rootDirectory = rootDirectory
        self.secretStore = secretStore
    }

    static func defaultRootDirectory() -> URL {
        MemoryPaths.rootDirectory().appendingPathComponent("ModelSettings", isDirectory: true)
    }

    var settingsURL: URL {
        rootDirectory.appendingPathComponent("memory-llm-settings.json", isDirectory: false)
    }

    func loadSettings() async throws -> MemoryLLMSettings {
        let url = settingsURL
        return try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return MemoryLLMSettings()
            }
            let data = try Data(contentsOf: url)
            var settings = try Self.decoder.decode(MemoryLLMSettings.self, from: data)
            settings.normalize()
            return settings
        }.value
    }

    func saveSettings(_ settings: MemoryLLMSettings) async throws {
        let rootDirectory = rootDirectory
        let url = settingsURL
        var sanitized = settings
        sanitized.normalize()
        sanitized.providers = sanitized.providers.map { provider in
            var copy = provider
            if case .inline = copy.apiKey {
                copy.apiKey = .none
            }
            return copy
        }
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(sanitized)
            try data.write(to: url, options: .atomic)
        }.value
    }

    func resolvedAPIKey(for secret: APIProviderSecret) -> String {
        switch secret {
        case .none:
            return ""
        case .inline(let value):
            return value
        case .keychain(let account):
            return secretStore.readAPIKey(account: account) ?? ""
        }
    }

    func resolvedProvider(from settings: MemoryLLMSettings) -> MemoryResolvedOnlineLLMProvider? {
        guard let provider = settings.selectedProvider, provider.isEnabled else { return nil }
        return MemoryResolvedOnlineLLMProvider(provider: provider, apiKey: resolvedAPIKey(for: provider.apiKey))
    }

    func providerBySavingDraft(
        existing: MemoryOnlineLLMProvider,
        name: String,
        baseURL: String,
        model: String,
        rawAPIKey: String?
    ) throws -> MemoryOnlineLLMProvider {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedBaseURL), url.scheme != nil, url.host != nil else {
            throw MemoryLLMConfigurationStoreError.invalidProviderURL
        }

        var provider = existing
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.name = trimmedName.isEmpty ? existing.name : trimmedName
        provider.baseURL = trimmedBaseURL
        provider.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.apiKey = try storedSecret(rawKey: rawAPIKey, providerID: existing.id, existing: existing.apiKey)
        provider.updatedAt = .now
        return provider
    }

    private func storedSecret(rawKey: String?, providerID: String, existing: APIProviderSecret) throws -> APIProviderSecret {
        guard let rawKey else {
            if case .inline = existing {
                return .none
            }
            return existing
        }
        let account = Self.keychainAccount(providerID: providerID)
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            secretStore.deleteAPIKey(account: account)
            if let existingAccount = existing.keychainAccount, existingAccount != account {
                secretStore.deleteAPIKey(account: existingAccount)
            }
            return .none
        }
        try secretStore.saveAPIKey(trimmed, account: account)
        if let existingAccount = existing.keychainAccount, existingAccount != account {
            secretStore.deleteAPIKey(account: existingAccount)
        }
        return .keychain(account: account)
    }

    static func keychainAccount(providerID: String) -> String {
        "memory-llm-\(providerID)"
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
