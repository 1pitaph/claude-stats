import Foundation

protocol TrackEventLogReading: Sendable {
    var eventLogURLs: [URL] { get }
    func loadEvents() async -> [TrackEvent]
}

struct TrackEventLogReader: TrackEventLogReading {
    let eventLogURLs: [URL]

    init(eventLogURLs: [URL] = TrackEventLogReader.defaultEventLogURLs()) {
        self.eventLogURLs = eventLogURLs
    }

    func loadEvents() async -> [TrackEvent] {
        let urls = eventLogURLs
        return await Task.detached(priority: .utility) {
            let decoder = JSONDecoder()
            var events: [TrackEvent] = []

            for url in urls {
                guard FileManager.default.fileExists(atPath: url.path),
                      let data = try? Data(contentsOf: url) else { continue }

                for (offset, lineBytes) in data.split(separator: 0x0A, omittingEmptySubsequences: true).enumerated() {
                    let lineData = Data(lineBytes)
                    guard let record = try? decoder.decode(TrackHookRecord.self, from: lineData),
                          let event = record.makeEvent(sourceURL: url, offset: offset) else { continue }
                    events.append(event)
                }
            }

            return events.sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                return lhs.id < rhs.id
            }
        }.value
    }

    static func defaultEventLogURLs(codexHome: URL = CodexPaths.default.homeDirectory) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        return [
            appSupport
                .appendingPathComponent("ClaudeStats", isDirectory: true)
                .appendingPathComponent("Track", isDirectory: true)
                .appendingPathComponent("events.jsonl", isDirectory: false),
            appSupport
                .appendingPathComponent("com.claudestats.ClaudeStats", isDirectory: true)
                .appendingPathComponent("Track", isDirectory: true)
                .appendingPathComponent("events.jsonl", isDirectory: false),
            codexHome
                .appendingPathComponent("track-events.jsonl", isDirectory: false),
        ]
    }
}

private struct TrackHookRecord: Decodable {
    let type: String?
    let receivedAt: String?
    let receivedAtSnake: String?
    let timestamp: TrackTimestamp?
    let sessionID: String?
    let sessionIDSnake: String?
    let threadID: String?
    let threadIDSnake: String?
    let parentSessionID: String?
    let parentSessionIDSnake: String?
    let parentThreadID: String?
    let parentThreadIDSnake: String?
    let turnID: String?
    let turnIDSnake: String?
    let agentID: String?
    let agentIDSnake: String?
    let agentType: String?
    let agentTypeSnake: String?
    let sourceKind: String?
    let sourceKindSnake: String?
    let hookEventName: String?
    let hookEventNameSnake: String?
    let eventName: String?
    let source: String?
    let toolUseID: String?
    let toolUseIDSnake: String?
    let toolName: String?
    let toolNameSnake: String?
    let approvalID: String?
    let approvalIDSnake: String?
    let permissionMode: String?
    let permissionModeSnake: String?
    let cwd: String?
    let transcriptPath: String?
    let transcriptPathSnake: String?
    let toolInput: TrackJSONValue?
    let toolInputSnake: TrackJSONValue?
    let status: String?
    let decision: String?
    let behavior: String?
    let message: String?
    let summary: String?
    let error: TrackJSONValue?
    let activeFlags: [String]?
    let activeFlagsSnake: [String]?
    let payload: TrackJSONValue?

    enum CodingKeys: String, CodingKey {
        case type
        case receivedAt
        case receivedAtSnake = "received_at"
        case timestamp
        case sessionID
        case sessionIDSnake = "session_id"
        case threadID
        case threadIDSnake = "thread_id"
        case parentSessionID
        case parentSessionIDSnake = "parent_session_id"
        case parentThreadID
        case parentThreadIDSnake = "parent_thread_id"
        case turnID
        case turnIDSnake = "turn_id"
        case agentID
        case agentIDSnake = "agent_id"
        case agentType
        case agentTypeSnake = "agent_type"
        case sourceKind
        case sourceKindSnake = "source_kind"
        case hookEventName
        case hookEventNameSnake = "hook_event_name"
        case eventName
        case source
        case toolUseID
        case toolUseIDSnake = "tool_use_id"
        case toolName
        case toolNameSnake = "tool_name"
        case approvalID
        case approvalIDSnake = "approval_id"
        case permissionMode
        case permissionModeSnake = "permission_mode"
        case cwd
        case transcriptPath
        case transcriptPathSnake = "transcript_path"
        case toolInput
        case toolInputSnake = "tool_input"
        case status
        case decision
        case behavior
        case message
        case summary
        case error
        case activeFlags
        case activeFlagsSnake = "active_flags"
        case payload
    }

