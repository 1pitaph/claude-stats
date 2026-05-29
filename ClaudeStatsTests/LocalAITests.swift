import Foundation
import Testing
@testable import ClaudeStats

@Suite("Local AI model catalog")
struct LocalAIModelCatalogTests {
    @Test("Built-in manifests are Codable and preserve embedding metadata")
    func manifestRoundTrip() throws {
        let model = try #require(LocalAIModelCatalog.builtInModels.first)
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(LocalAIModelManifest.self, from: data)

        #expect(decoded.id == "multilingual-e5-small-gguf-q8")
        #expect(decoded.runtime == .llamaGGUF)
        #expect(decoded.dimensions == 384)
        #expect(decoded.pooling == .mean)
        #expect(decoded.artifact.url?.absoluteString.hasPrefix("https://github.com/1pitaph/claude-stats/releases/download/local-models-v1/") == true)
    }

    @Test("Recommendation keeps low-memory Apple Silicon Macs on small model")
    func recommendedModelForSmallMemory() {
        #expect(LocalAIModelCatalog.recommendedModelID(memoryBytes: 8 * 1_073_741_824) == "multilingual-e5-small-gguf-q8")
    }

    @Test("Recommendation prefers base on Apple Silicon with enough memory")
    func recommendedModelForLargeMemory() {
        #expect(LocalAIModelCatalog.recommendedModelID(memoryBytes: 16 * 1_073_741_824) == "multilingual-e5-base-gguf-q8")
    }

    @Test("Built-in LLM manifests download from Hugging Face")
    func llmManifestsDownloadFromHuggingFace() throws {
        let model = try #require(LocalAIModelCatalog.builtInLLMModels.first)

        #expect(model.kind == .llm)
        #expect(model.artifact.sourceKind == .huggingFace)
        #expect(model.artifact.huggingFaceRepo?.isEmpty == false)
        #expect(model.artifact.huggingFaceFile?.hasSuffix(".gguf") == true)
    }

    @Test("LLM recommendation scales to larger Macs")
    func recommendedLLMForLargeMemory() {
        #expect(
            LocalAIModelCatalog.recommendedLLMModelID(memoryBytes: 64 * 1_073_741_824)
                == "qwen3-30b-a3b-instruct-2507-q5-k-m"
        )
    }
}

@Suite("Local AI file verification")
struct LocalAIModelFileVerifierTests {
    @Test("SHA-256 verifier reports mismatches")
    func checksumMismatch() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture.gguf")
        try Data("fixture".utf8).write(to: file)

        #expect(throws: LocalAIModelStoreError.self) {
            try LocalAIModelFileVerifier.verifySHA256(fileURL: file, expected: String(repeating: "0", count: 64))
        }
    }
}

@MainActor
@Suite("Local AI model store")
struct LocalAIModelStoreTests {
    @Test("Interrupted persisted downloads become retryable on launch")
    func interruptedPersistedDownloadsBecomeRetryable() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "LocalAIModelStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = Self.customModel(id: "test-interrupted-\(UUID().uuidString)")
        let stateURL = root.appendingPathComponent("models-state.json")
        let payload = PersistedLocalAIState(
            customModels: [model],
            installStates: [
                LocalModelInstallState(
                    modelID: model.id,
                    phase: .downloading,
                    installedPath: nil,
                    bytesReceived: 0,
                    byteCount: 42,
                    errorMessage: nil,
                    installedAt: nil
                ),
            ]
        )
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(payload).write(to: stateURL)

        let store = LocalAIModelStore(defaults: defaults, stateURL: stateURL)
        let recovered = store.installState(for: model.id)

        #expect(recovered.phase == .failed)
        #expect(recovered.errorMessage == "Download was interrupted. Click Retry to resume.")
        #expect(recovered.byteCount == 42)

        let saved = try JSONDecoder().decode(PersistedLocalAIState.self, from: Data(contentsOf: stateURL))
        #expect(saved.installStates.first?.phase == .failed)
    }

    private static func customModel(id: String) -> LocalAIModelManifest {
        LocalAIModelManifest(
            id: id,
            displayName: "Test Model",
            subtitle: "Fixture",
            kind: .embedding,
            runtime: .llamaGGUF,
            modelRevision: "test-v1",
            sourceRepo: "fixture/model",
            sourceRevision: "main",
            artifact: .github(url: URL(string: "https://example.com/model.gguf")!, sha256: nil, byteCount: 42),
            licenseName: "MIT",
            licenseURL: nil,
            dimensions: 3,
            maxTokens: 16,
            minMemoryGB: 1,
            parameterCount: "Fixture",
            pooling: .mean,
            recommendedTier: "Fixture",
            isExperimental: true
        )
    }

    private struct PersistedLocalAIState: Codable {
        let customModels: [LocalAIModelManifest]
        let installStates: [LocalModelInstallState]
    }
}

@Suite("Transcript embedding index")
struct TranscriptEmbeddingIndexTests {
    @Test("Vector blobs round-trip and cosine search ranks best session")
    func vectorRoundTripAndRanking() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = TranscriptEmbeddingIndex(url: root.appendingPathComponent("embeddings.sqlite"))

        try await index.replaceChunks(
            provider: .claude,
            sessionID: "s1",
            modelID: "multilingual-e5-small-gguf-q8",
            modelRevision: "gguf-q8-v1",
            chunkerVersion: "test-chunker",
            dimensions: 3,
            chunks: [
                TranscriptEmbeddingChunk(
                    sessionID: "s1",
                    chunkID: "chunk-0",
                    textHash: "hash-a",
                    excerpt: "SwiftUI settings work",
                    vector: [1, 0, 0]
                ),
                TranscriptEmbeddingChunk(
                    sessionID: "s1",
                    chunkID: "chunk-1",
                    textHash: "hash-b",
                    excerpt: "Local embedding cache",
                    vector: [0.8, 0.2, 0]
                ),
            ]
        )
        try await index.replaceChunks(
            provider: .claude,
            sessionID: "s2",
            modelID: "multilingual-e5-small-gguf-q8",
            modelRevision: "gguf-q8-v1",
            chunkerVersion: "test-chunker",
            dimensions: 3,
            chunks: [
                TranscriptEmbeddingChunk(
                    sessionID: "s2",
                    chunkID: "chunk-0",
                    textHash: "hash-c",
                    excerpt: "Network proxy traces",
                    vector: [0, 1, 0]
                ),
            ]
        )

        let cached = try await index.cachedChunkHashes(
            provider: .claude,
            sessionID: "s1",
            modelID: "multilingual-e5-small-gguf-q8",
            modelRevision: "gguf-q8-v1",
            chunkerVersion: "test-chunker"
        )
        #expect(cached == ["chunk-0": "hash-a", "chunk-1": "hash-b"])

        let hits = try await index.search(
            provider: .claude,
            modelID: "multilingual-e5-small-gguf-q8",
            modelRevision: "gguf-q8-v1",
            chunkerVersion: "test-chunker",
            queryVector: [1, 0, 0],
            limit: 2
        )
        #expect(hits.map(\.sessionID) == ["s1", "s2"])
        #expect(hits.first?.excerpt == "SwiftUI settings work")

        let excludingCurrent = try await index.search(
            provider: .claude,
            modelID: "multilingual-e5-small-gguf-q8",
            modelRevision: "gguf-q8-v1",
            chunkerVersion: "test-chunker",
            queryVector: [1, 0, 0],
            limit: 2,
            excludingSessionID: "s1"
        )
        #expect(excludingCurrent.map(\.sessionID) == ["s2"])
    }
}
