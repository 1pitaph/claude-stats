import Foundation

enum LocalAIModelRuntime: String, Codable, Sendable, Hashable, CaseIterable {
    case llamaGGUF

    var displayName: String {
        switch self {
        case .llamaGGUF: "llama.cpp / GGUF"
        }
    }
}

enum LocalAIModelKind: String, Codable, Sendable, Hashable, CaseIterable {
    case embedding
    case llm

    var displayName: String {
        switch self {
        case .embedding: "Embedding"
        case .llm: "LLM"
        }
    }

    var storageDirectoryName: String {
        switch self {
        case .embedding: "Embeddings"
        case .llm: "LLMs"
        }
    }
}

enum LocalAIModelSourceKind: String, Codable, Sendable, Hashable {
    case githubRelease
    case huggingFace
}

enum LocalAIEmbeddingPooling: String, Codable, Sendable, Hashable {
    case mean
    case last

    var displayName: String {
        switch self {
        case .mean: "Mean"
        case .last: "Last token"
        }
    }
}

struct LocalAIModelArtifact: Codable, Sendable, Hashable {
    let sourceKind: LocalAIModelSourceKind
    let url: URL?
    let huggingFaceRepo: String?
    let huggingFaceFile: String?
    let huggingFaceRevision: String?
    let sha256: String?
    let byteCount: Int64?

    static func github(url: URL, sha256: String?, byteCount: Int64?) -> LocalAIModelArtifact {
        LocalAIModelArtifact(
            sourceKind: .githubRelease,
            url: url,
            huggingFaceRepo: nil,
            huggingFaceFile: nil,
            huggingFaceRevision: nil,
            sha256: sha256,
            byteCount: byteCount
        )
    }

    static func huggingFace(
        repo: String,
        file: String,
        revision: String = "main",
        sha256: String? = nil,
        byteCount: Int64? = nil
    ) -> LocalAIModelArtifact {
        LocalAIModelArtifact(
            sourceKind: .huggingFace,
            url: nil,
            huggingFaceRepo: repo,
            huggingFaceFile: file,
            huggingFaceRevision: revision,
            sha256: sha256,
            byteCount: byteCount
        )
    }
}

struct LocalAIModelManifest: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let displayName: String
    let subtitle: String
    let kind: LocalAIModelKind
    let runtime: LocalAIModelRuntime
    let modelRevision: String
    let sourceRepo: String
    let sourceRevision: String
    let artifact: LocalAIModelArtifact
    let licenseName: String
    let licenseURL: URL?
    let dimensions: Int
    let maxTokens: Int
    let minMemoryGB: Int
    let parameterCount: String
    let pooling: LocalAIEmbeddingPooling
    let recommendedTier: String
    let isExperimental: Bool

    var installDirectoryName: String {
        "\(id)-\(modelRevision)"
    }

    var fileName: String {
        artifact.huggingFaceFile
            ?? artifact.url?.lastPathComponent
            ?? "\(installDirectoryName).gguf"
    }
}

enum LocalModelInstallPhase: String, Codable, Sendable, Hashable {
    case notInstalled
    case downloading
    case installed
    case failed

    var displayName: String {
        switch self {
        case .notInstalled: "Not installed"
        case .downloading: "Downloading"
        case .installed: "Installed"
        case .failed: "Failed"
        }
    }
}

struct LocalModelInstallState: Codable, Sendable, Hashable {
    let modelID: String
    var phase: LocalModelInstallPhase
    var installedPath: String?
    var bytesReceived: Int64
    var byteCount: Int64?
    var errorMessage: String?
    var installedAt: Date?

    static func notInstalled(modelID: String) -> LocalModelInstallState {
        LocalModelInstallState(
            modelID: modelID,
            phase: .notInstalled,
            installedPath: nil,
            bytesReceived: 0,
            byteCount: nil,
            errorMessage: nil,
            installedAt: nil
        )
    }
}

struct SemanticSessionSearchResult: Identifiable, Sendable, Hashable {
    let sessionID: String
    let score: Double
    let matchedExcerpt: String

    var id: String { sessionID }
}
