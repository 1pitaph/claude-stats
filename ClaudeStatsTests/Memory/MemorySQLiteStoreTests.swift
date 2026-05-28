import Foundation
import Testing
@testable import ClaudeStats

@Suite("Memory SQLite store")
struct MemorySQLiteStoreTests {
    @Test("AI destination raw values round trip")
    func aiDestinationRawValuesRoundTrip() {
        let values: [MemoryAIDestination] = [
            .overview,
            .analysis,
            .session("project::session"),
            .indexedRecord("ai:claude:memory-only"),
        ]

        for value in values {
            #expect(MemoryAIDestination(rawValue: value.rawValue) == value)
        }
    }

    @MainActor
    @Test("AI session items merge live sessions with memory-only records")
    func aiSessionItemsMergeLiveAndMemoryOnlyRecords() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let live = Self.session(
            id: "project::live",
            externalID: "live",
            filePath: root.appendingPathComponent("live.jsonl").path,
            cwd: root.appendingPathComponent("project").path,
            lastModified: Date(timeIntervalSince1970: 100)
        )
        let provider = MemoryTestProvider(sessions: [live])
        let sessionStore = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table
        )
        await sessionStore.refresh()

        let storage = MemorySQLiteStore(url: root.appendingPathComponent("memory.sqlite3"))
        let source = MemorySource(
            id: MemoryDefaults.defaultAISourceID(providerRaw: ProviderKind.claude.rawValue),
            kind: .aiSessions,
            providerRaw: ProviderKind.claude.rawValue,
            title: "Claude sessions",
            path: root.path,
            isDefault: true
        )
        try await storage.upsertSources([source])

        let liveRecord = MemoryRecord(
            id: "ai:claude:project::live",
            sourceID: source.id,
            kind: .aiSession,
            providerRaw: ProviderKind.claude.rawValue,
            externalID: live.id,
            title: "Indexed live",
            filePath: live.filePath,
            endedAt: Date(timeIntervalSince1970: 120)
        )
        let memoryOnlyRecord = MemoryRecord(
            id: "ai:claude:memory-only",
            sourceID: source.id,
            kind: .aiSession,
            providerRaw: ProviderKind.claude.rawValue,
            externalID: "memory-only",
            title: "Memory-only session",
            projectPath: root.appendingPathComponent("external").path,
            filePath: root.appendingPathComponent("external/session.jsonl").path,
            endedAt: Date(timeIntervalSince1970: 90)
        )
        try await storage.upsertRecord(liveRecord, blocks: [
            Self.block(record: liveRecord, text: "live block"),
        ])
        try await storage.upsertRecord(memoryOnlyRecord, blocks: [
            Self.block(record: memoryOnlyRecord, text: "memory block"),
        ])

        let memory = MemoryStore(
            storage: storage,
            sourceStore: MemorySourceFileStore(url: root.appendingPathComponent("sources.json"))
        )
        await memory.reload(sessionStore: sessionStore)

        let items = memory.aiSessionItems(sessionStore: sessionStore, provider: .claude)
        #expect(items.count == 2)
        #expect(items.contains { $0.session?.id == live.id && $0.record?.id == liveRecord.id && !$0.isIndexedOnly })
        #expect(items.contains { $0.record?.id == memoryOnlyRecord.id && $0.isIndexedOnly })
    }

    @Test("FTS insert search and prune records")
    func ftsInsertSearchAndPrune() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MemorySQLiteStore(url: root.appendingPathComponent("memory.sqlite3"))
        let source = MemorySource(
            id: "ai:claude:default",
            kind: .aiSessions,
            providerRaw: "claude",
            title: "Claude sessions",
            path: root.path,
            isDefault: true
        )
        try await storage.upsertSources([source])

        let record = MemoryRecord(
            id: "ai:claude:session-1",
            sourceID: source.id,
            kind: .aiSession,
            providerRaw: "claude",
            externalID: "session-1",
            title: "Parser work"
        )
        let block = MemoryBlock(
            id: "ai:claude:session-1:block-0",
            recordID: record.id,
            sourceID: source.id,
            ordinal: 0,
            role: .assistant,
            text: "Needle context for parser refactor",
            ref: MemoryRef.ai(provider: "claude", sessionID: "session-1", blockID: "block-0"),
            textHash: MemorySQLiteStore.textHash("Needle context for parser refactor")
        )
        try await storage.upsertRecord(record, blocks: [block])

        let hits = try await storage.search(query: "needle")
        #expect(hits.count == 1)
        #expect(hits.first?.block.ref == "memory://ai/claude/session-1/block-0")

        try await storage.pruneRecords(sourceID: source.id, keeping: [])
        let afterPrune = try await storage.search(query: "needle")
        #expect(afterPrune.isEmpty)
    }

    @Test("Terminal writer stores run captures and JSONL")
    func terminalWriterStoresRunCaptures() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MemorySQLiteStore(url: root.appendingPathComponent("memory.sqlite3"))
        let writer = MemoryTerminalCaptureWriter(
            storage: storage,
            jsonlURL: root.appendingPathComponent("terminal.jsonl")
        )

        let record = try await writer.saveRunCapture(
            command: "/bin/echo",
            arguments: ["ok"],
            cwd: root.path,
            stdout: "ok\n",
            stderr: "",
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 11),
            truncated: false
        )

        let blocks = try await storage.blocks(recordID: record.id)
        #expect(blocks.first?.text == "ok\n")
        #expect(try String(contentsOf: root.appendingPathComponent("terminal.jsonl"), encoding: .utf8).contains(record.id))
    }

    @Test("Source JSON round-trips")
    func sourceJSONRoundTrip() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemorySourceFileStore(url: root.appendingPathComponent("sources.json"))
        let sources = [
            MemorySource(
                id: "terminal:default",
                kind: .terminal,
                providerRaw: nil,
                title: "Terminal",
                path: root.path,
                isDefault: true
            ),
        ]
        try await store.save(sources)
        #expect(try await store.load() == sources)
    }

    private static func session(
        id: String,
        externalID: String,
        filePath: String,
        cwd: String,
        lastModified: Date
    ) -> Session {
        Session(
            id: id,
            externalID: externalID,
            provider: .claude,
            projectDirectoryName: "project",
            filePath: filePath,
            cwd: cwd,
            lastModified: lastModified,
            fileSize: 42,
            stats: nil
        )
    }

    private static func block(record: MemoryRecord, text: String) -> MemoryBlock {
        MemoryBlock(
            id: "\(record.id):block-0",
            recordID: record.id,
            sourceID: record.sourceID,
            ordinal: 0,
            role: .assistant,
            text: text,
            ref: MemoryRef.ai(provider: record.providerRaw ?? "claude", sessionID: record.externalID ?? record.id, blockID: "block-0"),
            textHash: MemorySQLiteStore.textHash(text)
        )
    }
}

private final class MemoryTestProvider: Provider, @unchecked Sendable {
    let kind: ProviderKind = .claude
    let dataDirectoryExists = true
    let dataDirectoryPath: String? = "/tmp/claude"

    private let sessions: [Session]

    init(sessions: [Session]) {
        self.sessions = sessions
    }

    func discoverSessions() async -> [Session] {
        sessions
    }

    func parse(_ session: Session) async -> SessionStats? {
        SessionStats(
            title: "Live session",
            messageCount: 1,
            firstActivity: nil,
            lastActivity: session.lastModified,
            models: [],
            timeline: []
        )
    }
}

@Suite("Memory shell integration")
struct MemoryShellIntegrationTests {
    @Test("Renderer contains markers and metadata command")
    func rendererContainsMarkers() {
        let text = MemoryShellIntegrationManager().render(shell: .zsh, helperPath: "/tmp/claude-stats-memory")
        #expect(text.contains("Claude Stats Memory"))
        #expect(text.contains("record-shell"))
        #expect(text.contains("--command"))
    }
}
