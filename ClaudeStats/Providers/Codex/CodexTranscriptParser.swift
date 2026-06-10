import Foundation

/// Parses an OpenAI Codex CLI `rollout-*.jsonl` transcript into ``SessionStats``.
///
/// Codex records a `token_count` event after each turn carrying both the
/// cumulative usage (`total_token_usage`) and that turn's delta
/// (`last_token_usage`). We attribute each delta to the model in effect at the
/// time (the most recent `turn_context.model`), which also gives an hourly
/// per-model timeline. Cache-hit prompt tokens are reported as
/// `cached_input_tokens`, a subset of `input_tokens`.
struct CodexTranscriptParser: Sendable {
    let pricing: ModelPricing

    /// Codex sessions don't name the model in `session_meta`; default to GPT-5
    /// when no `turn_context` has been seen yet.
    private static let defaultModel = "gpt-5"

    func parse(transcriptAt url: URL, fallbackTitle: String) async -> SessionStats? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        var currentModel = Self.defaultModel
        var perModel: [String: (count: Int, usage: TokenUsage, cost: CostEstimate)] = [:]
        var perModelHourly: [String: [Date: TokenUsage]] = [:]
        var messageCount = 0
        var firstActivity: Date?
        var lastActivity: Date?
        var threadName: String?
        var firstUserTitle: String?
        var messageTimestamps: [Date] = []
        var currentServiceTier: ModelPricing.ServiceTier?
        let calendar = Calendar.current

