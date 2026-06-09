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

    static func defaultEventLogURLs() -> [URL] {
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
            home
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("track-events.jsonl", isDirectory: false),
        ]
    }
}

private struct TrackHookRecord: Decodable {
    let receivedAt: String?
    let receivedAtSnake: String?
    let timestamp: TrackTimestamp?
    let sessionID: String?
    let sessionIDSnake: String?
    let parentSessionID: String?
    let parentSessionIDSnake: String?
    let turnID: String?
    let turnIDSnake: String?
    let agentID: String?
    let agentIDSnake: String?
    let agentType: String?
    let agentTypeSnake: String?
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

    enum CodingKeys: String, CodingKey {
        case receivedAt
        case receivedAtSnake = "received_at"
        case timestamp
        case sessionID
        case sessionIDSnake = "session_id"
        case parentSessionID
        case parentSessionIDSnake = "parent_session_id"
        case turnID
        case turnIDSnake = "turn_id"
        case agentID
        case agentIDSnake = "agent_id"
        case agentType
        case agentTypeSnake = "agent_type"
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
    }

    func makeEvent(sourceURL: URL, offset: Int) -> TrackEvent? {
        guard let sessionID = firstNonEmpty(sessionID, sessionIDSnake) else { return nil }
        let hookName = firstNonEmpty(hookEventName, hookEventNameSnake, eventName) ?? "StatusChanged"
        let timestamp = parsedTimestamp ?? .now
        let toolUseID = firstNonEmpty(toolUseID, toolUseIDSnake)
        let approvalID = firstNonEmpty(approvalID, approvalIDSnake)
        let toolName = firstNonEmpty(toolName, toolNameSnake)
        let agentType = firstNonEmpty(agentType, agentTypeSnake)
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
            parentSessionID: firstNonEmpty(parentSessionID, parentSessionIDSnake),
            turnID: firstNonEmpty(turnID, turnIDSnake),
            agentID: firstNonEmpty(agentID, agentIDSnake),
            agentType: agentType,
            toolUseID: toolUseID,
            approvalID: approvalID,
            toolName: toolName,
            permissionMode: firstNonEmpty(permissionMode, permissionModeSnake),
            cwd: cwd,
            transcriptPath: firstNonEmpty(transcriptPath, transcriptPathSnake),
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
        case "SubagentStart", "subagent.started", "subagent_start":
            return .subagentStarted
        case "SubagentStop", "subagent.stopped", "subagent_stop":
            return .subagentStopped
        case "PreToolUse", "tool.requested", "tool.started":
            return .toolRequested
        case "PostToolUse", "tool.succeeded", "tool.failed":
            if isFailure { return .toolFailed }
            return .toolSucceeded
        case "PermissionRequest", "approval.requested", "permission.asked":
            return .approvalRequested
        case "permission.replied", "approval.allowed", "approval.denied":
            if normalizedDecision == "deny" || normalizedDecision == "denied" {
                return .approvalDenied
            }
            return .approvalAllowed
        case "QuestionAsked", "question.asked":
            return .questionAsked
        case "QuestionReplied", "question.replied":
            return .questionReplied
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

    private func makeSource() -> TrackEventSource {
        switch source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "appserver", "app-server", "app_server":
            .appServer
        case "transcript":
            .transcript
        case "process":
            .process
        case "notification":
            .notification
        default:
            .hook
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
        if let input = toolInputSnake ?? toolInput {
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
