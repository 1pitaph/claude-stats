import Foundation

/// Parses a Claude Code `.jsonl` transcript into ``SessionStats``: title,
/// message count, activity window, per-model token totals (priced), and an
/// hourly per-model token timeline.
///
/// Reads the file whole and splits on newlines — transcripts are typically
/// small. (A pathologically huge transcript would be loaded fully into
/// memory; acceptable for v0.1.)
struct TranscriptParser: Sendable {
    let pricing: ModelPricing
    private static let syntheticModelID = "<synthetic>"

    func parse(transcriptAt url: URL, fallbackTitle: String) async -> SessionStats? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        var perModel: [String: (count: Int, usage: TokenUsage, cost: CostEstimate)] = [:]
        var perModelHourly: [String: [Date: TokenUsage]] = [:]
        var billableMessages: [BillableMessage] = []
        var messageCount = 0
        var firstActivity: Date?
        var lastActivity: Date?
        var aiTitle: String?
        var firstUserTitle: String?
        var messageTimestamps: [Date] = []
        let calendar = Calendar.current

        let decoder = JSONDecoder()
        for lineBytes in data.split(separator: 0x0A /* \n */, omittingEmptySubsequences: true) {
            guard let line = try? decoder.decode(TranscriptLine.self, from: Data(lineBytes)) else { continue }
            switch line.type {
            case "ai-title":
                if let t = line.aiTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    aiTitle = t
                }

            case "assistant":
                messageCount += 1
                let date = ISO8601.parse(line.timestamp)
                track(date, &firstActivity, &lastActivity)
                if let date { messageTimestamps.append(date) }
                let model = line.message?.model ?? "unknown"
                let usage = line.message?.usage?.tokenUsage ?? .zero
                let speed = line.message?.usage?.speed
                let webSearchRequests = line.message?.usage?.serverToolUse?.webSearchRequests ?? 0
                let cost = pricing.claudeCostEstimate(
                    model: model,
                    usage: usage,
                    speed: speed,
                    webSearchRequests: webSearchRequests
                )
                if model == Self.syntheticModelID, usage.total == 0, cost.detailedBilling == 0 {
                    continue
                }

                // Subagent (Task tool) turns get written to BOTH the subagent's
                // own JSONL and the parent session's JSONL with identical
                // `message.id` and `requestId`. Keep that pair so cross-session
                // aggregation can dedup — see ``BillableMessage``.
                let hash: String?
                if let msgID = line.message?.id, let reqID = line.requestId {
                    hash = "\(msgID):\(reqID)"
                } else {
                    hash = nil
                }
                billableMessages.append(BillableMessage(
                    hash: hash,
                    model: model,
                    usage: usage,
                    cost: cost,
                    timestamp: date
                ))

                if usage.total > 0 {
                    var acc = perModel[model] ?? (0, .zero, .zero)
                    acc.count += 1
                    acc.usage += usage
                    acc.cost += cost
                    perModel[model] = acc
                    if let date {
                        let hour = calendar.dateInterval(of: .hour, for: date)?.start
                            ?? calendar.startOfDay(for: date)
                        perModelHourly[model, default: [:]][hour, default: .zero] += usage
                    }
                } else {
                    // Still count the model so a session with assistant turns
                    // but zero recorded usage doesn't vanish.
                    var acc = perModel[model] ?? (0, .zero, .zero)
                    acc.count += 1
                    acc.cost += cost
                    perModel[model] = acc
                }

            case "user":
                messageCount += 1
                let date = ISO8601.parse(line.timestamp)
                track(date, &firstActivity, &lastActivity)
                if let date { messageTimestamps.append(date) }
                if firstUserTitle == nil, let raw = line.message?.content?.titleText,
                   let cleaned = TitleSanitizer.sanitize(raw) {
                    firstUserTitle = cleaned
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

        // Empty transcript (only queue-ops / snapshots): not worth showing.
        guard messageCount > 0 || !models.isEmpty else { return nil }

        let title = aiTitle ?? firstUserTitle ?? fallbackTitle
        return SessionStats(
            title: title,
            messageCount: messageCount,
            firstActivity: firstActivity,
            lastActivity: lastActivity,
            models: models,
            timeline: timeline,
            activityIntervals: Self.coalesceBursts(messageTimestamps),
            billableMessages: billableMessages
        )
    }

    func messages(transcriptAt url: URL) async -> [SessionTranscriptMessage] {
        guard let data = try? Data(contentsOf: url) else { return [] }

        var messages: [SessionTranscriptMessage] = []
        let decoder = JSONDecoder()
        for (index, lineBytes) in data.split(separator: 0x0A /* \n */, omittingEmptySubsequences: true).enumerated() {
            guard let line = try? decoder.decode(TranscriptLine.self, from: Data(lineBytes)),
                  let content = line.message?.content,
                  let text = content.displayText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { continue }

            let role: SessionTranscriptMessage.Role
            switch line.type {
            case "user":
                role = content.isToolOnly ? .tool : .user
            case "assistant":
                role = .assistant
            default:
                continue
            }

            messages.append(SessionTranscriptMessage(
                id: "claude-\(index)",
                role: role,
                text: text,
                timestamp: ISO8601.parse(line.timestamp),
                model: line.message?.model
            ))
        }

        return messages
    }

    func executedCommands(transcriptAt url: URL) async -> [SessionCommandEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }

        var commands: [SessionCommandEvent] = []
        let decoder = JSONDecoder()
        for lineBytes in data.split(separator: 0x0A /* \n */, omittingEmptySubsequences: true) {
            guard let line = try? decoder.decode(TranscriptLine.self, from: Data(lineBytes)),
                  line.type == "assistant",
                  let content = line.message?.content else {
                continue
            }

            let timestamp = ISO8601.parse(line.timestamp)
            for command in content.executedShellCommands {
                commands.append(SessionCommandEvent(command: command, timestamp: timestamp))
            }
        }

        return commands
    }