        let decoder = JSONDecoder()
        for lineBytes in data.split(separator: 0x0A /* \n */, omittingEmptySubsequences: true) {
            guard let line = try? decoder.decode(CodexLine.self, from: Data(lineBytes)) else { continue }
            let date = ISO8601.parse(line.timestamp)
            track(date, &firstActivity, &lastActivity)
            guard let payload = line.payload else { continue }

            switch (line.type, payload.type) {
            case ("turn_context", _):
                if let m = payload.model, !m.isEmpty { currentModel = m }
                else if let m = payload.collaborationMode?.settings?.model, !m.isEmpty { currentModel = m }
                if let tier = payload.billingTier ?? payload.collaborationMode?.settings?.billingTier ?? line.billingTier {
                    currentServiceTier = tier
                }

            case ("event_msg", "thread_name_updated"):
                if let t = payload.threadName?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    threadName = t
                }

            case ("event_msg", "agent_message"):
                messageCount += 1
                if let date { messageTimestamps.append(date) }

            case ("event_msg", "user_message"):
                messageCount += 1
                if let date { messageTimestamps.append(date) }
                if firstUserTitle == nil, let raw = payload.message, let cleaned = TitleSanitizer.sanitize(raw) {
                    firstUserTitle = cleaned
                }

            case ("event_msg", "token_count"):
                guard let delta = payload.info?.lastTokenUsage else { break }
                let usage = delta.tokenUsage
                guard usage.total > 0 else { break }
                var acc = perModel[currentModel] ?? (0, .zero, .zero)
                acc.count += 1
                acc.usage += usage
                let tier = payload.billingTier
                    ?? payload.info?.billingTier
                    ?? delta.billingTier
                    ?? line.billingTier
                    ?? currentServiceTier
                let cost = pricing.codexCostEstimate(
                    model: currentModel,
                    usage: usage,
                    contextInputTokens: delta.rawInputTokens,
                    serviceTier: tier
                )
                acc.cost += cost
                perModel[currentModel] = acc
                if let date {
                    let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? calendar.startOfDay(for: date)
                    perModelHourly[currentModel, default: [:]][hour, default: .zero] += usage
                }

            default:
                break
            }
        }

        let models = perModel
            .map { ModelUsage(model: $0.key, messageCount: $0.value.count, usage: $0.value.usage, costEstimate: $0.value.cost) }
            .sorted { $0.usage.total > $1.usage.total }
        let timeline = perModelHourly
            .flatMap { model, byHour in byHour.map { ModelBucket(model: model, start: $0.key, usage: $0.value) } }
            .sorted { $0.start < $1.start }

        guard messageCount > 0 || !models.isEmpty else { return nil }

        let title = threadName ?? firstUserTitle ?? fallbackTitle
        return SessionStats(
            title: title,
            messageCount: messageCount,
            firstActivity: firstActivity,
            lastActivity: lastActivity,
            models: models,
            timeline: timeline,
            activityIntervals: TranscriptParser.coalesceBursts(messageTimestamps)
        )
    }

    func messages(transcriptAt url: URL) async -> [SessionTranscriptMessage] {
        guard let data = try? Data(contentsOf: url) else { return [] }

        var messages: [SessionTranscriptMessage] = []
        let decoder = JSONDecoder()
        for (index, lineBytes) in data.split(separator: 0x0A /* \n */, omittingEmptySubsequences: true).enumerated() {
            guard let line = try? decoder.decode(CodexLine.self, from: Data(lineBytes)),
                  line.type == "event_msg",
                  let payload = line.payload else { continue }

            let role: SessionTranscriptMessage.Role
            switch payload.type {
            case "user_message":
                role = .user
            case "agent_message":
                role = .assistant
            default:
                continue
            }

            guard let text = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { continue }

            messages.append(SessionTranscriptMessage(
                id: "codex-\(index)",
                role: role,
                text: text,
                timestamp: ISO8601.parse(line.timestamp),
                model: nil
            ))
        }

        return messages
    }

    func executedCommands(transcriptAt url: URL) async -> [SessionCommandEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }

        var events: [SessionCommandEvent] = []
        let decoder = JSONDecoder()
        for lineBytes in data.split(separator: 0x0A /* \n */, omittingEmptySubsequences: true) {
            let lineData = Data(lineBytes)
            let timestamp = (try? decoder.decode(CodexLine.self, from: lineData))
                .flatMap { ISO8601.parse($0.timestamp) }
            guard let json = try? JSONSerialization.jsonObject(with: lineData) else { continue }

            var seen: Set<String> = []
            for command in Self.extractExecutedCommands(from: json, inheritedToolContext: false) {
                let cleaned = command.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { continue }
                events.append(SessionCommandEvent(command: cleaned, timestamp: timestamp))
            }
        }

        return events
    }

    func trackEvents(transcriptAt url: URL, session: Session) async -> [TrackEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }

        return await Task.detached(priority: .utility) {
            var state = CodexTranscriptTrackState(session: session)
            let decoder = JSONDecoder()

            for (index, lineBytes) in data.split(separator: 0x0A /* \n */, omittingEmptySubsequences: true).enumerated() {
                let lineData = Data(lineBytes)
                let line = try? decoder.decode(CodexLine.self, from: lineData)
                let timestamp = line.flatMap { ISO8601.parse($0.timestamp) }
                state.track(timestamp)

                guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
                let lineType = json.stringValue(for: "type")
                let payload = json.objectValue(for: "payload") ?? [:]
                let eventType = payload.stringValue(for: "type", "eventName", "event_name") ?? lineType ?? "StatusChanged"

                if lineType == "session_meta" {
                    state.applySessionMeta(payload)
                    continue
                }

                if lineType == "turn_context" {
                    state.currentTurnID = payload.stringValue(for: "turn_id", "turnID") ?? state.currentTurnID
                    state.currentAgentID = payload.stringValue(for: "agent_id", "agentID") ?? state.currentAgentID
                    state.currentAgentType = payload.stringValue(for: "agent_type", "agentType") ?? state.currentAgentType
                    continue
                }

                if let event = state.trackEvent(
                    lineIndex: index,
                    timestamp: timestamp,
                    eventType: eventType,
                    payload: payload,
                    rawLine: json
                ) {
                    state.events.append(event)
                }
            }

            return state.finalizedEvents()
        }.value
    }

    private func track(_ date: Date?, _ first: inout Date?, _ last: inout Date?) {
        guard let date else { return }
        if first == nil || date < first! { first = date }
        if last == nil || date > last! { last = date }
    }

    private static func extractExecutedCommands(from value: Any, inheritedToolContext: Bool) -> [String] {
        if let dictionary = value as? [String: Any] {
            let isToolContext = inheritedToolContext || indicatesToolExecution(dictionary)
            var commands: [String] = []

            if isToolContext {
                for key in commandKeys {
                    if let command = dictionary[key] as? String {
                        commands.append(command)
                    }
                }
            }

            for key in argumentKeys {
                if let argument = dictionary[key] as? String,
                   let parsed = parseJSONString(argument) {
                    commands.append(contentsOf: extractExecutedCommands(from: parsed, inheritedToolContext: isToolContext))
                }
            }

            for (key, child) in dictionary where !commandKeys.contains(key) {
                commands.append(contentsOf: extractExecutedCommands(from: child, inheritedToolContext: isToolContext))
            }
            return commands
        }

        if let array = value as? [Any] {
            return array.flatMap { extractExecutedCommands(from: $0, inheritedToolContext: inheritedToolContext) }
        }

        return []
    }

    private static func indicatesToolExecution(_ dictionary: [String: Any]) -> Bool {
        for key in contextKeys {
            guard let raw = dictionary[key] as? String else { continue }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty else { continue }
            if value == "bash" || value == "shell" || value == "terminal" || value == "exec_command" || value == "run_command" {
                return true
            }
            if value.contains("tool")
                || value.contains("exec")
                || value.contains("shell")
                || value.contains("terminal")
                || value.contains("command") {
                return true
            }
        }
        return false
    }

    private static func parseJSONString(_ string: String) -> Any? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static let commandKeys: Set<String> = [
        "command",
        "cmd",
        "command_line",
        "shell_command",
    ]

    private static let argumentKeys: Set<String> = [
        "arguments",
        "args",
        "input",
    ]

    private static let contextKeys: Set<String> = [
        "type",
        "name",
        "tool",
        "tool_name",
        "toolName",
        "kind",
        "event",
        "subtype",
        "category",
    ]
}