    func makeEvent(sourceURL: URL, offset: Int) -> TrackEvent? {
        guard let sessionID = normalizedSessionID(firstNonEmpty(
            sessionID,
            sessionIDSnake,
            threadID,
            threadIDSnake,
            payload?.stringValue(for: "session_id", "sessionID", "thread_id", "threadID")
        )) else { return nil }
        let hookName = firstNonEmpty(
            hookEventName,
            hookEventNameSnake,
            eventName,
            type,
            payload?.stringValue(for: "hook_event_name", "hookEventName", "eventName", "type")
        ) ?? "StatusChanged"
        let timestamp = parsedTimestamp ?? .now
        let toolUseID = firstNonEmpty(toolUseID, toolUseIDSnake, payload?.stringValue(for: "tool_use_id", "toolUseID", "toolUseId"))
        let approvalID = firstNonEmpty(approvalID, approvalIDSnake, payload?.stringValue(for: "approval_id", "approvalID", "request_id", "requestID"))
        let toolName = firstNonEmpty(toolName, toolNameSnake, payload?.stringValue(for: "tool_name", "toolName", "name"))
        let agentType = firstNonEmpty(
            agentType,
            agentTypeSnake,
            sourceKind,
            sourceKindSnake,
            payload?.stringValue(for: "agent_type", "agentType", "source_kind", "sourceKind")
        )
        let detail = makeDetail()
        let kind = makeKind(hookName: hookName)
        let stableParts = [
            sourceURL.path,
            sessionID,
            firstNonEmpty(turnID, turnIDSnake),
            firstNonEmpty(agentID, agentIDSnake),
            toolUseID,
            approvalID,
            hookName,
            "\(offset)",
        ].compactMap { $0 }
        let id = stableParts.joined(separator: "::")

        return TrackEvent(
            id: id,
            timestamp: timestamp,
            source: makeSource(),
            kind: kind,
            provider: .codex,
            sessionID: sessionID,
            parentSessionID: normalizedSessionID(firstNonEmpty(
                parentSessionID,
                parentSessionIDSnake,
                parentThreadID,
                parentThreadIDSnake,
                payload?.stringValue(for: "parent_session_id", "parentSessionID", "parentSessionId", "parent_thread_id", "parentThreadID", "parentThreadId")
            )),
            turnID: firstNonEmpty(turnID, turnIDSnake, payload?.stringValue(for: "turn_id", "turnID")),
            agentID: firstNonEmpty(agentID, agentIDSnake, payload?.stringValue(for: "agent_id", "agentID")),
            agentType: agentType,
            toolUseID: toolUseID,
            approvalID: approvalID,
            toolName: toolName,
            permissionMode: firstNonEmpty(permissionMode, permissionModeSnake, payload?.stringValue(for: "permission_mode", "permissionMode")),
            cwd: firstNonEmpty(cwd, payload?.stringValue(for: "cwd")),
            transcriptPath: firstNonEmpty(transcriptPath, transcriptPathSnake, payload?.stringValue(for: "transcript_path", "transcriptPath")),
            summary: makeSummary(hookName: hookName, kind: kind, toolName: toolName, agentType: agentType),
            detail: detail,
            confidence: makeSource().confidence
        )
    }

    private var parsedTimestamp: Date? {
        if let receivedAt = firstNonEmpty(receivedAt, receivedAtSnake),
           let parsed = TrackISO8601.parse(receivedAt) {
            return parsed
        }
        return timestamp?.dateValue
    }

