import CryptoKit
import Foundation

struct LocalAIHelperRuntimeConfig: Codable, Sendable, Hashable {
    static let currentSchemaVersion = 1
    static let defaultPort: UInt16 = 18_765

    var schemaVersion: Int
    var port: UInt16
    var token: String
    var embeddingModelID: String
    var llmModelID: String
    var embeddingDimensions: Int
    var configHash: String

    init(
        port: UInt16 = Self.defaultPort,
        token: String,
        embeddingModelID: String,
        llmModelID: String,
        embeddingDimensions: Int
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.port = port
        self.token = token
        self.embeddingModelID = embeddingModelID
        self.llmModelID = llmModelID
        self.embeddingDimensions = embeddingDimensions
        self.configHash = Self.computeHash(
            schemaVersion: Self.currentSchemaVersion,
            port: port,
            token: token,
            embeddingModelID: embeddingModelID,
            llmModelID: llmModelID,
            embeddingDimensions: embeddingDimensions
        )
    }

    var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)/v1")!
    }

    var healthURL: URL {
        URL(string: "http://127.0.0.1:\(port)/health")!
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.localAIHelperEncoder.encode(self)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func load(from url: URL) throws -> LocalAIHelperRuntimeConfig {
        try JSONDecoder.localAIHelperDecoder.decode(Self.self, from: Data(contentsOf: url))
    }

    static func computeHash(
        schemaVersion: Int,
        port: UInt16,
        token: String,
        embeddingModelID: String,
        llmModelID: String,
        embeddingDimensions: Int
    ) -> String {
        let payload = [
            "schema=\(schemaVersion)",
            "port=\(port)",
            "token=\(token)",
            "embedding=\(embeddingModelID)",
            "llm=\(llmModelID)",
            "dims=\(embeddingDimensions)",
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct LocalAIServiceRuntimeMetadata: Sendable, Hashable {
    var schemaVersion: Int
    var configHash: String
    var port: UInt16
}

extension JSONEncoder {
    static var localAIHelperEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var localAIHelperDecoder: JSONDecoder {
        JSONDecoder()
    }
}
