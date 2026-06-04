import Foundation

enum AppLLMMode: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case online
    case local

    static var availableCases: [AppLLMMode] {
        #if CLAUDE_STATS_LITE
        [.online]
        #else
        allCases
        #endif
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .online: "Online API"
        case .local: "Local LLM"
        }
    }
}

enum AppLLMProtocol: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
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
        case .openAIChatCompletions: AppLLMProvider.openAIChatID
        case .openAIResponses: AppLLMProvider.openAIResponsesID
        case .anthropicMessages: AppLLMProvider.anthropicID
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

struct AppLLMProvider: Codable, Identifiable, Sendable, Hashable {
    static let openAIChatID = "openai-chat-completions"
    static let openAIResponsesID = "openai-responses"
    static let anthropicID = "anthropic-messages"

    var id: String
    var name: String
    var `protocol`: AppLLMProtocol
    var baseURL: String
    var model: String
    var apiKey: APIProviderSecret
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        protocol: AppLLMProtocol,
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

    static func defaultProviders(now: Date = .now) -> [AppLLMProvider] {
        [
            AppLLMProvider(
                id: AppLLMProtocol.openAIChatCompletions.defaultProviderID,
                name: "OpenAI Chat Completions",
                protocol: .openAIChatCompletions,
                baseURL: AppLLMProtocol.openAIChatCompletions.defaultBaseURL,
                model: AppLLMProtocol.openAIChatCompletions.defaultModel,
                createdAt: now,
                updatedAt: now
            ),
            AppLLMProvider(
                id: AppLLMProtocol.openAIResponses.defaultProviderID,
                name: "OpenAI Responses",
                protocol: .openAIResponses,
                baseURL: AppLLMProtocol.openAIResponses.defaultBaseURL,
                model: AppLLMProtocol.openAIResponses.defaultModel,
                createdAt: now,
                updatedAt: now
            ),
            AppLLMProvider(
                id: AppLLMProtocol.anthropicMessages.defaultProviderID,
                name: "Anthropic",
                protocol: .anthropicMessages,
                baseURL: AppLLMProtocol.anthropicMessages.defaultBaseURL,
                model: AppLLMProtocol.anthropicMessages.defaultModel,
                createdAt: now,
                updatedAt: now
            ),
        ]
    }
}

struct AppLLMSettings: Codable, Sendable, Hashable {
    var mode: AppLLMMode
    var selectedProviderID: String
    var providers: [AppLLMProvider]
    var gitCommitMessageAlgorithmPreference: GitCommitMessageAlgorithmPreference
    var updatedAt: Date

    init(
        mode: AppLLMMode = .online,
        selectedProviderID: String = AppLLMProvider.openAIResponsesID,
        providers: [AppLLMProvider] = AppLLMProvider.defaultProviders(),
        gitCommitMessageAlgorithmPreference: GitCommitMessageAlgorithmPreference = .automatic,
        updatedAt: Date = .now
    ) {
        self.mode = mode
        self.selectedProviderID = selectedProviderID
        self.providers = providers
        self.gitCommitMessageAlgorithmPreference = gitCommitMessageAlgorithmPreference
        self.updatedAt = updatedAt
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case selectedProviderID
        case providers
        case gitCommitMessageAlgorithmPreference
        case gitSummaryAlgorithmPreference
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(AppLLMMode.self, forKey: .mode) ?? .online
        selectedProviderID = try container.decodeIfPresent(String.self, forKey: .selectedProviderID) ?? AppLLMProvider.openAIResponsesID
        providers = try container.decodeIfPresent([AppLLMProvider].self, forKey: .providers) ?? AppLLMProvider.defaultProviders()
        gitCommitMessageAlgorithmPreference = try container.decodeIfPresent(
            GitCommitMessageAlgorithmPreference.self,
            forKey: .gitCommitMessageAlgorithmPreference
        ) ?? container.decodeIfPresent(
            GitCommitMessageAlgorithmPreference.self,
            forKey: .gitSummaryAlgorithmPreference
        ) ?? .automatic
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(selectedProviderID, forKey: .selectedProviderID)
        try container.encode(providers, forKey: .providers)
        try container.encode(gitCommitMessageAlgorithmPreference, forKey: .gitCommitMessageAlgorithmPreference)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var selectedProvider: AppLLMProvider? {
        providers.first { $0.id == selectedProviderID }
    }

    func provider(for protocol: AppLLMProtocol) -> AppLLMProvider? {
        providers.first { $0.protocol == `protocol` }
    }

    mutating func replaceProvider(_ provider: AppLLMProvider) {
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
        for defaultProvider in AppLLMProvider.defaultProviders(now: now) where !merged.contains(where: { $0.id == defaultProvider.id }) {
            merged.append(defaultProvider)
        }
        providers = merged.sorted { lhs, rhs in
            let lhsIndex = AppLLMProtocol.allCases.firstIndex(of: lhs.protocol) ?? 0
            let rhsIndex = AppLLMProtocol.allCases.firstIndex(of: rhs.protocol) ?? 0
            return lhsIndex < rhsIndex
        }
        if !providers.contains(where: { $0.id == selectedProviderID }) {
            selectedProviderID = AppLLMProvider.openAIResponsesID
        }
    }
}

struct AppLLMResolvedOnlineProvider: Sendable, Hashable {
    var provider: AppLLMProvider
    var apiKey: String
}

struct AppLLMGenerationEndpoint: Sendable, Hashable {
    var mode: AppLLMMode
    var `protocol`: AppLLMProtocol
    var baseURL: URL
    var apiKey: String
    var model: String
    var displayName: String
}
