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
                let cost = pricing.cost(
                    model: currentModel,
                    usage: usage,
                    contextInputTokens: delta.rawInputTokens
                )
                acc.cost += CostEstimate(standardAPI: cost)
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

// MARK: - JSONL line shapes (only the fields we read)

private struct CodexLine: Decodable {
    let timestamp: String?
    let type: String?
    let payload: Payload?

    struct Payload: Decodable {
        let type: String?          // inner event type for `event_msg`
        let model: String?         // `turn_context`
        let collaborationMode: CollaborationMode?
        let threadName: String?    // `thread_name_updated`
        let message: String?       // `user_message` / `agent_message`
        let info: TokenInfo?       // `token_count` (may be null)

        enum CodingKeys: String, CodingKey {
            case type, model, message, info
            case collaborationMode = "collaboration_mode"
            case threadName = "thread_name"
        }
    }

    struct CollaborationMode: Decodable {
        let settings: Settings?
        struct Settings: Decodable { let model: String? }
    }

    struct TokenInfo: Decodable {
        let lastTokenUsage: Usage?
        let totalTokenUsage: Usage?
        enum CodingKeys: String, CodingKey {
            case lastTokenUsage = "last_token_usage"
            case totalTokenUsage = "total_token_usage"
        }
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let cachedInputTokens: Int?
        let outputTokens: Int?
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case outputTokens = "output_tokens"
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
