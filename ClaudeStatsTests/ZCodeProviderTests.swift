import Foundation
import Testing
@testable import ClaudeStats

@Suite("ZCodeProvider")
struct ZCodeProviderTests {

    @Test("Provider kind is `.zcode` and uses ~/.zcode by default")
    func providerKindIsZCode() {
        let provider = ZCodeProvider(paths: .default, pricing: .fallback)
        #expect(provider.kind == .zcode)
        #expect(provider.dataDirectoryPath?.hasSuffix(".zcode") == true)
    }

    @Test("Empty database returns no sessions")
    func emptyDatabase() async throws {
        let temp = try TempZCodeHome.create()
        defer { temp.cleanup() }
        // No database file at all.
        let provider = ZCodeProvider(paths: temp.paths, pricing: .fallback)
        #expect(provider.dataDirectoryExists == true)
        let sessions = await provider.discoverSessions()
        #expect(sessions.isEmpty)
    }

    @Test("SQLite session + model_usage round-trip into SessionStats")
    func parsesSQLiteSessionStats() async throws {
        let temp = try TempZCodeHome.create()
        defer { temp.cleanup() }
        try temp.seedDatabase(sessions: [
            .init(id: "sess_abc",
                  directory: "/Users/me/projects/demo",
                  title: "Add ZCode adapter",
                  timeCreated: 1_750_000_000_000,
                  timeUpdated: 1_750_000_300_000,
                  modelUsage: [
                    .init(model: "glm-5.2",
                          input: 1_200,
                          output: 800,
                          reasoning: 50,
                          cacheRead: 4_000,
                          cacheWrite: 200,
                          startedAt: 1_750_000_010_000,
                          completedAt: 1_750_000_018_000),
                    .init(model: "glm-5.2",
                          input: 300,
                          output: 400,
                          reasoning: 25,
                          cacheRead: 0,
                          cacheWrite: 0,
                          startedAt: 1_750_000_200_000,
                          completedAt: 1_750_000_206_000),
                  ],
                  messages: [
                    .init(id: "m1", role: "user", text: "Adapt claude-stats to ZCode.", timeCreated: 1_750_000_005_000),
                    .init(id: "m2", role: "assistant", text: "Sure — here's the plan.", timeCreated: 1_750_000_020_000),
                  ])
        ])

        let provider = ZCodeProvider(paths: temp.paths, pricing: .fallback)
        let sessions = await provider.discoverSessions()
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.externalID == "sess_abc")
        #expect(session.cwd == "/Users/me/projects/demo")
        #expect(session.projectDirectoryName == "demo")

        let stats = try #require(await provider.parse(session))
        #expect(stats.models.count == 1)
        let model = try #require(stats.models.first)
        #expect(model.model == "glm-5.2")
        // 1200+300 input
        #expect(model.usage.inputTokens == 1_500)
        // 800+50+400+25 (reasoning folded into output)
        #expect(model.usage.outputTokens == 1_275)
        #expect(model.usage.cacheReadTokens == 4_000)
        #expect(model.usage.cacheCreation5mTokens == 200)
        #expect(stats.timeline.isEmpty == false)
        #expect(stats.title.contains("Add ZCode adapter") || stats.title.contains("ZCode"))
        #expect(stats.messageCount == 2)
    }

    @Test("Display name normalisation")
    func displayName() {
        let provider = ZCodeProvider(paths: .default, pricing: .fallback)
        #expect(provider.displayName(forModel: "glm-5.2") == "GLM 5.2")
        #expect(provider.displayName(forModel: "GLM-5.2") == "GLM 5.2")
        #expect(provider.displayName(forModel: "doubao-pro") == "Doubao pro")
        #expect(provider.displayName(forModel: "deepseek-v4-pro") == "DeepSeek v4-pro")
        #expect(provider.displayName(forModel: "unknown-model-x") == "unknown-model-x")
    }
}

// MARK: - Test helpers

private struct TempZCodeHome {
    let homeDirectory: URL

    var paths: ZCodePaths { ZCodePaths(homeDirectory: homeDirectory) }

