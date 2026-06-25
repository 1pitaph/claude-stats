import Foundation

/// Parses one ZCode CLI session out of `~/.zcode/cli/db/db.sqlite`.
///
/// The ZCode database is already structured: `model_usage` carries per-request
/// token splits, durations, and cost-relevant model ids; `message` + `part`
/// hold the transcript; `tool_usage` records executed tool invocations. The
/// parser stitches them together into the shared ``SessionStats`` shape.
///
/// When the database is unavailable we fall back to scraping rollout JSONL
/// files via ``ZCodeRolloutParser``.
struct ZCodeTranscriptParser: Sendable {
    let paths: ZCodePaths
    let pricing: ModelPricing

    func parse(_ session: Session) -> SessionStats? {
        let databaseURL = URL(fileURLWithPath: session.filePath)
        guard let connection = try? SQLiteConnection(url: databaseURL, readOnly: true) else {
            return ZCodeRolloutParser(paths: paths, pricing: pricing).parse(session)
        }
        let usageRows = modelUsageRows(connection: connection, sessionID: session.externalID)
        let header = sessionHeader(connection: connection, sessionID: session.externalID)
        let messages = messageRows(connection: connection, sessionID: session.externalID)

        let modelUsages = aggregatedModelUsage(rows: usageRows, messageCounts: messageCounts(messages))
        let timeline = hourlyTimeline(rows: usageRows)
        let messageCount = messages.filter { $0.role == .user || $0.role == .assistant }.count

        // Fall back to the JSONL rollout if the SQLite database has no usage
        // rows for this session yet.
        if modelUsages.isEmpty && messageCount == 0 {
            return ZCodeRolloutParser(paths: paths, pricing: pricing).parse(session)
        }

        let first = usageRows.compactMap(\.startedAt).min()
            ?? header?.timeCreated
            ?? messages.compactMap(\.timestamp).min()
        let last = usageRows.compactMap { $0.completedAt ?? $0.startedAt }.max()
            ?? header?.timeUpdated
            ?? messages.compactMap(\.timestamp).max()
            ?? session.lastModified

        return SessionStats(
            title: header?.title.flatMap { TitleSanitizer.sanitize($0) }
                ?? messages.first(where: { $0.role == .user }).flatMap { TitleSanitizer.sanitize($0.text) }
                ?? session.projectDisplayName,
            messageCount: messageCount,
            firstActivity: first,
            lastActivity: last,
            models: modelUsages,
            timeline: timeline,
            activityIntervals: TranscriptParser.coalesceBursts(messages.compactMap(\.timestamp))
        )
    }

    func messages(for session: Session) -> [SessionTranscriptMessage] {
        guard let connection = try? SQLiteConnection(url: URL(fileURLWithPath: session.filePath), readOnly: true) else {
            return ZCodeRolloutParser(paths: paths, pricing: pricing).messages(for: session)
        }
        return messageRows(connection: connection, sessionID: session.externalID)
    }

    func executedCommands(for session: Session) -> [SessionCommandEvent] {
        guard let connection = try? SQLiteConnection(url: URL(fileURLWithPath: session.filePath), readOnly: true),
              ProviderSQLiteHelpers.tableExists("tool_usage", in: connection) else {
            return []
        }
        let columns = ProviderSQLiteHelpers.columns(in: "tool_usage", connection: connection)
        guard columns.contains("session_id"), columns.contains("tool_name") else { return [] }
        let q = ProviderSQLiteHelpers.self
        let select = [
            q.expression("started_at", columns: columns, default: "0", alias: "started_at"),
            q.expression("tool_name", columns: columns, default: "''", alias: "tool_name"),
            q.coalescedExpression(["error_message"], columns: columns, default: "NULL", alias: "error_message"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM tool_usage WHERE session_id = ? ORDER BY started_at") else {
            return []
        }
        try? statement.bind(session.externalID, at: 1)

        var events: [SessionCommandEvent] = []
        while (try? statement.step()) == true {
            let name = statement.columnString(1)?.lowercased() ?? ""
            guard ["bash", "shell", "terminal", "exec", "run", "runcommand", "run_command"].contains(where: { name.contains($0) }) else {
                continue
            }
            let timestamp = ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(0))
            // ZCode does not store the actual command string on `tool_usage`;
            // surface the tool name + status so the UI can still show that a
            // shell tool fired at a particular moment.
            events.append(SessionCommandEvent(command: name, timestamp: timestamp))
        }
        return events
    }

