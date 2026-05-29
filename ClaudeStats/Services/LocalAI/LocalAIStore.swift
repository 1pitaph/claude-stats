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
        didSet {
            defaults.set(completeLocalModeEnabled, forKey: Keys.completeLocalModeEnabled)
            if completeLocalModeEnabled {
                resetHelperRecoveryState()
            }
        }
    }
    private(set) var isIndexing = false
    private(set) var localAPIEndpoint: LocalAIOpenAIEndpoint?
    private(set) var localAPIError: String?
    private(set) var lastSemanticError: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let embeddingIndex: TranscriptEmbeddingIndex
    @ObservationIgnored private let engineFactory: LocalAIEmbeddingEngineFactory
    @ObservationIgnored private let helperManager: any LocalAIHelperManaging
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var helperFailureDates: [Date] = []
    @ObservationIgnored private var helperCooldownUntil: Date?

    private static let chunkerVersion = "semantic-chunker-v1"
    private static let helperFailureLimit = 3
    private static let helperFailureWindow: TimeInterval = 5 * 60
    private static let helperCooldownDuration: TimeInterval = 10 * 60

    init(
        modelStore: LocalAIModelStore = LocalAIModelStore(),
        embeddingIndex: TranscriptEmbeddingIndex = TranscriptEmbeddingIndex(),
        engineFactory: LocalAIEmbeddingEngineFactory = LocalAIEmbeddingEngineFactory(),
        helperManager: any LocalAIHelperManaging = LocalAIHelperManager(),
        now: @escaping () -> Date = Date.init,
        defaults: UserDefaults = .standard
    ) {
        self.modelStore = modelStore
        self.defaults = defaults
        self.embeddingIndex = embeddingIndex
        self.engineFactory = engineFactory
        self.helperManager = helperManager
        self.now = now
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
        startOpenAICompatibleServer(resetRecoveryState: true)
    }

    func stopOpenAICompatibleServer() {
        _ = try? helperManager.stop()
        resetHelperRecoveryState()
        localAPIEndpoint = nil
        localAPIError = nil
    }

    func restartOpenAICompatibleServerIfNeeded() {
        guard completeLocalModeEnabled else { return }
        let config = currentRuntimeConfig()
        _ = reconcileOpenAICompatibleServer(config: config, allowRestart: true)
    }

    func localAIEnvironment() -> CodeMemoryLocalAIEnvironment? {
        let config = currentRuntimeConfig()
        guard let localAPIEndpoint = reconcileOpenAICompatibleServer(config: config, allowRestart: completeLocalModeEnabled)
        else { return nil }
        return CodeMemoryLocalAIEnvironment(
            baseURL: localAPIEndpoint.baseURL,
            token: localAPIEndpoint.token,
            llmModelID: modelStore.selectedLLMModel.id,
            embeddingModelID: modelStore.selectedEmbeddingModel.id,
            embeddingDimensions: modelStore.selectedEmbeddingModel.dimensions,
            configurationHash: config.configHash,
            adaptersEnabled: completeLocalModeEnabled
        )
    }

    @discardableResult
    private func startOpenAICompatibleServer(
        resetRecoveryState: Bool,
        config: LocalAIHelperRuntimeConfig? = nil
    ) -> LocalAIOpenAIEndpoint? {
        if resetRecoveryState {
            resetHelperRecoveryState()
        }
        let attemptDate = now()
        if let message = activeHelperCooldownMessage(at: attemptDate) {
            localAPIEndpoint = nil
            localAPIError = message
            return nil
        }
        do {
            let config = config ?? currentRuntimeConfig()
            let endpoint = try helperManager.start(config: config)
            localAPIEndpoint = endpoint
            localAPIError = nil
            resetHelperRecoveryState()
            return endpoint
        } catch {
            localAPIEndpoint = nil
            recordHelperStartFailure(error, at: attemptDate)
            return nil
        }
    }

    private func reconcileOpenAICompatibleServer(
        config: LocalAIHelperRuntimeConfig,
        allowRestart: Bool
    ) -> LocalAIOpenAIEndpoint? {
        let checkDate = now()
        if let message = activeHelperCooldownMessage(at: checkDate) {
            localAPIEndpoint = nil
            localAPIError = message
            return nil
        }

        if let localAPIEndpoint,
           helperManager.existingProcessCanServe(config: config) {
            localAPIError = nil
            resetHelperRecoveryState()
            return localAPIEndpoint
        }

        if helperManager.existingProcessCanServe(config: config) {
            let endpoint = LocalAIOpenAIEndpoint(baseURL: config.baseURL, token: config.token)
            localAPIEndpoint = endpoint
            localAPIError = nil
            resetHelperRecoveryState()
            return endpoint
        }

        localAPIEndpoint = nil
        guard allowRestart else { return nil }
        return startOpenAICompatibleServer(resetRecoveryState: false, config: config)
    }

    private func resetHelperRecoveryState() {
        helperFailureDates.removeAll()
        helperCooldownUntil = nil
    }

    private func recordHelperStartFailure(_ error: Error, at date: Date) {
        let cutoff = date.addingTimeInterval(-Self.helperFailureWindow)
        helperFailureDates = helperFailureDates.filter { $0 >= cutoff }
        helperFailureDates.append(date)

        if helperFailureDates.count >= Self.helperFailureLimit {
            helperCooldownUntil = date.addingTimeInterval(Self.helperCooldownDuration)
            localAPIError = helperCooldownMessage(at: date)
        } else {
            localAPIError = error.localizedDescription
        }
    }

    private func activeHelperCooldownMessage(at date: Date) -> String? {
        guard let helperCooldownUntil else { return nil }
        guard helperCooldownUntil > date else {
            self.helperCooldownUntil = nil
            helperFailureDates.removeAll()
            return nil
        }
        return helperCooldownMessage(at: date)
    }

    private func helperCooldownMessage(at date: Date) -> String {
        guard let helperCooldownUntil else { return "Local AI helper is paused after repeated crashes." }
        let remainingMinutes = max(1, Int(ceil(helperCooldownUntil.timeIntervalSince(date) / 60)))
        return "Local AI helper is paused after repeated crashes. Retry in \(remainingMinutes) min."
    }

    private func currentRuntimeConfig() -> LocalAIHelperRuntimeConfig {
        LocalAIHelperRuntimeConfig(
            token: localAPIToken(),
            embeddingModelID: modelStore.selectedEmbeddingModel.id,
            llmModelID: modelStore.selectedLLMModel.id,
            embeddingDimensions: modelStore.selectedEmbeddingModel.dimensions
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
