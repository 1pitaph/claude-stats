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

@Suite("Local AI helper runtime")
struct LocalAIHelperRuntimeTests {
    @Test("Runtime config hash is stable and changes with selected models")
    func runtimeConfigHash() {
        let first = LocalAIHelperRuntimeConfig(
            token: "token",
            embeddingModelID: "embedding-a",
            llmModelID: "llm-a",
            embeddingDimensions: 384
        )
        let same = LocalAIHelperRuntimeConfig(
            token: "token",
            embeddingModelID: "embedding-a",
            llmModelID: "llm-a",
            embeddingDimensions: 384
        )
        let changed = LocalAIHelperRuntimeConfig(
            token: "token",
            embeddingModelID: "embedding-b",
            llmModelID: "llm-a",
            embeddingDimensions: 384
        )

        #expect(first.configHash == same.configHash)
        #expect(first.configHash != changed.configHash)
        #expect(first.baseURL.absoluteString == "http://127.0.0.1:18765/v1")
    }

    @Test("Runtime config writes with owner-only permissions and round-trips")
    func runtimeConfigWriteRoundTrip() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("runtime.json")
        let config = LocalAIHelperRuntimeConfig(
            token: "secret",
            embeddingModelID: "embedding",
            llmModelID: "llm",
            embeddingDimensions: 384
        )

        try config.write(to: url)
        let decoded = try LocalAIHelperRuntimeConfig.load(from: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try #require(attrs[.posixPermissions] as? NSNumber)

        #expect(decoded == config)
        #expect(permissions.intValue & 0o777 == 0o600)
    }
}

@MainActor
@Suite("Local AI helper recovery")
struct LocalAIHelperRecoveryTests {
    @Test("Healthy helper exposes a local AI environment")
    func healthyHelperReturnsEnvironment() throws {
        let helper = FakeLocalAIHelperManager()
        let store = try Self.makeStore(helper: helper)
        store.completeLocalModeEnabled = true

        let endpoint = try #require(store.startOpenAICompatibleServer())
        let environment = try #require(store.localAIEnvironment())

        #expect(environment.baseURL == endpoint.baseURL)
        #expect(environment.adaptersEnabled)
        #expect(helper.startCallCount == 1)
    }

    @Test("Stale endpoint restarts before returning environment")
    func staleEndpointRestarts() throws {
        let helper = FakeLocalAIHelperManager()
        let store = try Self.makeStore(helper: helper)
        store.completeLocalModeEnabled = true

        _ = try #require(store.startOpenAICompatibleServer())
        helper.isHealthy = false

        let environment = try #require(store.localAIEnvironment())

        #expect(environment.baseURL.absoluteString == "http://127.0.0.1:18765/v1")
        #expect(helper.startCallCount == 2)
        #expect(store.localAPIError == nil)
    }

    @Test("Repeated restart failures enter cooldown")
    func repeatedFailuresEnterCooldown() throws {
        let helper = FakeLocalAIHelperManager()
        helper.startResults = [
            .failure(FakeLocalAIHelperError.startFailed),
            .failure(FakeLocalAIHelperError.startFailed),
            .failure(FakeLocalAIHelperError.startFailed),
            .success(Self.endpoint(token: "unused")),
        ]
        let store = try Self.makeStore(helper: helper)
        store.completeLocalModeEnabled = true

        store.restartOpenAICompatibleServerIfNeeded()
        store.restartOpenAICompatibleServerIfNeeded()
        store.restartOpenAICompatibleServerIfNeeded()
        store.restartOpenAICompatibleServerIfNeeded()

        #expect(helper.startCallCount == 3)
        #expect(store.localAPIEndpoint == nil)
        #expect(store.localAPIStatusText.contains("paused after repeated crashes"))
    }

    @Test("Manual start clears cooldown and retries")
    func manualStartClearsCooldown() throws {
        let helper = FakeLocalAIHelperManager()
        helper.startResults = [
            .failure(FakeLocalAIHelperError.startFailed),
            .failure(FakeLocalAIHelperError.startFailed),
            .failure(FakeLocalAIHelperError.startFailed),
            .success(Self.endpoint(token: "manual")),
        ]
        let store = try Self.makeStore(helper: helper)
        store.completeLocalModeEnabled = true

        store.restartOpenAICompatibleServerIfNeeded()
        store.restartOpenAICompatibleServerIfNeeded()
        store.restartOpenAICompatibleServerIfNeeded()
        let endpoint = try #require(store.startOpenAICompatibleServer())

        #expect(helper.startCallCount == 4)
        #expect(endpoint.baseURL.absoluteString == "http://127.0.0.1:18765/v1")
        #expect(store.localAPIError == nil)
    }

    private static func makeStore(helper: FakeLocalAIHelperManager) throws -> LocalAIStore {
        let suiteName = "LocalAIHelperRecoveryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return LocalAIStore(
            helperManager: helper,
            now: { Date(timeIntervalSince1970: 1_000) },
            defaults: defaults
        )
    }

    private static func endpoint(token: String) -> LocalAIOpenAIEndpoint {
        LocalAIOpenAIEndpoint(baseURL: URL(string: "http://127.0.0.1:18765/v1")!, token: token)
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

private enum FakeLocalAIHelperError: Error, LocalizedError {
    case startFailed

    var errorDescription: String? {
        "helper failed"
    }
}

private final class FakeLocalAIHelperManager: LocalAIHelperManaging, @unchecked Sendable {
    var isHealthy = false
    var startResults: [Result<LocalAIOpenAIEndpoint, Error>] = []
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start(config: LocalAIHelperRuntimeConfig) throws -> LocalAIOpenAIEndpoint {
        startCallCount += 1
        let result = startResults.isEmpty
            ? .success(LocalAIOpenAIEndpoint(baseURL: config.baseURL, token: config.token))
            : startResults.removeFirst()
        switch result {
        case .success(let endpoint):
            isHealthy = true
            return LocalAIOpenAIEndpoint(baseURL: endpoint.baseURL, token: config.token)
        case .failure(let error):
            isHealthy = false
            throw error
        }
    }

    func stop() throws -> Bool {
        stopCallCount += 1
        isHealthy = false
        return true
    }

    func existingProcessCanServe(config: LocalAIHelperRuntimeConfig) -> Bool {
        isHealthy
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
