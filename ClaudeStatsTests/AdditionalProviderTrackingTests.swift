import Foundation
import Testing
@testable import ClaudeStats

@Suite("Additional provider tracking")
struct AdditionalProviderTrackingTests {
    @Test("OpenCode reads SQLite sessions, usage, messages, and commands")
    func openCodeSQLiteTracking() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let dbURL = root.appendingPathComponent("opencode.db")
        let db = try SQLiteConnection(url: dbURL)
        try db.execute("""
        CREATE TABLE session (
            id TEXT PRIMARY KEY,
            directory TEXT,
            title TEXT,
            model TEXT,
            time_created INTEGER,
            time_updated INTEGER,
            cost REAL,
            tokens_input INTEGER,
            tokens_output INTEGER,
            tokens_reasoning INTEGER,
            tokens_cache_read INTEGER,
            tokens_cache_write INTEGER
        );
        CREATE TABLE message (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            time_created INTEGER,
            data TEXT
        );
        CREATE TABLE part (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            time_created INTEGER,
            data TEXT
        );
        """)
        try db.execute("""
        INSERT INTO session VALUES (
            'oc-1', '/tmp/opencode-demo', 'OpenCode task', 'gpt-5',
            1760000000000, 1760003600000, 0.42, 10, 20, 3, 4, 5
        );
        INSERT INTO message VALUES
            ('m1', 'oc-1', 1760000000000, '{"role":"user","content":"build it"}'),
            ('m2', 'oc-1', 1760000100000, '{"role":"assistant","content":"done"}');
        INSERT INTO part VALUES (
            'p1', 'oc-1', 1760000200000,
            '{"type":"tool_call","tool_name":"shell","arguments":{"command":"git status"}}'
        );
        """)

        let provider = OpenCodeProvider(
            paths: OpenCodePaths(dataDirectories: [root]),
            pricing: TestPricing.table
        )
        let sessions = await provider.discoverSessions()
        let session = try #require(sessions.first)
        #expect(session.provider == .opencode)
        #expect(session.cwd == "/tmp/opencode-demo")

        let stats = try #require(await provider.parse(session))
        let model = try #require(stats.models.first)
        #expect(stats.title == "OpenCode task")
        #expect(stats.messageCount == 2)
        #expect(model.usage.inputTokens == 10)
        #expect(model.usage.outputTokens == 23)
        #expect(model.usage.cacheReadTokens == 4)
        #expect(model.usage.cacheCreation5mTokens == 5)
        #expect(model.estimatedCost == 0.42)