    // MARK: model_usage

    private struct ModelUsageRow {
        let model: String
        let usage: TokenUsage
        let startedAt: Date?
        let completedAt: Date?
    }

    private func modelUsageRows(connection: SQLiteConnection, sessionID: String) -> [ModelUsageRow] {
        guard ProviderSQLiteHelpers.tableExists("model_usage", in: connection) else { return [] }
        let columns = ProviderSQLiteHelpers.columns(in: "model_usage", connection: connection)
        guard columns.contains("session_id"), columns.contains("model_id") else { return [] }
        let q = ProviderSQLiteHelpers.self
        let select = [
            q.expression("model_id", columns: columns, default: "''", alias: "model_id"),
            q.expression("input_tokens", columns: columns, default: "0", alias: "input_tokens"),
            q.expression("output_tokens", columns: columns, default: "0", alias: "output_tokens"),
            q.expression("cache_read_input_tokens", columns: columns, default: "0", alias: "cache_read_input_tokens"),
            q.expression("cache_creation_input_tokens", columns: columns, default: "0", alias: "cache_creation_input_tokens"),
            q.expression("reasoning_tokens", columns: columns, default: "0", alias: "reasoning_tokens"),
            q.expression("started_at", columns: columns, default: "0", alias: "started_at"),
            q.expression("completed_at", columns: columns, default: "0", alias: "completed_at"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare(
            "SELECT \(select) FROM model_usage WHERE session_id = ? AND status = 'completed' ORDER BY started_at"
        ) else { return [] }
        try? statement.bind(sessionID, at: 1)

        var rows: [ModelUsageRow] = []
        while (try? statement.step()) == true {
            let model = statement.columnString(0)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !model.isEmpty else { continue }
            let reasoning = q.columnInt(statement, 5)
            let output = q.columnInt(statement, 2)
            // ZCode tracks reasoning tokens separately. The shared TokenUsage
            // model lumps them into `outputTokens` (mirroring Codex), so add
            // any reasoning total to the output total.
            let usage = TokenUsage(
                inputTokens: q.columnInt(statement, 1),
                outputTokens: output + reasoning,
                cacheReadTokens: q.columnInt(statement, 3),
                cacheCreation5mTokens: q.columnInt(statement, 4),
                cacheCreation1hTokens: 0
            )
            rows.append(ModelUsageRow(
                model: model,
                usage: usage,
                startedAt: ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(6)),
                completedAt: ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(7))
            ))
        }
        return rows
    }

    private func aggregatedModelUsage(rows: [ModelUsageRow],
                                      messageCounts: [String: Int]) -> [ModelUsage] {
        guard !rows.isEmpty else { return [] }
        var totals: [String: (count: Int, usage: TokenUsage)] = [:]
        for row in rows {
            var acc = totals[row.model] ?? (0, .zero)
            acc.count += 1
            acc.usage += row.usage
            totals[row.model] = acc
        }
        return totals
            .map { (model, accumulated) -> ModelUsage in
                let count = max(accumulated.count, messageCounts[model] ?? 0)
                return ModelUsage(
                    model: model,
                    messageCount: count,
                    usage: accumulated.usage,
                    costEstimate: pricing.costEstimate(model: model, usage: accumulated.usage)
                )
            }
            .sorted { $0.usage.total > $1.usage.total }
    }

    private func hourlyTimeline(rows: [ModelUsageRow]) -> [ModelBucket] {
        guard !rows.isEmpty else { return [] }
        let calendar = Calendar.current
        var buckets: [String: [Date: TokenUsage]] = [:]
        for row in rows {
            guard let date = row.startedAt ?? row.completedAt else { continue }
            let start = calendar.dateInterval(of: .hour, for: date)?.start ?? date
            buckets[row.model, default: [:]][start, default: .zero] += row.usage
        }
        return buckets
            .flatMap { model, byStart in
                byStart.map { ModelBucket(model: model, start: $0.key, usage: $0.value) }
            }
            .sorted { $0.start < $1.start }
    }

