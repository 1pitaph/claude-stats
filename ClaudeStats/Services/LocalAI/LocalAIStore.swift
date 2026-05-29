import Foundation
import Observation

enum LocalAISemanticSearchError: Error, LocalizedError {
    case modelNotInstalled
    case noTranscriptLoader

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled: "Download a local embedding model to use semantic search."
        case .noTranscriptLoader: "No transcript loader is available for this provider."
        }
    }
}

@MainActor
@Observable
final class LocalAIStore {
    let modelStore: LocalAIModelStore
    var completeLocalModeEnabled: Bool {
        didSet { defaults.set(completeLocalModeEnabled, forKey: Keys.completeLocalModeEnabled) }
    }
    private(set) var isIndexing = false
    private(set) var localAPIEndpoint: LocalAIOpenAIEndpoint?
    private(set) var localAPIError: String?
    private(set) var lastSemanticError: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let embeddingIndex: TranscriptEmbeddingIndex
    @ObservationIgnored private let engineFactory: LocalAIEmbeddingEngineFactory
    @ObservationIgnored private let openAIService: LocalAIOpenAIService
    @ObservationIgnored private var openAIServer: LocalAIOpenAIServer?

    private static let chunkerVersion = "semantic-chunker-v1"

    init(
        modelStore: LocalAIModelStore = LocalAIModelStore(),
        embeddingIndex: TranscriptEmbeddingIndex = TranscriptEmbeddingIndex(),
        engineFactory: LocalAIEmbeddingEngineFactory = LocalAIEmbeddingEngineFactory(),
        defaults: UserDefaults = .standard
    ) {
        self.modelStore = modelStore
        self.defaults = defaults
        self.embeddingIndex = embeddingIndex
        self.engineFactory = engineFactory
        self.openAIService = LocalAIOpenAIService(modelStore: modelStore)
        self.completeLocalModeEnabled = (defaults.object(forKey: Keys.completeLocalModeEnabled) as? Bool) ?? false
    }

    var semanticSearchAvailable: Bool {
        modelStore.installedModelURL(for: modelStore.selectedEmbeddingModel) != nil
    }

    var localLLMAvailable: Bool {
        modelStore.installedModelURL(for: modelStore.selectedLLMModel) != nil
    }

    var localAPIStatusText: String {
        if let localAPIEndpoint {
            return localAPIEndpoint.baseURL.absoluteString
        }
        if let localAPIError {
            return localAPIError
        }
        return "Stopped"
    }

    var selectedEmbeddingStatus: EmbeddingModelStatus {
        let state = modelStore.installState(for: modelStore.selectedEmbeddingModel.id)
        switch state.phase {
        case .notInstalled:
            return .notConfigured
        case .downloading:
            return .downloading
        case .installed:
            return isIndexing ? .indexing : .ready
        case .failed:
            return .failed
        }
    }

    func makeEngineInfoStatus() -> EmbeddingModelStatus {
        selectedEmbeddingStatus
    }

    func search(
        query: String,
        provider: ProviderKind,
        sessions: [Session],
        messageLoader: TranscriptMessageLoader?,
        limit: Int = 40
    ) async -> [SemanticSessionSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        do {
            let prepared = try selectedModelAndEngine()
            try await ensureIndexed(
                provider: provider,
                sessions: sessions,
                messageLoader: messageLoader,
                model: prepared.model,
                engine: prepared.engine
            )
            let queryRows = try await prepared.engine.embed(["query: \(trimmed)"])
            let queryVector = queryRows.first ?? []
            let hits = try await embeddingIndex.search(
                provider: provider,
                modelID: prepared.model.id,
                modelRevision: prepared.model.modelRevision,
                chunkerVersion: Self.chunkerVersion,
                queryVector: queryVector,
                limit: limit
            )
            lastSemanticError = nil
            return hits.map {
                SemanticSessionSearchResult(sessionID: $0.sessionID, score: $0.score, matchedExcerpt: $0.excerpt)
            }
        } catch {
            lastSemanticError = error.localizedDescription
            return []
        }
    }

