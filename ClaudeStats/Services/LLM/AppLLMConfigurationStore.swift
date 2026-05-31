import Foundation

enum AppLLMConfigurationStoreError: Error, LocalizedError, Sendable {
    case invalidProviderURL

    var errorDescription: String? {
        switch self {
        case .invalidProviderURL: "LLM base URL is invalid."
        }
    }
}

struct AppLLMConfigurationStore: Sendable {
    let rootDirectory: URL
    let secretStore: any APIProviderSecretStoring
    let legacyMemoryStore: MemoryLLMConfigurationStore?

    init(
        rootDirectory: URL = Self.defaultRootDirectory(),
        secretStore: any APIProviderSecretStoring = APIProviderKeychainStore.shared,
        legacyMemoryStore: MemoryLLMConfigurationStore? = MemoryLLMConfigurationStore()
    ) {
        self.rootDirectory = rootDirectory
        self.secretStore = secretStore
        self.legacyMemoryStore = legacyMemoryStore
    }

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("LLM", isDirectory: true)
    }

    var settingsURL: URL {
        rootDirectory.appendingPathComponent("app-llm-settings.json", isDirectory: false)
    }

    func loadSettings() async throws -> AppLLMSettings {
        let url = settingsURL
        if FileManager.default.fileExists(atPath: url.path) {
            return try await Task.detached(priority: .utility) {
                let data = try Data(contentsOf: url)
                var settings = try Self.decoder.decode(AppLLMSettings.self, from: data)
                settings.normalize()
                return settings
            }.value
        }
        if let migrated = try await migratedLegacyMemorySettings() {
            try await saveSettings(migrated)
            return migrated
        }
        return AppLLMSettings()
    }

    func saveSettings(_ settings: AppLLMSettings) async throws {
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

    func resolvedProvider(from settings: AppLLMSettings) -> AppLLMResolvedOnlineProvider? {
        guard let provider = settings.selectedProvider, provider.isEnabled else { return nil }
        return AppLLMResolvedOnlineProvider(provider: provider, apiKey: resolvedAPIKey(for: provider.apiKey))
    }

    func providerBySavingDraft(
        existing: AppLLMProvider,
        name: String,
        baseURL: String,
        model: String,
        rawAPIKey: String?
    ) throws -> AppLLMProvider {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedBaseURL), url.scheme != nil, url.host != nil else {
            throw AppLLMConfigurationStoreError.invalidProviderURL
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

    private func migratedLegacyMemorySettings() async throws -> AppLLMSettings? {
        guard let legacyMemoryStore else { return nil }
        let legacy = try await legacyMemoryStore.loadSettings()
        var providers: [AppLLMProvider] = []
        for legacyProvider in legacy.providers {
            let providerID = legacyProvider.id.appLLMProviderIDFallback
            let resolvedAPIKey = legacyMemoryStore.resolvedAPIKey(for: legacyProvider.apiKey)
            let storedSecret = try storedSecret(
                rawKey: resolvedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                providerID: providerID,
                existing: .none
            )
            providers.append(legacyProvider.appLLMProvider(apiKey: storedSecret))
        }
        var settings = AppLLMSettings(
            mode: legacy.mode.appLLMMode,
            selectedProviderID: legacy.selectedProviderID.appLLMProviderIDFallback,
            providers: providers,
            updatedAt: legacy.updatedAt
        )
        settings.normalize()
        return settings
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
        "app-llm-\(providerID)"
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

private extension MemoryLLMMode {
    var appLLMMode: AppLLMMode {
        switch self {
        case .online: .online
        case .local: .local
        }
    }
}

private extension MemoryOnlineLLMProtocol {
    var appLLMProtocol: AppLLMProtocol {
        switch self {
        case .openAIChatCompletions: .openAIChatCompletions
        case .openAIResponses: .openAIResponses
        case .anthropicMessages: .anthropicMessages
        }
    }
}

private extension String {
    var appLLMProviderIDFallback: String {
        switch self {
        case MemoryOnlineLLMProvider.openAIChatID: AppLLMProvider.openAIChatID
        case MemoryOnlineLLMProvider.openAIResponsesID: AppLLMProvider.openAIResponsesID
        case MemoryOnlineLLMProvider.anthropicID: AppLLMProvider.anthropicID
        default: self
        }
    }
}

private extension MemoryOnlineLLMProvider {
    func appLLMProvider(apiKey: APIProviderSecret) -> AppLLMProvider {
        return AppLLMProvider(
            id: id.appLLMProviderIDFallback,
            name: name,
            protocol: self.protocol.appLLMProtocol,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            isEnabled: isEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