private struct CodexTranscriptTrackState {
    let session: Session
    var events: [TrackEvent] = []
    var currentTurnID: String?
    var currentAgentID: String?
    var currentAgentType: String?
    var firstActivity: Date?
    var lastActivity: Date?
    var sessionID: String
    var parentSessionID: String?
    var agentID: String?
    var agentType: String?
    var cwd: String?
    var isSubagent = false

    init(session: Session) {
        self.session = session
        self.sessionID = Self.normalizedSessionID(session.externalID.isEmpty ? session.id : session.externalID)
        self.cwd = session.cwd
    }

    mutating func track(_ date: Date?) {
        guard let date else { return }
        if firstActivity == nil || date < firstActivity! { firstActivity = date }
        if lastActivity == nil || date > lastActivity! { lastActivity = date }
    }

    mutating func applySessionMeta(_ payload: [String: Any]) {
        sessionID = Self.normalizedSessionID(payload.stringValue(for: "id", "session_id", "sessionID") ?? sessionID)
        cwd = payload.stringValue(for: "cwd") ?? cwd
        parentSessionID = Self.normalizedOptionalSessionID(payload.stringValue(
            for: "parent_session_id",
            "parentSessionID",
            "parentSessionId",
            "parent_thread_id",
            "parentThreadID",
            "parentThreadId"
        )) ?? parentSessionID
        agentID = payload.stringValue(for: "agent_id", "agentID") ?? agentID
        agentType = payload.stringValue(for: "agent_type", "agentType")
            ?? Self.role(from: payload)
            ?? agentType
        if parentSessionID != nil || Self.role(from: payload) == "subagent" {
            isSubagent = true
            if agentType == nil { agentType = "subagent" }
        }
    }