    static func create() throws -> TempZCodeHome {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zcode-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return TempZCodeHome(homeDirectory: directory)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: homeDirectory)
    }

    struct SeedSession {
        struct ModelUsageRow {
            let model: String
            let input: Int
            let output: Int
            let reasoning: Int
            let cacheRead: Int
            let cacheWrite: Int
            let startedAt: Int64
            let completedAt: Int64
        }
        struct MessageRow {
            let id: String
            let role: String
            let text: String
            let timeCreated: Int64
        }
        let id: String
        let directory: String
        let title: String
        let timeCreated: Int64
        let timeUpdated: Int64
        let modelUsage: [ModelUsageRow]
        let messages: [MessageRow]
    }

    func seedDatabase(sessions: [SeedSession]) throws {
        try FileManager.default.createDirectory(
            at: paths.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let connection = try SQLiteConnection(url: paths.databaseURL, readOnly: false)
        try connection.execute("""
            CREATE TABLE session (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL DEFAULT '',
                slug TEXT NOT NULL DEFAULT '',
                directory TEXT NOT NULL DEFAULT '',
                title TEXT NOT NULL DEFAULT '',
                version TEXT NOT NULL DEFAULT '',
                time_created INTEGER NOT NULL DEFAULT 0,
                time_updated INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE model_usage (
                id TEXT PRIMARY KEY,
                logical_request_id TEXT NOT NULL DEFAULT '',
                attempt_index INTEGER NOT NULL DEFAULT 0,
                session_id TEXT NOT NULL,
                query_source TEXT NOT NULL DEFAULT '',
                provider_id TEXT NOT NULL DEFAULT '',
                model_id TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'completed',
                started_at INTEGER NOT NULL,
                completed_at INTEGER,
                input_tokens INTEGER NOT NULL DEFAULT 0,
                output_tokens INTEGER NOT NULL DEFAULT 0,
                reasoning_tokens INTEGER NOT NULL DEFAULT 0,
                cache_creation_input_tokens INTEGER NOT NULL DEFAULT 0,
                cache_read_input_tokens INTEGER NOT NULL DEFAULT 0,
                computed_total_tokens INTEGER NOT NULL DEFAULT 0,
                retry_count INTEGER NOT NULL DEFAULT 0,
                retryable INTEGER NOT NULL DEFAULT 0,
                cancelled_by_user INTEGER NOT NULL DEFAULT 0,
                context_exceeded INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE message (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                time_created INTEGER NOT NULL,
                time_updated INTEGER NOT NULL DEFAULT 0,
                data TEXT NOT NULL
            );
            CREATE TABLE part (
                id TEXT PRIMARY KEY,
                message_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                time_created INTEGER NOT NULL,
                time_updated INTEGER NOT NULL DEFAULT 0,
                data TEXT NOT NULL
            );
            CREATE TABLE tool_usage (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                tool_call_id TEXT NOT NULL,
                tool_name TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'completed',
                started_at INTEGER NOT NULL
            );
        """)

        for session in sessions {
            let s = try connection.prepare("""
                INSERT INTO session (id, directory, title, time_created, time_updated)
                VALUES (?, ?, ?, ?, ?)
            """)
            try s.bind(session.id, at: 1)
            try s.bind(session.directory, at: 2)
            try s.bind(session.title, at: 3)
            try s.bind(session.timeCreated, at: 4)
            try s.bind(session.timeUpdated, at: 5)
            _ = try s.step()

            for (index, usage) in session.modelUsage.enumerated() {
                let u = try connection.prepare("""
                    INSERT INTO model_usage (id, session_id, model_id, status, started_at, completed_at,
                                             input_tokens, output_tokens, reasoning_tokens,
                                             cache_creation_input_tokens, cache_read_input_tokens)
                    VALUES (?, ?, ?, 'completed', ?, ?, ?, ?, ?, ?, ?)
                """)
                try u.bind("\(session.id)-usage-\(index)", at: 1)
                try u.bind(session.id, at: 2)
                try u.bind(usage.model, at: 3)
                try u.bind(usage.startedAt, at: 4)
                try u.bind(usage.completedAt, at: 5)
                try u.bind(Int64(usage.input), at: 6)
                try u.bind(Int64(usage.output), at: 7)
                try u.bind(Int64(usage.reasoning), at: 8)
                try u.bind(Int64(usage.cacheWrite), at: 9)
                try u.bind(Int64(usage.cacheRead), at: 10)
                _ = try u.step()
            }

            for message in session.messages {
                let messageData: [String: Any] = ["role": message.role, "time": ["created": message.timeCreated]]
                let messageJSON = try JSONSerialization.data(withJSONObject: messageData)
                let m = try connection.prepare("""
                    INSERT INTO message (id, session_id, time_created, data)
                    VALUES (?, ?, ?, ?)
                """)
                try m.bind(message.id, at: 1)
                try m.bind(session.id, at: 2)
                try m.bind(message.timeCreated, at: 3)
                try m.bind(String(data: messageJSON, encoding: .utf8) ?? "{}", at: 4)
                _ = try m.step()

                let partData: [String: Any] = ["type": "text", "text": message.text]
                let partJSON = try JSONSerialization.data(withJSONObject: partData)
                let p = try connection.prepare("""
                    INSERT INTO part (id, message_id, session_id, time_created, data)
                    VALUES (?, ?, ?, ?, ?)
                """)
                try p.bind("\(message.id)-part", at: 1)
                try p.bind(message.id, at: 2)
                try p.bind(session.id, at: 3)
                try p.bind(message.timeCreated, at: 4)
                try p.bind(String(data: partJSON, encoding: .utf8) ?? "{}", at: 5)
                _ = try p.step()
            }
        }
    }
}
