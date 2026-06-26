import Foundation

/// JSONL-backed fallback for the ZCode provider.
///
/// Used when `~/.zcode/cli/db/db.sqlite` is unavailable (fresh install, schema
/// migration, or a ZCode build that hasn't enabled the database yet). Each
/// `rollout/model-io-sess_<uuid>.jsonl` file is one session's worth of
/// per-request rollouts; we aggregate the `response.usage` blocks across
/// lines.
struct ZCodeRolloutParser: Sendable {
    let paths: ZCodePaths
    let pricing: ModelPricing

    init(paths: ZCodePaths, pricing: ModelPricing = .fallback) {
        self.paths = paths
        self.pricing = pricing
    }

    // MARK: - Discovery

    func discoverSessions() -> [Session] {
        let directory = paths.rolloutDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("model-io-sess_") }
            .compactMap { url -> Session? in
                guard let sessionID = sessionID(fromFileName: url.lastPathComponent) else { return nil }
                let snapshot = ProviderStorageHelpers.snapshot(for: [url])
                let firstUserMessage = firstUserMessageText(at: url)
                return Session(
                    id: "zcode::rollout::\(sessionID)",
                    externalID: sessionID,
                    provider: .zcode,
                    projectDirectoryName: firstUserMessage ?? sessionID,
                    filePath: url.path,
                    cwd: nil,
                    lastModified: snapshot.modified,
                    fileSize: snapshot.size
                )
            }
    }

    private func sessionID(fromFileName name: String) -> String? {
        let prefix = "model-io-"
        guard name.hasPrefix(prefix), name.hasSuffix(".jsonl") else { return nil }
        return String(name.dropFirst(prefix.count).dropLast(".jsonl".count))
    }

    // MARK: - Parse

    func parse(_ session: Session) -> SessionStats? {
        let url = URL(fileURLWithPath: session.filePath)
        guard let stream = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var totals: [String: TokenUsage] = [:]
        var timeline: [String: [Date: TokenUsage]] = [:]
        var modelCounts: [String: Int] = [:]
        var firstActivity: Date?
        var lastActivity: Date?
        var firstUserMessage: String?
        let calendar = Calendar.current

        stream.enumerateLines { line, _ in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            if firstUserMessage == nil,
               let request = object["request"] as? [String: Any],
               let messages = request["messages"] as? [[String: Any]],
               let user = messages.first(where: { ($0["role"] as? String) == "user" }),
               let content = user["content"] as? String {
                firstUserMessage = content
            }

            let model = (object["model"] as? [String: Any])
                .flatMap { ProviderJSON.string($0, keys: ["modelID", "model_id", "id", "name"]) }
                ?? "zcode"

            let completedAt = ProviderJSON.date(object, keys: ["completedAt"])
            if let completedAt {
                firstActivity = min(firstActivity ?? completedAt, completedAt)
                lastActivity = max(lastActivity ?? completedAt, completedAt)
            }

            guard let response = object["response"] as? [String: Any],
                  let usageDict = response["usage"] as? [String: Any] else { return }

            let usage = TokenUsage(
                inputTokens: ProviderJSON.int(usageDict, keys: ["inputTokens", "input_tokens"]) ?? 0,
                outputTokens: ProviderJSON.int(usageDict, keys: ["outputTokens", "output_tokens"]) ?? 0,
                cacheReadTokens: ProviderJSON.int(usageDict, keys: ["cacheReadTokens", "cache_read_tokens", "cache_read_input_tokens"]) ?? 0,
                cacheCreation5mTokens: ProviderJSON.int(usageDict, keys: ["cacheWriteTokens", "cache_write_tokens", "cache_creation_input_tokens"]) ?? 0,
                cacheCreation1hTokens: 0
            )
            guard usage.total > 0 else { return }

            totals[model, default: .zero] += usage
            modelCounts[model, default: 0] += 1
            if let completedAt {
                let bucket = calendar.dateInterval(of: .hour, for: completedAt)?.start ?? completedAt
                timeline[model, default: [:]][bucket, default: .zero] += usage
            }
        }

        guard !totals.isEmpty else { return nil }

        let modelUsages = totals
            .map { model, usage in
                ModelUsage(
                    model: model,
                    messageCount: max(1, modelCounts[model] ?? 0),
                    usage: usage,
                    costEstimate: pricing.costEstimate(model: model, usage: usage)
                )
            }
            .sorted { $0.usage.total > $1.usage.total }

        let buckets = timeline.flatMap { model, byStart in
            byStart.map { ModelBucket(model: model, start: $0.key, usage: $0.value) }
        }.sorted { $0.start < $1.start }

        let title = firstUserMessage.flatMap { TitleSanitizer.sanitize($0) }
            ?? session.projectDisplayName

        return SessionStats(
            title: title,
            messageCount: modelCounts.values.reduce(0, +),
            firstActivity: firstActivity,
            lastActivity: lastActivity ?? session.lastModified,
            models: modelUsages,
            timeline: buckets,
            activityIntervals: []
        )
    }

    func messages(for session: Session) -> [SessionTranscriptMessage] {
        let url = URL(fileURLWithPath: session.filePath)
        guard let stream = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var results: [SessionTranscriptMessage] = []
        var lineIndex = 0
        stream.enumerateLines { line, _ in
            defer { lineIndex += 1 }
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            let timestamp = ProviderJSON.date(object, keys: ["completedAt"])
            let model = (object["model"] as? [String: Any])
                .flatMap { ProviderJSON.string($0, keys: ["modelID", "model_id"]) }
            if let request = object["request"] as? [String: Any],
               let messages = request["messages"] as? [[String: Any]] {
                for message in messages {
                    guard let role = ProviderTranscriptExtraction.role(from: message) else { continue }
                    guard role == .user || role == .system else { continue }
                    guard let text = ProviderTranscriptExtraction.text(from: message),
                          !text.isEmpty else { continue }
                    results.append(SessionTranscriptMessage(
                        id: "zcode-rollout-\(lineIndex)-\(role.rawValue)",
                        role: role,
                        text: text,
                        timestamp: timestamp,
                        model: model
                    ))
                }
            }
            if let response = object["response"] as? [String: Any],
               let text = response["text"] as? String,
               !text.isEmpty {
                results.append(SessionTranscriptMessage(
                    id: "zcode-rollout-\(lineIndex)-assistant",
                    role: .assistant,
                    text: text,
                    timestamp: timestamp,
                    model: model
                ))
            }
        }
        return results
    }

    // MARK: - Helpers

    private func firstUserMessageText(at url: URL) -> String? {
        guard let stream = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var result: String?
        stream.enumerateLines { line, stop in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let request = object["request"] as? [String: Any],
                  let messages = request["messages"] as? [[String: Any]] else {
                return
            }
            if let user = messages.first(where: { ($0["role"] as? String) == "user" }),
               let content = user["content"] as? String,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result = TitleSanitizer.sanitize(content)
                stop = true
            }
        }
        return result
    }
}
