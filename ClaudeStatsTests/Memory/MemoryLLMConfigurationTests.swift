import Foundation
import Testing
@testable import ClaudeStats

@Suite("Memory LLM configuration")
struct MemoryLLMConfigurationTests {
    @Test("Runtime config writes with owner-only permissions and hash changes with model inputs")
    func runtimeConfigWriteAndHash() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("memory-runtime.json")
        let first = Self.runtimeConfig(protocolName: .openAIResponses, llmKey: "online-key", dimensions: 384)
        let same = Self.runtimeConfig(protocolName: .openAIResponses, llmKey: "online-key", dimensions: 384)
        let changedProtocol = Self.runtimeConfig(protocolName: .openAIChatCompletions, llmKey: "online-key", dimensions: 384)
        let changedKey = Self.runtimeConfig(protocolName: .openAIResponses, llmKey: "other-key", dimensions: 384)
        let changedDimensions = Self.runtimeConfig(protocolName: .openAIResponses, llmKey: "online-key", dimensions: 768)

        try first.write(to: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try #require(attrs[.posixPermissions] as? NSNumber)

        #expect(permissions.intValue & 0o777 == 0o600)
        #expect(first.configurationHash == same.configurationHash)
        #expect(first.configurationHash != changedProtocol.configurationHash)
        #expect(first.configurationHash != changedKey.configurationHash)
        #expect(first.configurationHash != changedDimensions.configurationHash)
    }

    @Test("Provider settings JSON does not persist raw API keys")
    func providerSettingsDoNotPersistRawAPIKey() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let secrets = InMemoryAPIProviderSecretStore()
        let store = MemoryLLMConfigurationStore(rootDirectory: root, secretStore: secrets)
        var settings = MemoryLLMSettings()
        let existing = try #require(settings.provider(for: .openAIResponses))
        let saved = try store.providerBySavingDraft(
            existing: existing,
            name: "OpenAI Responses",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5-mini",
            rawAPIKey: "sk-memory-test"
        )
        settings.replaceProvider(saved)

        try await store.saveSettings(settings)

        let raw = try String(contentsOf: store.settingsURL, encoding: .utf8)
        let account = MemoryLLMConfigurationStore.keychainAccount(providerID: saved.id)
        let loaded = try await store.loadSettings()

        #expect(!raw.contains("sk-memory-test"))
        #expect(raw.contains(account))
        #expect(secrets.readAPIKey(account: account) == "sk-memory-test")
        #expect(store.resolvedProvider(from: loaded)?.apiKey == "sk-memory-test")
    }

    private static func runtimeConfig(
        protocolName: CodeMemoryLLMProtocol,
        llmKey: String,
        dimensions: Int
    ) -> CodeMemoryModelRuntimeConfig {
        CodeMemoryModelRuntimeConfig(
            mode: "online",
            llm: CodeMemoryLLMEndpoint(
                protocolName: protocolName,
                baseURL: URL(string: "https://api.openai.com/v1")!,
                apiKey: llmKey,
                model: "gpt-5-mini"
            ),
            embedding: CodeMemoryEmbeddingEndpoint(
                baseURL: URL(string: "http://127.0.0.1:18765/v1")!,
                apiKey: "embedding-key",
                model: "multilingual-e5-small-gguf-q8",
                dimensions: dimensions
            )
        )
    }
}
