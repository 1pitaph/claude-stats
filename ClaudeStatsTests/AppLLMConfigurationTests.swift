import Foundation
import Testing
@testable import ClaudeStats

@Suite("App LLM configuration")
struct AppLLMConfigurationTests {
    @Test("Migrates legacy Memory LLM settings without persisting raw API keys")
    func migratesLegacyMemorySettings() async throws {
        let legacyRoot = try TempDir.make()
        let appRoot = try TempDir.make()
        defer {
            try? FileManager.default.removeItem(at: legacyRoot)
            try? FileManager.default.removeItem(at: appRoot)
        }

        let legacySecrets = InMemoryAPIProviderSecretStore()
        let appSecrets = InMemoryAPIProviderSecretStore()
        let legacyStore = MemoryLLMConfigurationStore(rootDirectory: legacyRoot, secretStore: legacySecrets)
        var legacy = MemoryLLMSettings(mode: .online, onlineExtractionEnabled: true)
        let existing = try #require(legacy.provider(for: .openAIResponses))
        let saved = try legacyStore.providerBySavingDraft(
            existing: existing,
            name: "Migrated OpenAI",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5-mini",
            rawAPIKey: "sk-legacy-memory"
        )
        legacy.replaceProvider(saved)
        try await legacyStore.saveSettings(legacy)

        let appStore = AppLLMConfigurationStore(
            rootDirectory: appRoot,
            secretStore: appSecrets,
            legacyMemoryStore: legacyStore
        )
        let migrated = try await appStore.loadSettings()
        let raw = try String(contentsOf: appStore.settingsURL, encoding: .utf8)
        let provider = try #require(migrated.provider(for: .openAIResponses))
        let account = AppLLMConfigurationStore.keychainAccount(providerID: provider.id)

        #expect(migrated.mode == .online)
        #expect(provider.name == "Migrated OpenAI")
        #expect(!raw.contains("sk-legacy-memory"))
        #expect(raw.contains(account))
        #expect(appSecrets.readAPIKey(account: account) == "sk-legacy-memory")
        #expect(appStore.resolvedProvider(from: migrated)?.apiKey == "sk-legacy-memory")
    }
}