        let messages = await provider.transcriptMessages(for: session)
        #expect(messages.map(\.text) == ["build it", "done"])
        let commands = await provider.executedCommands(for: session)
        #expect(commands.map(\.command) == ["git status"])
    }

    @Test("Kiro prefers JSONL sessions over archives and estimates token usage")
    func kiroJSONLAndArchiveTracking() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent(".kiro", isDirectory: true)
        let sessionsDir = home.appendingPathComponent("sessions/cli", isDirectory: true)
        let archiveDir = root.appendingPathComponent("archives", isDirectory: true)
        let metaURL = sessionsDir.appendingPathComponent("kiro-1.json")
        let jsonlURL = sessionsDir.appendingPathComponent("kiro-1.jsonl")
        try TempDir.write("""
        {"session_id":"kiro-1","cwd":"/tmp/kiro-demo","title":"Kiro file session","created_at":"2026-01-10T09:00:00Z","updated_at":"2026-01-10T09:05:00Z"}
        """, to: metaURL)
        try TempDir.write([
            #"{"version":"v1","kind":"Prompt","data":{"content":"hello"},"timestamp":"2026-01-10T09:00:00Z"}"#,
            #"{"version":"v1","kind":"AssistantMessage","data":{"content":"world"},"timestamp":"2026-01-10T09:01:00Z"}"#,
        ].joined(separator: "\n") + "\n", to: jsonlURL)
        try TempDir.write("""
        {"session_id":"kiro-1","cwd":"/tmp/archive-demo","title":"Archive duplicate","messages":[{"role":"user","content":"archive"}]}
        """, to: archiveDir.appendingPathComponent("kiro-1.json"))

        let provider = KiroProvider(
            paths: KiroPaths(
                homeDirectory: home,
                applicationSupportDatabase: root.appendingPathComponent("missing-app.sqlite3"),
                localShareDatabase: root.appendingPathComponent("missing-local.sqlite3"),
                archiveDirectory: archiveDir
            ),
            pricing: TestPricing.table
        )

        let sessions = await provider.discoverSessions()
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(
            URL(fileURLWithPath: session.filePath).resolvingSymlinksInPath().path
                == metaURL.resolvingSymlinksInPath().path
        )
        #expect(session.cwd == "/tmp/kiro-demo")

        let stats = try #require(await provider.parse(session))
        #expect(stats.title == "Kiro file session")
        #expect(stats.messageCount == 2)
        let usage = try #require(stats.models.first?.usage)
        #expect(usage.cacheCreation5mTokens == 2)
        #expect(usage.cacheReadTokens == 2)
        #expect(usage.outputTokens == 2)
    }

    @Test("Kiro reads conversations_v2 SQLite and archive snapshots")
    func kiroSQLiteAndArchiveTracking() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let dbURL = root.appendingPathComponent("data.sqlite3")
        let db = try SQLiteConnection(url: dbURL)
        try db.execute("""
        CREATE TABLE conversations_v2 (
            key TEXT,
            conversation_id TEXT,
            value TEXT,
            created_at INTEGER,
            updated_at INTEGER
        );
        """)
        try db.execute("""
        INSERT INTO conversations_v2 VALUES (
            '/tmp/kiro-sql',
            'kiro-sql',
            '{"title":"SQL Kiro","model_info":{"model":"claude-sonnet-4-6"},"transcript":[{"role":"user","content":"sql hi"},{"role":"assistant","content":"sql done","usage":{"input_tokens":3,"output_tokens":7}}]}',
            1760000000000,
            1760000100000
        );
        """)
        let archiveDir = root.appendingPathComponent("archives", isDirectory: true)
        try TempDir.write("""
        {"session_id":"kiro-archive","cwd":"/tmp/kiro-archive","title":"Archived Kiro","messages":[{"role":"user","content":"archived hi"},{"role":"assistant","content":"archived done"}]}
        """, to: archiveDir.appendingPathComponent("kiro-archive.json"))

        let provider = KiroProvider(
            paths: KiroPaths(
                homeDirectory: root.appendingPathComponent(".kiro", isDirectory: true),
                applicationSupportDatabase: dbURL,
                localShareDatabase: root.appendingPathComponent("missing.sqlite3"),
                archiveDirectory: archiveDir
            ),
            pricing: TestPricing.table
        )
        let sessions = await provider.discoverSessions()
        #expect(Set(sessions.map(\.externalID)) == ["kiro-sql", "kiro-archive"])
        let sqlSession = try #require(sessions.first { $0.externalID == "kiro-sql" })
        let sqlStats = try #require(await provider.parse(sqlSession))
        #expect(sqlStats.title == "SQL Kiro")
        #expect(sqlStats.models.first?.model == "claude-sonnet-4-6")
        #expect(sqlStats.models.first?.usage.inputTokens == 3)
        #expect(sqlStats.models.first?.usage.outputTokens == 7)

        let archiveSession = try #require(sessions.first { $0.externalID == "kiro-archive" })
        let archiveStats = try #require(await provider.parse(archiveSession))
        #expect(archiveStats.title == "Archived Kiro")
        #expect(archiveStats.messageCount == 2)
    }

    @Test("Hermes reads state database usage, fallback token counts, messages, and commands")
    func hermesSQLiteTracking() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let dbURL = root.appendingPathComponent("state.db")
        let db = try SQLiteConnection(url: dbURL)
        try db.execute("""
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            title TEXT,
            model TEXT,
            cwd TEXT,
            started_at TEXT,
            updated_at TEXT,
            input_tokens INTEGER,
            output_tokens INTEGER,
            cache_read_tokens INTEGER,
            cache_write_tokens INTEGER,
            cost REAL,
            token_count INTEGER
        );
        CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            role TEXT,
            content TEXT,
            created_at TEXT,
            token_count INTEGER,
            tool_name TEXT,
            tool_calls TEXT
        );
        """)
        try db.execute("""
        INSERT INTO sessions VALUES
            ('hermes-1', 'Hermes task', 'nous-hermes', '/tmp/hermes-demo', '2026-01-10T09:00:00Z', '2026-01-10T09:05:00Z', 11, 22, 3, 4, 0.33, 0),
            ('hermes-fallback', 'Hermes fallback', 'nous-hermes', '/tmp/hermes-fallback', '2026-01-10T10:00:00Z', '2026-01-10T10:05:00Z', 0, 0, 0, 0, NULL, 0);
        INSERT INTO messages VALUES
            ('hm1', 'hermes-1', 'user', 'please run', '2026-01-10T09:00:00Z', 5, NULL, NULL),
            ('hm2', 'hermes-1', 'assistant', 'done', '2026-01-10T09:01:00Z', 7, NULL, NULL),
            ('hm3', 'hermes-1', 'tool', 'shell', '2026-01-10T09:02:00Z', 0, 'shell', '{"arguments":{"command":"swift test"}}'),
            ('hf1', 'hermes-fallback', 'user', 'fallback user', '2026-01-10T10:00:00Z', 8, NULL, NULL),
            ('hf2', 'hermes-fallback', 'assistant', 'fallback assistant', '2026-01-10T10:01:00Z', 13, NULL, NULL);
        """)

        let provider = HermesProvider(paths: HermesPaths(homeDirectory: root), pricing: TestPricing.table)
        let sessions = await provider.discoverSessions()
        #expect(Set(sessions.map(\.externalID)) == ["hermes-1", "hermes-fallback"])

        let session = try #require(sessions.first { $0.externalID == "hermes-1" })
        let stats = try #require(await provider.parse(session))
        #expect(stats.title == "Hermes task")
        #expect(stats.models.first?.usage.inputTokens == 11)
        #expect(stats.models.first?.usage.outputTokens == 22)
        #expect(stats.models.first?.usage.cacheReadTokens == 3)
        #expect(stats.models.first?.usage.cacheCreation5mTokens == 4)
        #expect(stats.models.first?.estimatedCost == 0.33)
        let commands = await provider.executedCommands(for: session)
        #expect(commands.map(\.command) == ["swift test"])

        let fallbackSession = try #require(sessions.first { $0.externalID == "hermes-fallback" })
        let fallbackStats = try #require(await provider.parse(fallbackSession))
        #expect(fallbackStats.models.first?.usage.inputTokens == 8)
        #expect(fallbackStats.models.first?.usage.outputTokens == 13)
    }
}
