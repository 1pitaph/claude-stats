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

    @Test("Reader accepts app-server status and alternate subagent event names")
    func readerAcceptsAppServerAndAlternateSubagentNames() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("track-events.jsonl")
        let lines = [
            #"{"timestamp":"2026-06-09T09:00:00Z","source":"app-server","thread_id":"codex-session-1","type":"thread/status/changed","activeFlags":["waitingOnApproval"],"tool_use_id":"tool-1","tool_name":"exec_command"}"#,
            #"{"timestamp":"2026-06-09T09:00:01Z","session_id":"codex-session-1","eventName":"SubagentStarted","sourceKind":"explorer","agent_id":"agent-1"}"#,
        ]
        try TempDir.write(lines.joined(separator: "\n") + "\n", to: url)

        let events = await TrackEventLogReader(eventLogURLs: [url]).loadEvents()

        #expect(events.count == 2)
        #expect(events[0].source == .appServer)
        #expect(events[0].kind == .approvalRequested)
        #expect(events[0].sessionID == "codex-session-1")
        #expect(events[1].kind == .subagentStarted)
        #expect(events[1].agentType == "explorer")
    }

    @Test("Tool events with agent ids synthesize subagent nodes")
    func toolEventsWithAgentIDsSynthesizeSubagents() async throws {
        let events = [
            Self.event(kind: .turnStarted, id: "turn", turnID: "turn-1"),
            Self.event(kind: .toolRequested, id: "tool", agentID: "worker-1", agentType: "worker", toolUseID: "tool-1", toolName: "exec_command"),
        ]

        let snapshot = TrackSnapshotBuilder().build(
            sessions: [Self.session()],
            commandEventsBySessionID: [:],
            hookEvents: events,
            now: Self.date("2026-06-09T09:05:00Z")
        )

        let run = try #require(snapshot.runs.first)
        let subagent = try #require(run.nodes.first { $0.kind == .subagent })
        #expect(subagent.title == "worker")
        #expect(run.edges.contains { $0.from.contains("agent::worker-1") && $0.to.contains("tool::tool-1") })
    }

    @Test("Post tool use resolves waiting approval when no explicit permission reply exists")
    func postToolUseResolvesApproval() async throws {
        let events = [
            Self.event(kind: .turnStarted, id: "turn", turnID: "turn-1"),
            Self.event(kind: .approvalRequested, id: "approval", toolUseID: "tool-1", approvalID: "approval-1", toolName: "exec_command"),
            Self.event(kind: .toolSucceeded, id: "tool-done", toolUseID: "tool-1", toolName: "exec_command"),
        ]

        let snapshot = TrackSnapshotBuilder().build(
            sessions: [Self.session()],
            commandEventsBySessionID: [:],
            hookEvents: events,
            now: Self.date("2026-06-09T09:05:00Z")
        )

        let approval = try #require(snapshot.approvals.first)
        #expect(approval.status == .approved)
        #expect(approval.resolvedAt != nil)
    }

    @Test("Parent session id groups child transcript events into parent run")
    func parentSessionIDGroupsChildEvents() async throws {
        let parent = Self.session()
        let child = Session(
            id: "encoded-project::child-session",
            externalID: "child-session",
            provider: .codex,
            projectDirectoryName: "-Users-dev-projects-claude-stats",
            filePath: "/tmp/child-session.jsonl",
            cwd: "/Users/dev/projects/claude-stats",
            lastModified: Self.date("2026-06-09T09:00:08Z"),
            fileSize: 1_024,
            stats: SessionStats(
                title: "Research",
                messageCount: 1,
                firstActivity: Self.date("2026-06-09T09:00:02Z"),
                lastActivity: Self.date("2026-06-09T09:00:05Z"),
                models: [],
                timeline: []
            )
        )
        let events = [
            Self.event(kind: .subagentStarted, id: "child-start", sessionID: "child-session", parentSessionID: "codex-session-1", agentID: "child-session", agentType: "explorer"),
            Self.event(kind: .subagentStopped, id: "child-stop", sessionID: "child-session", parentSessionID: "codex-session-1", agentID: "child-session", agentType: "explorer"),
        ]

        let snapshot = TrackSnapshotBuilder().build(
            sessions: [parent, child],
            commandEventsBySessionID: [:],
            hookEvents: events,
            now: Self.date("2026-06-09T09:05:00Z")
        )

        #expect(snapshot.runs.count == 1)
        let parentRun = try #require(snapshot.runs.first { $0.id == parent.id })
        #expect(parentRun.nodes.contains { $0.kind == .subagent && $0.title == "explorer" })
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

    private static func event(
        kind: TrackEventKind,
        id: String,
        sessionID: String = "codex-session-1",
        parentSessionID: String? = nil,
        turnID: String? = nil,
        agentID: String? = nil,
        agentType: String? = nil,
        toolUseID: String? = nil,
        approvalID: String? = nil,
        toolName: String? = nil
    ) -> TrackEvent {
        TrackEvent(
            id: id,
            timestamp: Self.date("2026-06-09T09:00:00Z"),
            source: .hook,
            kind: kind,
            provider: .codex,
            sessionID: sessionID,
            parentSessionID: parentSessionID,
            turnID: turnID,
            agentID: agentID,
            agentType: agentType,
            toolUseID: toolUseID,
            approvalID: approvalID,
            toolName: toolName,
            permissionMode: nil,
            cwd: "/Users/dev/projects/claude-stats",
            transcriptPath: nil,
            summary: kind.title,
            detail: nil,
            confidence: .high
        )
    }

    private static func date(_ value: String) -> Date {
        (try? Date.ISO8601FormatStyle().parse(value)) ?? Date(timeIntervalSince1970: 0)
    }
}