    func similarSessions(
        to session: Session,
        providerSessions: [Session],
        messageLoader: TranscriptMessageLoader?,
        limit: Int = 5
    ) async -> [SemanticSessionSearchResult] {
        let basis = [
            session.stats?.title,
            session.projectDisplayName,
            session.cwd,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        guard !basis.isEmpty else { return [] }
        do {
            let prepared = try selectedModelAndEngine()
            try await ensureIndexed(
                provider: session.provider,
                sessions: providerSessions,
                messageLoader: messageLoader,
                model: prepared.model,
                engine: prepared.engine
            )
            let queryRows = try await prepared.engine.embed(["query: \(basis)"])
            let queryVector = queryRows.first ?? []
            let hits = try await embeddingIndex.search(
                provider: session.provider,
                modelID: prepared.model.id,
                modelRevision: prepared.model.modelRevision,
                chunkerVersion: Self.chunkerVersion,
                queryVector: queryVector,
                limit: limit,
                excludingSessionID: session.id
            )
            lastSemanticError = nil
            return hits.map {
                SemanticSessionSearchResult(sessionID: $0.sessionID, score: $0.score, matchedExcerpt: $0.excerpt)
            }
        } catch {
            lastSemanticError = error.localizedDescription
            return []
        }
    }

    func deleteEmbeddingCache() {
        Task {
            do {
                try await embeddingIndex.deleteAll()
                lastSemanticError = nil
            } catch {
                lastSemanticError = error.localizedDescription
            }
        }
    }

    @discardableResult
    func startOpenAICompatibleServer() -> LocalAIOpenAIEndpoint? {
        do {
            let token = localAPIToken()
            let server = openAIServer ?? LocalAIOpenAIServer(service: openAIService, token: token)
            let endpoint = try server.start()
            openAIServer = server
            localAPIEndpoint = endpoint
            localAPIError = nil
            return endpoint
        } catch {
            localAPIEndpoint = nil
            localAPIError = error.localizedDescription
            return nil
        }
    }

    func stopOpenAICompatibleServer() {
        openAIServer?.stop()
        openAIServer = nil
        localAPIEndpoint = nil
        localAPIError = nil
    }

    func restartOpenAICompatibleServerIfNeeded() {
        guard completeLocalModeEnabled else { return }
        _ = startOpenAICompatibleServer()
    }

    func localAIEnvironment() -> CodeMemoryLocalAIEnvironment? {
        guard let localAPIEndpoint else { return nil }
        return CodeMemoryLocalAIEnvironment(
            baseURL: localAPIEndpoint.baseURL,
            token: localAPIEndpoint.token,
            llmModelID: modelStore.selectedLLMModel.id,
            embeddingModelID: modelStore.selectedEmbeddingModel.id,
            embeddingDimensions: modelStore.selectedEmbeddingModel.dimensions,
            adaptersEnabled: completeLocalModeEnabled
        )
    }

    private func selectedModelAndEngine() throws -> (model: LocalAIModelManifest, engine: any EmbeddingEngine) {
        let model = modelStore.selectedEmbeddingModel
        guard let url = modelStore.installedModelURL(for: model) else {
            throw LocalAISemanticSearchError.modelNotInstalled
        }
        return (model, engineFactory.makeEngine(model: model, modelURL: url))
    }

    private func ensureIndexed(
        provider: ProviderKind,
        sessions: [Session],
        messageLoader: TranscriptMessageLoader?,
        model: LocalAIModelManifest,
        engine: any EmbeddingEngine
    ) async throws {
        guard let messageLoader else { throw LocalAISemanticSearchError.noTranscriptLoader }
        isIndexing = true
        defer { isIndexing = false }

        for session in sessions {
            try Task.checkCancellation()
            let messages = await messageLoader(session)
            let chunks = Self.chunks(for: session, messages: messages)
            let hashes = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0.textHash) })
            let cached = try await embeddingIndex.cachedChunkHashes(
                provider: provider,
                sessionID: session.id,
                modelID: model.id,
                modelRevision: model.modelRevision,
                chunkerVersion: Self.chunkerVersion
            )
            guard cached != hashes else { continue }

            let texts = chunks.map { "passage: \($0.text)" }
            let vectors = try await engine.embed(texts)
            let records = zip(chunks, vectors).map { chunk, vector in
                TranscriptEmbeddingChunk(
                    sessionID: session.id,
                    chunkID: chunk.id,
                    textHash: chunk.textHash,
                    excerpt: chunk.excerpt,
                    vector: vector
                )
            }
            try await embeddingIndex.replaceChunks(
                provider: provider,
                sessionID: session.id,
                modelID: model.id,
                modelRevision: model.modelRevision,
                chunkerVersion: Self.chunkerVersion,
                dimensions: model.dimensions,
                chunks: records
            )
        }
    }

    private static func chunks(for session: Session, messages: [SessionTranscriptMessage]) -> [SemanticChunk] {
        var header = [
            session.stats?.title,
            session.projectDisplayName,
            session.cwd,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        if header.isEmpty { header = session.externalID }

        let usefulMessages = messages
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(24)

        var chunks: [SemanticChunk] = []
        var buffer = header
        var ordinal = 0
        func flush() {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let excerpt = String(trimmed.prefix(220))
            chunks.append(SemanticChunk(id: "chunk-\(ordinal)", text: trimmed, excerpt: excerpt))
            ordinal += 1
            buffer = header
        }

        for message in usefulMessages {
            let next = "\n\(message.role.displayName): \(message.text)"
            if buffer.count + next.count > 1_800 {
                flush()
            }
            buffer += next
            if chunks.count >= 5 { break }
        }
        flush()
        return chunks
    }

    private struct SemanticChunk {
        let id: String
        let text: String
        let excerpt: String

        var textHash: String {
            TranscriptEmbeddingIndex.textHash(text)
        }
    }

    private func localAPIToken() -> String {
        if let stored = defaults.string(forKey: Keys.localAPIToken), !stored.isEmpty {
            return stored
        }
        let token = "cs-local-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        defaults.set(token, forKey: Keys.localAPIToken)
        return token
    }

    private enum Keys {
        static let completeLocalModeEnabled = "LocalAI.completeLocalModeEnabled"
        static let localAPIToken = "LocalAI.openAICompatibleToken"
    }
}
