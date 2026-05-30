import CryptoKit
import Foundation

enum CodeMemoryLLMProtocol: String, Codable, CaseIterable, Sendable, Hashable {
    case openAIChatCompletions = "openai_chat_completions"
    case openAIResponses = "openai_responses"
    case anthropicMessages = "anthropic_messages"
}

struct CodeMemoryLLMEndpoint: Codable, Sendable, Hashable {
    var protocolName: CodeMemoryLLMProtocol
    var baseURL: URL
    var apiKey: String
    var model: String

    init(protocolName: CodeMemoryLLMProtocol, baseURL: URL, apiKey: String, model: String) {
        self.protocolName = protocolName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    private enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case baseURL = "base_url"
        case apiKey = "api_key"
        case model
    }
}

struct CodeMemoryEmbeddingEndpoint: Codable, Sendable, Hashable {
    var baseURL: URL
    var apiKey: String
    var model: String
    var dimensions: Int

    private enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case apiKey = "api_key"
        case model
        case dimensions
    }
}

struct CodeMemoryModelRuntimeConfig: Codable, Sendable, Hashable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var mode: String
    var llm: CodeMemoryLLMEndpoint
    var embedding: CodeMemoryEmbeddingEndpoint
    var mem0Enabled: Bool
    var graphitiEnabled: Bool
    var configurationHash: String

    init(
        mode: String,
        llm: CodeMemoryLLMEndpoint,
        embedding: CodeMemoryEmbeddingEndpoint,
        mem0Enabled: Bool = true,
        graphitiEnabled: Bool = true
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.mode = mode
        self.llm = llm
        self.embedding = embedding
        self.mem0Enabled = mem0Enabled
        self.graphitiEnabled = graphitiEnabled
        self.configurationHash = Self.computeHash(
            schemaVersion: Self.currentSchemaVersion,
            mode: mode,
            llm: llm,
            embedding: embedding,
            mem0Enabled: mem0Enabled,
            graphitiEnabled: graphitiEnabled
        )
    }

    var adaptersEnabled: Bool {
        mem0Enabled || graphitiEnabled
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.memoryEncoder.encode(self)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func computeHash(
        schemaVersion: Int,
        mode: String,
        llm: CodeMemoryLLMEndpoint,
        embedding: CodeMemoryEmbeddingEndpoint,
        mem0Enabled: Bool,
        graphitiEnabled: Bool
    ) -> String {
        let payload = [
            "schema=\(schemaVersion)",
            "mode=\(mode)",
            "llm_protocol=\(llm.protocolName.rawValue)",
            "llm_base_url=\(llm.baseURL.absoluteString)",
            "llm_model=\(llm.model)",
            "llm_key_digest=\(secretDigest(llm.apiKey))",
            "embedding_base_url=\(embedding.baseURL.absoluteString)",
            "embedding_model=\(embedding.model)",
            "embedding_dims=\(embedding.dimensions)",
            "embedding_key_digest=\(secretDigest(embedding.apiKey))",
            "mem0=\(mem0Enabled)",
            "graphiti=\(graphitiEnabled)",
        ].joined(separator: "\n")
        return digest(payload)
    }

    private static func secretDigest(_ value: String) -> String {
        digest("secret:\(value)")
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case mode
        case llm
        case embedding
        case mem0Enabled = "mem0_enabled"
        case graphitiEnabled = "graphiti_enabled"
        case configurationHash = "configuration_hash"
    }
}