    mutating func trackEvent(
        lineIndex: Int,
        timestamp: Date?,
        eventType: String,
        payload: [String: Any],
        rawLine: [String: Any]
    ) -> TrackEvent? {
        let normalizedType = eventType.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalizedType.lowercased()
        let kind: TrackEventKind
        if Self.approvalRequestedTypes.contains(lower) || indicatesWaitingApproval(payload) {
            kind = .approvalRequested
        } else if Self.approvalResolvedTypes.contains(lower) {
            kind = Self.isDenied(payload) ? .approvalDenied : .approvalAllowed
        } else if Self.toolRequestedTypes.contains(lower) || hasToolCallShape(payload, rawLine: rawLine) {
            kind = .toolRequested
        } else if Self.toolCompletedTypes.contains(lower) {
            kind = Self.isFailure(payload) ? .toolFailed : .toolSucceeded
        } else {
            return nil
        }

        let toolName = payload.stringValue(for: "tool_name", "toolName", "name", "tool", "type")
            ?? rawLine.stringValue(for: "tool_name", "toolName", "name", "type")
        let toolUseID = payload.stringValue(for: "tool_use_id", "toolUseID", "toolUseId", "id", "call_id")
            ?? rawLine.stringValue(for: "tool_use_id", "toolUseID", "toolUseId", "id", "call_id")
        let approvalID = payload.stringValue(for: "approval_id", "approvalID", "request_id", "requestID")
            ?? rawLine.stringValue(for: "approval_id", "approvalID", "request_id", "requestID")
        let detailValue = payload.trackJSONValue(for: "tool_input", "toolInput", "input", "arguments")
        let detail = detailValue?.compactDescription
        let effectiveAgentID = payload.stringValue(for: "agent_id", "agentID")
            ?? currentAgentID
            ?? agentID
        let effectiveAgentType = payload.stringValue(for: "agent_type", "agentType")
            ?? currentAgentType
            ?? agentType

        return TrackEvent(
            id: "transcript::\(session.id)::\(lineIndex)::\(normalizedType)",
            timestamp: timestamp ?? lastActivity ?? session.lastModified,
            source: .transcript,
            kind: kind,
            provider: .codex,
            sessionID: sessionID,
            parentSessionID: parentSessionID,
            turnID: payload.stringValue(for: "turn_id", "turnID") ?? currentTurnID,
            agentID: effectiveAgentID,
            agentType: effectiveAgentType,
            toolUseID: toolUseID,
            approvalID: approvalID,
            toolName: toolName,
            permissionMode: payload.stringValue(for: "permission_mode", "permissionMode"),
            cwd: payload.stringValue(for: "cwd") ?? cwd,
            transcriptPath: session.filePath,
            summary: summary(kind: kind, toolName: toolName, agentType: effectiveAgentType),
            detail: detail,
            confidence: .medium
        )
    }