    // MARK: session row

    private struct SessionHeader {
        let title: String?
        let timeCreated: Date?
        let timeUpdated: Date?
    }

    private func sessionHeader(connection: SQLiteConnection, sessionID: String) -> SessionHeader? {
        guard ProviderSQLiteHelpers.tableExists("session", in: connection) else { return nil }
        let columns = ProviderSQLiteHelpers.columns(in: "session", connection: connection)
        guard columns.contains("id") else { return nil }
        let q = ProviderSQLiteHelpers.self
        let select = [
            q.coalescedExpression(["title", "slug"], columns: columns, default: "NULL", alias: "title"),
            q.expression("time_created", columns: columns, default: "0", alias: "time_created"),
            q.expression("time_updated", columns: columns, default: "0", alias: "time_updated"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare(
            "SELECT \(select) FROM session WHERE id = ? LIMIT 1"
        ) else { return nil }
        try? statement.bind(sessionID, at: 1)
        guard (try? statement.step()) == true else { return nil }
        return SessionHeader(
            title: statement.columnString(0)?.trimmingCharacters(in: .whitespacesAndNewlines),
            timeCreated: ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(1)),
            timeUpdated: ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(2))
        )
    }

    // MARK: message + part

    private func messageRows(connection: SQLiteConnection, sessionID: String) -> [SessionTranscriptMessage] {
        guard ProviderSQLiteHelpers.tableExists("message", in: connection) else { return [] }
        guard let messageStatement = try? connection.prepare(
            "SELECT id, time_created, data FROM message WHERE session_id = ? ORDER BY time_created, id"
        ) else { return [] }
        try? messageStatement.bind(sessionID, at: 1)

        // Collect message metadata first (role, timestamp, optional model).
        var headers: [(id: String, role: SessionTranscriptMessage.Role, timestamp: Date?, model: String?)] = []
        while (try? messageStatement.step()) == true {
            guard let id = messageStatement.columnString(0), !id.isEmpty else { continue }
            let timestamp = ProviderDateParser.date(fromSQLiteNumber: messageStatement.columnInt64(1))
            let dictionary = ProviderJSON.dictionary(from: messageStatement.columnString(2))
            let role = dictionary
                .flatMap { ProviderTranscriptExtraction.role(from: $0) } ?? .user
            let model = dictionary.flatMap { dict -> String? in
                if let modelDict = dict["model"] as? [String: Any] {
                    return ProviderJSON.string(modelDict, keys: ["modelID", "model_id", "id", "name"])
                }
                return ProviderJSON.string(dict, keys: ["model", "modelID", "model_id"])
            }
            headers.append((id, role, timestamp, model))
        }
        guard !headers.isEmpty else { return [] }

        // Concatenate all `part.data.text` fragments per message id.
        var textsByMessageID: [String: String] = [:]
        if ProviderSQLiteHelpers.tableExists("part", in: connection) {
            guard let partStatement = try? connection.prepare(
                "SELECT message_id, data FROM part WHERE session_id = ? ORDER BY time_created, id"
            ) else { return [] }
            try? partStatement.bind(sessionID, at: 1)
            while (try? partStatement.step()) == true {
                guard let messageID = partStatement.columnString(0), !messageID.isEmpty else { continue }
                guard let dictionary = ProviderJSON.dictionary(from: partStatement.columnString(1)) else { continue }
                guard let fragment = ProviderTranscriptExtraction.text(from: dictionary), !fragment.isEmpty else { continue }
                if textsByMessageID[messageID] != nil {
                    textsByMessageID[messageID]! += "\n" + fragment
                } else {
                    textsByMessageID[messageID] = fragment
                }
            }
        }

        return headers.compactMap { header in
            let text = textsByMessageID[header.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            return SessionTranscriptMessage(
                id: "zcode-\(header.id)",
                role: header.role,
                text: text,
                timestamp: header.timestamp,
                model: header.model
            )
        }
    }

    private func messageCounts(_ messages: [SessionTranscriptMessage]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for message in messages where message.role == .assistant {
            if let model = message.model, !model.isEmpty {
                counts[model, default: 0] += 1
            }
        }
        return counts
    }
}
