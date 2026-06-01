import Foundation

enum EmbeddingModelStatus: String, Codable, Sendable, Hashable {
    case notConfigured
    case unavailable
    case downloading
    case indexing
    case failed
    case ready

    var displayName: String {
        switch self {
        case .notConfigured: "Not configured"
        case .unavailable: "Unavailable"
        case .downloading: "Downloading"
        case .indexing: "Indexing"
        case .failed: "Failed"
        case .ready: "Ready"
        }
    }
}

enum EmbeddingMode: String, Codable, Sendable, Hashable {
    case llamaGGUF
}

protocol EmbeddingEngine: Sendable {
    var status: EmbeddingModelStatus { get }
    var modelID: String { get }
    var modelRevision: String { get }
    var dimensions: Int { get }
    var embedMode: EmbeddingMode { get }
    func embed(_ texts: [String]) async throws -> [[Float]]
}

struct UnconfiguredEmbeddingEngine: EmbeddingEngine {
    let status: EmbeddingModelStatus = .notConfigured
    let modelID = "none"
    let modelRevision = "none"
    let dimensions = 0
    let embedMode: EmbeddingMode = .llamaGGUF

    func embed(_ texts: [String]) async throws -> [[Float]] {
        []
    }
}