    func finalizedEvents() -> [TrackEvent] {
        guard isSubagent else { return events }
        let effectiveAgentID = agentID ?? sessionID
        let effectiveAgentType = agentType ?? "subagent"
        let startedAt = firstActivity ?? session.stats?.firstActivity ?? session.lastModified
        let endedAt = lastActivity ?? session.stats?.lastActivity ?? session.lastModified
        let start = TrackEvent(
            id: "transcript::\(session.id)::subagent-start",
            timestamp: startedAt,
            source: .transcript,
            kind: .subagentStarted,
            provider: .codex,
            sessionID: sessionID,
            parentSessionID: parentSessionID,
            turnID: currentTurnID,
            agentID: effectiveAgentID,
            agentType: effectiveAgentType,
            toolUseID: nil,
            approvalID: nil,
            toolName: nil,
            permissionMode: nil,
            cwd: cwd,
            transcriptPath: session.filePath,
            summary: "Started \(effectiveAgentType)",
            detail: session.stats?.title,
            confidence: .medium
        )
        let stop = TrackEvent(
            id: "transcript::\(session.id)::subagent-stop",
            timestamp: max(startedAt, endedAt),
            source: .transcript,
            kind: .subagentStopped,
            provider: .codex,
            sessionID: sessionID,
            parentSessionID: parentSessionID,
            turnID: currentTurnID,
            agentID: effectiveAgentID,
            agentType: effectiveAgentType,
            toolUseID: nil,
            approvalID: nil,
            toolName: nil,
            permissionMode: nil,
            cwd: cwd,
            transcriptPath: session.filePath,
            summary: "Stopped \(effectiveAgentType)",
            detail: session.stats?.title,
            confidence: .medium
        )
        return ([start] + events + [stop]).sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id < rhs.id
        }
    }

    private func hasToolCallShape(_ payload: [String: Any], rawLine: [String: Any]) -> Bool {
        payload.stringValue(for: "tool_name", "toolName", "tool", "call_id") != nil
            || rawLine.stringValue(for: "tool_name", "toolName", "tool", "call_id") != nil
    }

    private func indicatesWaitingApproval(_ payload: [String: Any]) -> Bool {
        let values = payload.stringArrayValue(for: "activeFlags", "active_flags")
            + [payload.stringValue(for: "status", "phase")].compactMap { $0 }
        return values.contains { value in
            let normalized = value.lowercased()
            return normalized.contains("waitingonapproval")
                || normalized.contains("waiting_on_approval")
                || normalized.contains("waiting approval")
        }
    }

    private func summary(kind: TrackEventKind, toolName: String?, agentType: String?) -> String {
        switch kind {
        case .toolRequested:
            "Requested \(toolName ?? "tool")"
        case .toolSucceeded:
            "\(toolName ?? "Tool") succeeded"
        case .toolFailed:
            "\(toolName ?? "Tool") failed"
        case .approvalRequested:
            "Approval requested for \(toolName ?? "tool")"
        case .approvalAllowed:
            "Approval allowed"
        case .approvalDenied:
            "Approval denied"
        case .subagentStarted:
            "Started \(agentType ?? "subagent")"
        case .subagentStopped:
            "Stopped \(agentType ?? "subagent")"
        default:
            kind.title
        }
    }

    private static let toolRequestedTypes: Set<String> = [
        "tool_call",
        "tool.started",
        "tool.requested",
        "exec_command",
        "function_call",
        "item/started",
    ]

    private static let toolCompletedTypes: Set<String> = [
        "tool_result",
        "tool.succeeded",
        "tool.failed",
        "item/completed",
    ]

    private static let approvalRequestedTypes: Set<String> = [
        "permission.asked",
        "approval.requested",
        "permissionrequest",
        "serverrequest/requested",
    ]

    private static let approvalResolvedTypes: Set<String> = [
        "permission.replied",
        "approval.allowed",
        "approval.denied",
        "serverrequest/resolved",
    ]

    private static func isFailure(_ payload: [String: Any]) -> Bool {
        [payload.stringValue(for: "status"), payload.stringValue(for: "result"), payload.stringValue(for: "error")]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains("fail") || $0.contains("error") || $0.contains("denied") }
    }

    private static func isDenied(_ payload: [String: Any]) -> Bool {
        [payload.stringValue(for: "decision"), payload.stringValue(for: "behavior"), payload.stringValue(for: "status")]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains("deny") || $0.contains("denied") || $0.contains("reject") }
    }

    private static func role(from payload: [String: Any]) -> String? {
        if let role = normalizeRole(payload.stringValue(for: "codex_session_role", "agent_role", "agent_type", "agentType")) {
            return role
        }
        if let source = payload["source"] as? [String: Any] {
            if let subagent = source["subagent"] as? Bool {
                return subagent ? "subagent" : "root"
            }
            return normalizeRole(source.stringValue(for: "role", "type", "kind"))
        }
        return normalizeRole(payload.stringValue(for: "source"))
    }

    private static func normalizeRole(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        if ["subagent", "child", "delegate", "delegated", "explorer", "worker"].contains(normalized) {
            return "subagent"
        }
        if ["root", "main", "primary", "cli", "codex-cli", "codex-tui"].contains(normalized) {
            return "root"
        }
        return nil
    }

    private static func normalizedOptionalSessionID(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = normalizedSessionID(value)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedSessionID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("codex:") {
            return String(trimmed.dropFirst("codex:".count))
        }
        return trimmed
    }
}