    private func track(_ date: Date?, _ first: inout Date?, _ last: inout Date?) {
        guard let date else { return }
        if first == nil || date < first! { first = date }
        if last == nil || date > last! { last = date }
    }

    /// Adjacent message timestamps within ``burstGap`` collapse into one
    /// interval; a lone message (or a sub-``minBurst`` run) is widened to
    /// ``minBurst`` so it stays visible on a timeline.
    private static let burstGap: TimeInterval = 5 * 60
    private static let minBurst: TimeInterval = 30

    static func coalesceBursts(_ timestamps: [Date]) -> [DateInterval] {
        let sorted = timestamps.sorted()
        guard let first = sorted.first else { return [] }
        var out: [DateInterval] = []
        var start = first
        var end = first
        for t in sorted.dropFirst() {
            if t.timeIntervalSince(end) <= burstGap {
                end = max(end, t)
            } else {
                out.append(burstInterval(start, end))
                start = t; end = t
            }
        }
        out.append(burstInterval(start, end))
        return out
    }

    private static func burstInterval(_ start: Date, _ end: Date) -> DateInterval {
        end.timeIntervalSince(start) >= minBurst
            ? DateInterval(start: start, end: end)
            : DateInterval(start: start, duration: minBurst)
    }
}

// MARK: - JSONL line shapes (only the fields we read)

private struct TranscriptLine: Decodable {
    let type: String?
    let timestamp: String?
    let aiTitle: String?
    let message: Message?
    /// Top-level `requestId` — paired with `message.id` to dedup subagent
    /// turns that appear in both the parent and child JSONL files.
    let requestId: String?

    struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: Usage?
        let content: Content?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreation: CacheCreation?
        let speed: String?
        let serverToolUse: ServerToolUse?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreation = "cache_creation"
            case speed
            case serverToolUse = "server_tool_use"
        }

        var tokenUsage: TokenUsage {
            let fiveM = cacheCreation?.ephemeral5m ?? 0
            let oneH = cacheCreation?.ephemeral1h ?? 0
            // Prefer the 5m/1h breakdown. If it's absent, attribute the
            // lump-sum `cache_creation_input_tokens` to the 5m bucket so the
            // tokens aren't lost (and aren't double-counted with the breakdown).
            let (c5, c1) = (fiveM > 0 || oneH > 0) ? (fiveM, oneH) : (cacheCreationInputTokens ?? 0, 0)
            return TokenUsage(
                inputTokens: inputTokens ?? 0,
                outputTokens: outputTokens ?? 0,
                cacheReadTokens: cacheReadInputTokens ?? 0,
                cacheCreation5mTokens: c5,
                cacheCreation1hTokens: c1
            )
        }
    }

    struct CacheCreation: Decodable {
        let ephemeral5m: Int?
        let ephemeral1h: Int?
        enum CodingKeys: String, CodingKey {
            case ephemeral5m = "ephemeral_5m_input_tokens"
            case ephemeral1h = "ephemeral_1h_input_tokens"
        }
    }

    struct ServerToolUse: Decodable {
        let webSearchRequests: Int?

        enum CodingKeys: String, CodingKey {
            case webSearchRequests = "web_search_requests"
        }
    }

    /// `message.content` is a string for plain prompts, or an array of content
    /// blocks otherwise. Text feeds both titles and the transcript detail pane;
    /// tool blocks get a short readable label instead of raw JSON.
    enum Content: Decodable {
        case text(String)
        case blocks([ContentBlock])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                self = .text(s)
            } else {
                self = .blocks((try? container.decode([ContentBlock].self)) ?? [])
            }
        }

        var titleText: String? {
            switch self {
            case .text(let text):
                return text
            case .blocks(let blocks):
                return blocks.first { $0.type == "text" }?.text
            }
        }

        var displayText: String? {
            let parts: [String]
            switch self {
            case .text(let text):
                parts = [text]
            case .blocks(let blocks):
                parts = blocks.compactMap(\.displayText)
            }
            let text = parts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            return text.isEmpty ? nil : text
        }

        var isToolOnly: Bool {
            guard case .blocks(let blocks) = self, !blocks.isEmpty else { return false }
            return blocks.allSatisfy { $0.isToolBlock }
        }

        var executedShellCommands: [String] {
            guard case .blocks(let blocks) = self else { return [] }
            return blocks.compactMap(\.executedShellCommand)
        }
    }

    struct ContentBlock: Decodable {
        let type: String?
        let text: String?
        let name: String?
        let input: ToolInput?
        let content: BlockContent?

        var displayText: String? {
            switch type {
            case "text":
                return text
            case "tool_use":
                return name.map { "Tool call: \($0)" }
            case "tool_result":
                if let content = content?.text, !content.isEmpty {
                    return "Tool result:\n\(content)"
                }
                return "Tool result"
            default:
                return text ?? content?.text
            }
        }

        var isToolBlock: Bool {
            type == "tool_use" || type == "tool_result"
        }

        var executedShellCommand: String? {
            guard type == "tool_use", Self.isShellToolName(name) else { return nil }
            return input?.shellCommandValue
        }

        private static func isShellToolName(_ name: String?) -> Bool {
            let normalized = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { return false }
            if ["bash", "shell", "sh", "zsh", "fish", "terminal", "exec_command", "run_command", "shell_command"].contains(normalized) {
                return true
            }
            return normalized.contains("bash") || normalized.contains("shell") || normalized.contains("terminal")
        }
    }

    struct ToolInput: Decodable {
        let command: String?
        let cmd: String?
        let commandLine: String?
        let shellCommandRaw: String?

        enum CodingKeys: String, CodingKey {
            case command
            case cmd
            case commandLine = "command_line"
            case shellCommandRaw = "shell_command"
        }

        var shellCommandValue: String? {
            [command, cmd, commandLine, shellCommandRaw]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
                .first
        }
    }

    enum BlockContent: Decodable {
        case text(String)
        case ignored

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else {
                self = .ignored
            }
        }

        var text: String? {
            switch self {
            case .text(let text): text
            case .ignored: nil
            }
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
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
