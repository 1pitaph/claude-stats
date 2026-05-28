import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class MemoryStore {
    var section: MemoryWorkspaceSection = .search
    var searchText = ""
    var searchMode: MemorySearchMode = .text
    var newSourceProviderRaw = ProviderKind.claude.rawValue
    var newSourcePath = ""

    private(set) var sources: [MemorySource] = []
    private(set) var sourceStatuses: [String: MemorySourceStatus] = [:]
    private(set) var counts: MemoryCounts = .empty
    private(set) var searchResults: [MemorySearchResult] = []
    private(set) var aiRecords: [MemoryRecord] = []
    private(set) var terminalRecords: [MemoryRecord] = []
    private(set) var selectedRecord: MemoryRecord?
    private(set) var selectedBlocks: [MemoryBlock] = []
    private(set) var isLoading = false
    private(set) var isIndexing = false
    private(set) var isSearching = false
    private(set) var lastError: String?
    private(set) var setupMessage: String?

    @ObservationIgnored private let storage: MemorySQLiteStore
    @ObservationIgnored private let sourceStore: MemorySourceFileStore
    @ObservationIgnored private var hasLoaded = false

    init(
        storage: MemorySQLiteStore = MemorySQLiteStore(),
        sourceStore: MemorySourceFileStore = MemorySourceFileStore()
    ) {
        self.storage = storage
        self.sourceStore = sourceStore
    }

    func select(_ next: MemoryWorkspaceSection) {
        section = next
    }

    func clearSearchResults() {
        searchResults = []
    }

    func loadIfNeeded(sessionStore: SessionStore) async {
        guard !hasLoaded else { return }
        await reload(sessionStore: sessionStore)
    }

    func reload(sessionStore: SessionStore) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await loadSources(sessionStore: sessionStore)
            try await refreshDerivedLists()
            hasLoaded = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func index(sessionStore: SessionStore) async {
        guard !isIndexing else { return }
        isIndexing = true
        defer { isIndexing = false }
        do {
            try await loadSources(sessionStore: sessionStore)
            try await indexAISources(sessionStore: sessionStore)
            try await refreshDerivedLists()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Log.app.error("Memory index failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func performSearch(localAI: LocalAIStore, sessionStore: SessionStore) async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            var results: [MemorySearchResult] = []
            if searchMode == .text || searchMode == .hybrid || !localAI.semanticSearchAvailable {
                results += try await storage.search(query: query)
            }

            if (searchMode == .semantic || searchMode == .hybrid), localAI.semanticSearchAvailable {
                results += await semanticResults(query: query, localAI: localAI, sessionStore: sessionStore)
            }

            var seen = Set<String>()
            searchResults = results.filter { result in
                if seen.contains(result.id) { return false }
                seen.insert(result.id)
                return true
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func selectRecord(_ record: MemoryRecord?) async {
        selectedRecord = record
        guard let record else {
            selectedBlocks = []
            return
        }
        do {
            selectedBlocks = try await storage.blocks(recordID: record.id)
            lastError = nil
        } catch {
            selectedBlocks = []
            lastError = error.localizedDescription
        }
    }

    func blocks(recordID: String) async -> [MemoryBlock] {
        do {
            let blocks = try await storage.blocks(recordID: recordID)
            lastError = nil
            return blocks
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func aiSessionItems(sessionStore: SessionStore, provider: ProviderKind) -> [MemoryAISessionItem] {
        let providerRecords = aiRecords.filter { $0.providerRaw == provider.rawValue }
        var recordsBySessionID: [String: MemoryRecord] = [:]
        var recordsByFilePath: [String: MemoryRecord] = [:]
        for record in providerRecords {
            if let externalID = record.externalID, !externalID.isEmpty {
                recordsBySessionID[externalID] = record
            }
            if let filePath = record.filePath, !filePath.isEmpty {
                recordsByFilePath[filePath] = record
            }
        }

        var usedRecordIDs = Set<String>()
        var items: [MemoryAISessionItem] = sessionStore.sessions(for: provider).map { session in
            let record = recordsBySessionID[session.id] ?? recordsByFilePath[session.filePath]
            if let record {
                usedRecordIDs.insert(record.id)
            }
            return MemoryAISessionItem(session: session, record: record)
        }

        for record in providerRecords where !usedRecordIDs.contains(record.id) {
            items.append(MemoryAISessionItem(session: nil, record: record))
        }

        return items.sorted { lhs, rhs in
            if lhs.lastActivity != rhs.lastActivity {
                return lhs.lastActivity > rhs.lastActivity
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func aiRecord(for session: Session) -> MemoryRecord? {
        aiRecords.first { record in
            record.id == aiRecordID(provider: session.provider, sessionID: session.id)
                || record.externalID == session.id
                || record.filePath == session.filePath
        }
    }

    func addSource() async {
        let path = newSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        let provider = newSourceProviderRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = MemorySource(
            id: "ai:\(provider):\(UUID().uuidString)",
            kind: .aiSessions,
            providerRaw: provider,
            title: "\(ProviderKind(rawValue: provider)?.shortName ?? provider) Memory Root",
            path: NSString(string: path).expandingTildeInPath
        )
        sources.append(source)
        newSourcePath = ""
        await persistSources()
    }

    func removeSource(_ source: MemorySource) async {
        guard !source.isDefault else { return }
        sources.removeAll { $0.id == source.id }
        do {
            try await sourceStore.save(sources)
            try await storage.deleteSource(id: source.id)
            try await refreshDerivedLists()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func revealSource(_ source: MemorySource) {
        guard let path = source.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func installShell(shell: MemoryShell, helperPath: String) {
        do {
            let backup = try MemoryShellIntegrationManager().install(shell: shell, helperPath: helperPath)
            setupMessage = backup.map { "Installed \(shell.rawValue); backup at \($0.path.memoryAbbreviatingHomeDirectory)." }
                ?? "\(shell.rawValue) integration is already installed."
            sourceStatuses = computeStatuses(for: sources)
        } catch {
            setupMessage = error.localizedDescription
        }
    }

    func uninstallShell(shell: MemoryShell) {
        do {
            let backup = try MemoryShellIntegrationManager().uninstall(shell: shell)
            setupMessage = backup.map { "Uninstalled \(shell.rawValue); backup at \($0.path.memoryAbbreviatingHomeDirectory)." }
                ?? "\(shell.rawValue) integration was not installed."
        } catch {
            setupMessage = error.localizedDescription
        }
    }

    func clearIndex() async {
        do {
            try await storage.deleteAll()
            try await refreshDerivedLists()
            searchResults = []
            selectedRecord = nil
            selectedBlocks = []
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func loadSources(sessionStore: SessionStore) async throws {
        var loaded = try await sourceStore.load()
        let defaults = defaultSources(sessionStore: sessionStore)
        var byID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        var changed = false
        for source in defaults where byID[source.id] == nil {
            byID[source.id] = source
            changed = true
        }
        loaded = byID.values.sorted(by: sourceSort)
        if changed {
            try await sourceStore.save(loaded)
        }
        sources = loaded
        sourceStatuses = computeStatuses(for: loaded)
        try await storage.upsertSources(loaded)
    }

    private func persistSources() async {
        sources.sort(by: sourceSort)
        sourceStatuses = computeStatuses(for: sources)
        do {
            try await sourceStore.save(sources)
            try await storage.upsertSources(sources)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshDerivedLists() async throws {
        counts = try await storage.counts()
        aiRecords = try await storage.records(kind: .aiSession, limit: 500)
        let all = try await storage.records(limit: 500)
        terminalRecords = all.filter { record in
            record.kind == .terminalRun || record.kind == .terminalPipe || record.kind == .shellMetadata
        }
        sourceStatuses = computeStatuses(for: sources)
    }

    private func indexAISources(sessionStore: SessionStore) async throws {
        var updatedSources = sources
        for index in updatedSources.indices {
            var source = updatedSources[index]
            guard source.kind == .aiSessions, source.isEnabled else { continue }
            guard let provider = source.providerRaw.flatMap(ProviderKind.init(rawValue:)) else {
                source.lastError = "Unsupported provider."
                updatedSources[index] = source
                continue
            }
            guard provider == .claude || provider == .codex else {
                source.lastError = "\(provider.shortName) transcripts are not supported yet."
                updatedSources[index] = source
                continue
            }
            guard let loader = sessionStore.transcriptMessageLoader(for: provider) else {
                source.lastError = "No transcript loader is available."
                updatedSources[index] = source
                continue
            }

            let sessions = await sessions(for: source, provider: provider, sessionStore: sessionStore)
            var liveIDs = Set<String>()
            for session in sessions {
                let recordID = aiRecordID(provider: provider, sessionID: session.id)
                liveIDs.insert(recordID)
                let messages = await loader(session)
                let blocks = Self.blocks(for: messages, source: source, provider: provider, sessionID: session.id, recordID: recordID)
                guard !blocks.isEmpty else { continue }
                let record = MemoryRecord(
                    id: recordID,
                    sourceID: source.id,
                    kind: .aiSession,
                    providerRaw: provider.rawValue,
                    externalID: session.id,
                    title: session.stats?.title ?? session.projectDisplayName,
                    subtitle: session.cwd ?? session.externalID,
                    projectPath: session.cwd,
                    filePath: session.filePath,
                    startedAt: session.stats?.firstActivity,
                    endedAt: session.stats?.lastActivity ?? session.lastModified,
                    createdAt: session.lastModified,
                    updatedAt: session.lastModified
                )
                try await storage.upsertRecord(record, blocks: blocks)
            }
            try await storage.pruneRecords(sourceID: source.id, keeping: liveIDs)
            source.lastIndexedAt = .now
            source.lastError = nil
            updatedSources[index] = source
        }
        sources = updatedSources.sorted(by: sourceSort)
        sourceStatuses = computeStatuses(for: sources)
        try await sourceStore.save(sources)
        try await storage.upsertSources(sources)
    }

    private func semanticResults(
        query: String,
        localAI: LocalAIStore,
        sessionStore: SessionStore
    ) async -> [MemorySearchResult] {
        var mapped: [MemorySearchResult] = []
        for provider in [ProviderKind.claude, .codex] {
            let sessions = sessionStore.sessions(for: provider)
            guard !sessions.isEmpty else { continue }
            let hits = await localAI.search(
                query: query,
                provider: provider,
                sessions: sessions,
                messageLoader: sessionStore.transcriptMessageLoader(for: provider),
                limit: 30
            )
            for hit in hits {
                let recordID = aiRecordID(provider: provider, sessionID: hit.sessionID)
                guard let record = try? await storage.record(id: recordID),
                      let block = try? await storage.firstBlock(recordID: recordID, containing: hit.matchedExcerpt) else {
                    continue
                }
                let source = sources.first { $0.id == record.sourceID }
                mapped.append(
                    MemorySearchResult(
                        block: block,
                        record: record,
                        source: source,
                        score: hit.score,
                        snippet: hit.matchedExcerpt,
                        matchKind: .semantic
                    )
                )
            }
        }
        return mapped
    }

    private func sessions(for source: MemorySource, provider: ProviderKind, sessionStore: SessionStore) async -> [Session] {
        guard !source.isDefault, let path = source.path else {
            return sessionStore.sessions(for: provider)
        }
        switch provider {
        case .claude:
            let root = URL(fileURLWithPath: path, isDirectory: true)
            let config = root.lastPathComponent == "projects" ? root.deletingLastPathComponent() : root
            return await SessionScanner(paths: ClaudePaths(configDirectory: config)).scan()
        case .codex:
            let root = URL(fileURLWithPath: path, isDirectory: true)
            let home = root.lastPathComponent == "sessions" ? root.deletingLastPathComponent() : root
            return await CodexSessionScanner(paths: CodexPaths(homeDirectory: home)).scan()
        case .gemini, .kimi, .minimax:
            return []
        }
    }

    private func defaultSources(sessionStore: SessionStore) -> [MemorySource] {
        var defaults: [MemorySource] = [
            MemorySource(
                id: MemoryDefaults.terminalSourceID,
                kind: .terminal,
                providerRaw: nil,
                title: "Terminal captures",
                path: MemoryPaths.terminalCapturesURL().path,
                isDefault: true
            ),
        ]
        for provider in [ProviderKind.claude, .codex] {
            defaults.append(
                MemorySource(
                    id: MemoryDefaults.defaultAISourceID(providerRaw: provider.rawValue),
                    kind: .aiSessions,
                    providerRaw: provider.rawValue,
                    title: "\(provider.shortName) sessions",
                    path: sessionStore.dataDirectoryPath(for: provider),
                    isDefault: true
                )
            )
        }
        return defaults
    }

    private func computeStatuses(for sources: [MemorySource]) -> [String: MemorySourceStatus] {
        Dictionary(uniqueKeysWithValues: sources.map { source in
            let unsupported: Bool = {
                guard source.kind == .aiSessions,
                      let provider = source.providerRaw.flatMap(ProviderKind.init(rawValue:)) else {
                    return false
                }
                return provider != .claude && provider != .codex
            }()

            let readable: Bool
            let readOnly: Bool
            if source.kind == .terminal {
                readable = true
                readOnly = false
            } else if let path = source.path {
                readable = FileManager.default.isReadableFile(atPath: path)
                readOnly = !FileManager.default.isWritableFile(atPath: path)
            } else {
                readable = false
                readOnly = true
            }

            return (
                source.id,
                MemorySourceStatus(
                    sourceID: source.id,
                    readable: readable,
                    readOnly: readOnly,
                    indexed: source.lastIndexedAt != nil,
                    unsupported: unsupported,
                    error: source.lastError
                )
            )
        })
    }

    private func aiRecordID(provider: ProviderKind, sessionID: String) -> String {
        "ai:\(provider.rawValue):\(sessionID)"
    }

    private static func blocks(
        for messages: [SessionTranscriptMessage],
        source: MemorySource,
        provider: ProviderKind,
        sessionID: String,
        recordID: String
    ) -> [MemoryBlock] {
        messages.enumerated().compactMap { offset, message in
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let blockID = stableBlockID(message: message, ordinal: offset)
            let role = MemoryBlockRole(rawValue: message.role.rawValue) ?? .text
            return MemoryBlock(
                id: "\(recordID):\(blockID)",
                recordID: recordID,
                sourceID: source.id,
                ordinal: offset,
                role: role,
                text: text,
                timestamp: message.timestamp,
                model: message.model,
                ref: MemoryRef.ai(provider: provider.rawValue, sessionID: sessionID, blockID: blockID),
                textHash: MemorySQLiteStore.textHash(text)
            )
        }
    }

    private static func stableBlockID(message: SessionTranscriptMessage, ordinal: Int) -> String {
        let trimmed = message.id
            .replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if trimmed.isEmpty {
            return "block-\(ordinal)"
        }
        return "\(ordinal)-\(trimmed)"
    }

    private func sourceSort(_ lhs: MemorySource, _ rhs: MemorySource) -> Bool {
        if lhs.isDefault != rhs.isDefault { return lhs.isDefault && !rhs.isDefault }
        if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

struct MemoryAISessionItem: Identifiable, Sendable, Hashable {
    let id: String
    let session: Session?
    let record: MemoryRecord?
    let providerRaw: String?
    let projectID: String
    let projectDisplayName: String
    let title: String
    let subtitle: String
    let lastActivity: Date

    var isIndexedOnly: Bool { session == nil }

    init(session: Session?, record: MemoryRecord?) {
        self.session = session
        self.record = record
        if let session {
            self.id = "session:\(session.id)"
            self.providerRaw = session.provider.rawValue
            self.projectID = session.projectDirectoryName
            self.projectDisplayName = session.projectDisplayName
            self.title = (session.stats?.title).nonEmpty ?? (record?.title).nonEmpty ?? session.externalID
            self.subtitle = session.cwd.nonEmpty ?? record?.subtitle.nonEmpty ?? session.externalID
            self.lastActivity = session.stats?.lastActivity ?? record?.endedAt ?? session.lastModified
        } else if let record {
            self.id = "record:\(record.id)"
            self.providerRaw = record.providerRaw
            self.projectID = record.projectPath.nonEmpty ?? record.sourceID
            self.projectDisplayName = record.projectPath.map { path in
                let name = URL(fileURLWithPath: path).lastPathComponent
                return name.isEmpty ? path : name
            } ?? "Memory-only"
            self.title = Optional(record.title).nonEmpty ?? record.externalID.nonEmpty ?? record.id
            self.subtitle = record.subtitle.nonEmpty ?? record.filePath.nonEmpty ?? record.id
            self.lastActivity = record.endedAt ?? record.updatedAt
        } else {
            self.id = "empty"
            self.providerRaw = nil
            self.projectID = "empty"
            self.projectDisplayName = "Memory"
            self.title = "Memory"
            self.subtitle = ""
            self.lastActivity = .distantPast
        }
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