private extension Dictionary where Key == String, Value == Any {
    func stringValue(for keys: String...) -> String? {
        for key in keys {
            guard let value = self[key] else { continue }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    func objectValue(for keys: String...) -> [String: Any]? {
        for key in keys {
            if let object = self[key] as? [String: Any] { return object }
        }
        return nil
    }

    func stringArrayValue(for keys: String...) -> [String] {
        for key in keys {
            if let values = self[key] as? [String] {
                return values
            }
            if let values = self[key] as? [Any] {
                return values.compactMap { $0 as? String }
            }
        }
        return []
    }

    func trackJSONValue(for keys: String...) -> TrackJSONValue? {
        for key in keys {
            guard let value = self[key] else { continue }
            return TrackJSONValue(any: value)
        }
        return nil
    }
}

// MARK: - JSONL line shapes (only the fields we read)

private struct CodexLine: Decodable {
    let timestamp: String?
    let type: String?
    let payload: Payload?
    let serviceTier: String?
    let serviceTierSnake: String?
    let speed: String?
    let fast: Bool?

    enum CodingKeys: String, CodingKey {
        case timestamp, type, payload, speed, fast
        case serviceTier
        case serviceTierSnake = "service_tier"
    }

    var billingTier: ModelPricing.ServiceTier? {
        ModelPricing.ServiceTier.parse(serviceTier: serviceTier ?? serviceTierSnake, speed: speed, fast: fast)
    }

    struct Payload: Decodable {
        let type: String?          // inner event type for `event_msg`
        let model: String?         // `turn_context`
        let collaborationMode: CollaborationMode?
        let threadName: String?    // `thread_name_updated`
        let message: String?       // `user_message` / `agent_message`
        let info: TokenInfo?       // `token_count` (may be null)
        let serviceTier: String?
        let serviceTierSnake: String?
        let speed: String?
        let fast: Bool?

        enum CodingKeys: String, CodingKey {
            case type, model, message, info, serviceTier, speed, fast
            case serviceTierSnake = "service_tier"
            case collaborationMode = "collaboration_mode"
            case threadName = "thread_name"
        }

        var billingTier: ModelPricing.ServiceTier? {
            ModelPricing.ServiceTier.parse(serviceTier: serviceTier ?? serviceTierSnake, speed: speed, fast: fast)
        }
    }

    struct CollaborationMode: Decodable {
        let settings: Settings?
        struct Settings: Decodable {
            let model: String?
            let serviceTier: String?
            let serviceTierSnake: String?
            let speed: String?
            let fast: Bool?

            enum CodingKeys: String, CodingKey {
                case model, serviceTier, speed, fast
                case serviceTierSnake = "service_tier"
            }

            var billingTier: ModelPricing.ServiceTier? {
                ModelPricing.ServiceTier.parse(serviceTier: serviceTier ?? serviceTierSnake, speed: speed, fast: fast)
            }
        }
    }

    struct TokenInfo: Decodable {
        let lastTokenUsage: Usage?
        let totalTokenUsage: Usage?
        let serviceTier: String?
        let serviceTierSnake: String?
        let speed: String?
        let fast: Bool?
        enum CodingKeys: String, CodingKey {
            case lastTokenUsage = "last_token_usage"
            case totalTokenUsage = "total_token_usage"
            case serviceTier, speed, fast
            case serviceTierSnake = "service_tier"
        }

        var billingTier: ModelPricing.ServiceTier? {
            ModelPricing.ServiceTier.parse(serviceTier: serviceTier ?? serviceTierSnake, speed: speed, fast: fast)
        }
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let cachedInputTokens: Int?
        let outputTokens: Int?
        let serviceTier: String?
        let serviceTierSnake: String?
        let speed: String?
        let fast: Bool?
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case outputTokens = "output_tokens"
            case serviceTier, speed, fast
            case serviceTierSnake = "service_tier"
        }

        /// Codex `input_tokens` includes the cache-hit portion; split it out so
        /// the cached tokens are priced at the read rate, not the input rate.
        var tokenUsage: TokenUsage {
            let cached = cachedInputTokens ?? 0
            let input = max(0, rawInputTokens - cached)
            return TokenUsage(
                inputTokens: input,
                outputTokens: outputTokens ?? 0,
                cacheReadTokens: cached,
                cacheCreation5mTokens: 0,
                cacheCreation1hTokens: 0
            )
        }

        var rawInputTokens: Int { inputTokens ?? 0 }

        var billingTier: ModelPricing.ServiceTier? {
            ModelPricing.ServiceTier.parse(serviceTier: serviceTier ?? serviceTierSnake, speed: speed, fast: fast)
        }
    }
}

private enum ISO8601 {
    static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    static let withoutFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let d = try? withFraction.parse(string) { return d }
        return try? withoutFraction.parse(string)
    }
}