    private func makeKind(hookName: String) -> TrackEventKind {
        switch hookName {
        case "SessionStart", "session.started", "session_start":
            return .sessionStarted
        case "Stop", "SessionStop", "session.stopped", "session_stop":
            return .sessionStopped
        case "UserPromptSubmit", "turn.started", "prompt_submit":
            return .turnStarted
        case "SubagentStart", "SubagentStarted", "subagent.started", "subagent.start", "subagent_start", "subagent_started", "task.started", "task.start":
            return .subagentStarted
        case "SubagentStop", "SubagentStopped", "subagent.stopped", "subagent.stop", "subagent_stop", "subagent_stopped", "task.stopped", "task.stop":
            return .subagentStopped
        case "PreToolUse", "tool.requested", "tool.started":
            return .toolRequested
        case "PostToolUse", "tool.succeeded", "tool.failed":
            if isFailure { return .toolFailed }
            return .toolSucceeded
        case "PermissionRequest", "approval.requested", "permission.asked", "serverRequest/requested", "server_request.requested":
            return .approvalRequested
        case "permission.replied", "approval.allowed", "approval.denied", "serverRequest/resolved", "server_request.resolved":
            if normalizedDecision == "deny" || normalizedDecision == "denied" {
                return .approvalDenied
            }
            return .approvalAllowed
        case "QuestionAsked", "question.asked":
            return .questionAsked
        case "QuestionReplied", "question.replied":
            return .questionReplied
        case "thread/status/changed", "thread.status.changed":
            if indicatesWaitingApproval { return .approvalRequested }
            return .statusChanged
        default:
            if isFailure { return .error }
            return .statusChanged
        }
    }

    private var isFailure: Bool {
        let values = [status, decision, behavior, error?.compactDescription].compactMap { $0?.lowercased() }
        return values.contains { value in
            value.contains("fail")
                || value.contains("error")
                || value.contains("deny")
                || value.contains("rejected")
        }
    }

    private var normalizedDecision: String? {
        firstNonEmpty(decision, behavior, status)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var indicatesWaitingApproval: Bool {
        let values = (activeFlags ?? []) + (activeFlagsSnake ?? []) + [
            status,
            decision,
            behavior,
            payload?.stringValue(for: "status", "phase"),
        ].compactMap { $0 }
        return values.contains { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("waitingonapproval")
                || normalized.contains("waiting_on_approval")
                || normalized.contains("waiting approval")
                || normalized.contains("approval")
        }
    }

    private func makeSource() -> TrackEventSource {
        let rawSource = source ?? payload?.stringValue(for: "source")
        switch rawSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "appserver", "app-server", "app_server":
            return .appServer
        case "transcript":
            return .transcript
        case "process":
            return .process
        case "notification":
            return .notification
        default:
            return .hook
        }
    }

    private func makeSummary(hookName: String, kind: TrackEventKind, toolName: String?, agentType: String?) -> String {
        if let summary = firstNonEmpty(summary, message) { return summary }
        switch kind {
        case .subagentStarted:
            return "Started \(agentType ?? "subagent")"
        case .subagentStopped:
            return "Stopped \(agentType ?? "subagent")"
        case .toolRequested, .toolStarted:
            return "Requested \(toolName ?? "tool")"
        case .toolSucceeded:
            return "\(toolName ?? "Tool") succeeded"
        case .toolFailed:
            return "\(toolName ?? "Tool") failed"
        case .approvalRequested:
            return "Approval requested for \(toolName ?? "tool")"
        default:
            return TrackEventKindTitle.title(for: hookName, fallback: kind.title)
        }
    }

    private func makeDetail() -> String? {
        if let input = toolInputSnake ?? toolInput ?? payload?.objectValue(for: "tool_input", "toolInput", "input", "arguments") {
            return input.compactDescription
        }
        if let error {
            return error.compactDescription
        }
        return message
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.first { !$0.isEmpty }
    }

    private func normalizedSessionID(_ value: String?) -> String? {
        guard let value = firstNonEmpty(value) else { return nil }
        if value.hasPrefix("codex:") {
            return String(value.dropFirst("codex:".count))
        }
        return value
    }
}

private enum TrackEventKindTitle {
    static func title(for raw: String, fallback: String) -> String {
        guard !raw.isEmpty else { return fallback }
        return raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
    }
}

private enum TrackTimestamp: Decodable {
    case string(String)
    case seconds(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self = .seconds(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    var dateValue: Date? {
        switch self {
        case .string(let value):
            TrackISO8601.parse(value)
        case .seconds(let value):
            if value > 10_000_000_000 {
                Date(timeIntervalSince1970: value / 1_000)
            } else {
                Date(timeIntervalSince1970: value)
            }
        }
    }
}

private enum TrackISO8601 {
    static func parse(_ value: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(value)
    }
}
