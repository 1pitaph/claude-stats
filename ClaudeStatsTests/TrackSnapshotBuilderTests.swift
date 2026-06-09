import Foundation
import Testing
@testable import ClaudeStats

@Suite("Track snapshot builder")
struct TrackSnapshotBuilderTests {
    @Test("Hook events build a waiting approval graph")
    func hookEventsBuildWaitingApprovalGraph() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("track-events.jsonl")
        try TempDir.write(Self.pendingApprovalLines.joined(separator: "\n") + "\n", to: url)

        let hookEvents = await TrackEventLogReader(eventLogURLs: [url]).loadEvents()
        let session = Self.session()
        let snapshot = TrackSnapshotBuilder().build(
            sessions: [session],
            commandEventsBySessionID: [
                session.id: [SessionCommandEvent(command: "git status --short", timestamp: Self.date("2026-06-09T09:00:05Z"))],
            ],
            hookEvents: hookEvents,
            now: Self.date("2026-06-09T09:03:00Z"),
            eventLogURLs: [url]
        )

        #expect(hookEvents.count == 5)
        #expect(snapshot.runs.count == 1)
        let run = try #require(snapshot.runs.first)
        #expect(run.id == session.id)
        #expect(run.status == .waitingApproval)
        #expect(run.confidence == .high)
        #expect(run.nodes.contains { $0.kind == .subagent && $0.status == .running })
        #expect(run.nodes.contains { $0.kind == .tool && $0.status == .usingTool })
        #expect(run.nodes.contains { $0.kind == .approval && $0.status == .waitingApproval })
        #expect(run.approvals.first?.status == .waitingApproval)
        #expect(snapshot.pendingApprovalCount == 1)
        #expect(snapshot.eventLogURLs == [url])
        #expect(run.edges.contains { $0.from.contains("agent::researcher-1") && $0.to.contains("tool::tool-1") })
    }

    @Test("Resolved hook events clear approval and complete the run")
    func resolvedHookEventsCompleteRun() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("track-events.jsonl")
        try TempDir.write((Self.pendingApprovalLines + Self.resolutionLines).joined(separator: "\n") + "\n", to: url)

        let hookEvents = await TrackEventLogReader(eventLogURLs: [url]).loadEvents()
        let snapshot = TrackSnapshotBuilder().build(
            sessions: [Self.session()],
            commandEventsBySessionID: [:],
            hookEvents: hookEvents,
            now: Self.date("2026-06-09T09:05:00Z"),
            eventLogURLs: [url]
        )

        let run = try #require(snapshot.runs.first)
        #expect(run.status == .completed)
        #expect(run.approvals.first?.status == .approved)
        #expect(run.approvals.first?.resolvedAt != nil)
        #expect(run.tools.first?.status == .completed)
        #expect(run.tools.first?.endedAt != nil)
        #expect(snapshot.pendingApprovalCount == 0)
        #expect(run.nodes.contains { $0.kind == .subagent && $0.status == .completed })
        #expect(run.nodes.contains { $0.kind == .approval && $0.status == .approved })
    }

    private static let pendingApprovalLines = [
        #"{"received_at":"2026-06-09T09:00:00Z","session_id":"codex-session-1","hook_event_name":"SessionStart","cwd":"/Users/dev/projects/claude-stats"}"#,
        #"{"received_at":"2026-06-09T09:00:01Z","session_id":"codex-session-1","turn_id":"turn-1","hook_event_name":"UserPromptSubmit","permission_mode":"default","summary":"Implement Track module"}"#,
        #"{"received_at":"2026-06-09T09:00:02Z","session_id":"codex-session-1","turn_id":"turn-1","agent_id":"researcher-1","agent_type":"github-researcher","hook_event_name":"SubagentStart"}"#,
        #"{"received_at":"2026-06-09T09:00:03Z","session_id":"codex-session-1","turn_id":"turn-1","agent_id":"researcher-1","tool_use_id":"tool-1","tool_name":"gh","hook_event_name":"PreToolUse","tool_input":{"cmd":"gh repo view openai/codex"}}"#,
        #"{"received_at":"2026-06-09T09:00:04Z","session_id":"codex-session-1","turn_id":"turn-1","agent_id":"researcher-1","tool_use_id":"tool-1","approval_id":"approval-1","tool_name":"gh","hook_event_name":"PermissionRequest","tool_input":{"cmd":"gh repo view openai/codex"}}"#,
    ]

    private static let resolutionLines = [
        #"{"received_at":"2026-06-09T09:00:05Z","session_id":"codex-session-1","turn_id":"turn-1","agent_id":"researcher-1","tool_use_id":"tool-1","approval_id":"approval-1","tool_name":"gh","eventName":"permission.replied","decision":"allow"}"#,
        #"{"received_at":"2026-06-09T09:00:06Z","session_id":"codex-session-1","turn_id":"turn-1","agent_id":"researcher-1","tool_use_id":"tool-1","tool_name":"gh","hook_event_name":"PostToolUse","status":"success"}"#,
        #"{"received_at":"2026-06-09T09:00:07Z","session_id":"codex-session-1","turn_id":"turn-1","agent_id":"researcher-1","agent_type":"github-researcher","hook_event_name":"SubagentStop"}"#,
        #"{"received_at":"2026-06-09T09:00:08Z","session_id":"codex-session-1","hook_event_name":"Stop"}"#,
    ]

    private static func session() -> Session {
        Session(
            id: "encoded-project::codex-session-1",
            externalID: "codex-session-1",
            provider: .codex,
            projectDirectoryName: "-Users-dev-projects-claude-stats",
            filePath: "/tmp/codex-session-1.jsonl",
            cwd: "/Users/dev/projects/claude-stats",
            lastModified: Self.date("2026-06-09T09:00:08Z"),
            fileSize: 1_024,
            stats: SessionStats(
                title: "Implement Track module",
                messageCount: 2,
                firstActivity: Self.date("2026-06-09T09:00:00Z"),
                lastActivity: Self.date("2026-06-09T09:00:08Z"),
                models: [],
                timeline: []
            )
        )
    }

    private static func date(_ value: String) -> Date {
        (try? Date.ISO8601FormatStyle().parse(value)) ?? Date(timeIntervalSince1970: 0)
    }
}
