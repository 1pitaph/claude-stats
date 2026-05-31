import Foundation
import Testing
@testable import ClaudeStats

@Suite("Session command summaries")
struct SessionCommandSummaryTests {
    @Test("Ranks exact commands by count then latest use")
    func ranksExactCommands() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)

        let commands = SessionCommandSummaryBuilder.topCommands(
            from: [
                SessionCommandEvent(command: "git status", timestamp: older),
                SessionCommandEvent(command: "git status", timestamp: newer),
                SessionCommandEvent(command: "git diff --stat", timestamp: newer),
                SessionCommandEvent(command: "npm test", timestamp: newer.addingTimeInterval(10)),
                SessionCommandEvent(command: "npm test", timestamp: older),
                SessionCommandEvent(command: "swift test", timestamp: nil),
            ],
            limit: 3
        )

        #expect(commands.map(\.command) == ["npm test", "git status", "git diff --stat"])
        #expect(commands.map(\.count) == [2, 2, 1])
    }

    @Test("Selects latest active sessions across providers")
    func selectsLatestSessionsAcrossProviders() {
        let sessions = [
            Self.session(id: "old", provider: .claude, lastActivity: Date(timeIntervalSince1970: 10)),
            Self.session(id: "newer", provider: .codex, lastActivity: Date(timeIntervalSince1970: 30)),
            Self.session(id: "middle", provider: .claude, lastActivity: Date(timeIntervalSince1970: 20)),
        ]

        let recent = SessionCommandSummaryBuilder.recentSessions(sessions, limit: 2)

        #expect(recent.map(\.id) == ["newer", "middle"])
    }

    @Test("Keeps recent sessions with empty command state")
    func keepsEmptyCommandSessions() {
        let session = Self.session(id: "empty", provider: .codex, lastActivity: Date(timeIntervalSince1970: 50))

        let summary = SessionCommandSummaryBuilder.summary(for: session, events: [], commandLimit: 3)

        #expect(summary.sessionID == "empty")
        #expect(summary.commands.isEmpty)
    }

    private static func session(id: String, provider: ProviderKind, lastActivity: Date) -> Session {
        Session(
            id: id,
            externalID: id,
            provider: provider,
            projectDirectoryName: "project-\(id)",
            filePath: "/tmp/\(id).jsonl",
            cwd: "/tmp/project-\(id)",
            lastModified: lastActivity.addingTimeInterval(-1),
            fileSize: 100,
            stats: SessionStats(
                title: "Session \(id)",
                messageCount: 1,
                firstActivity: lastActivity.addingTimeInterval(-5),
                lastActivity: lastActivity,
                models: [],
                timeline: []
            )
        )
    }
}
