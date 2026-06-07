import Foundation

struct HermesTranscriptParser: Sendable {
    let pricing: ModelPricing

    func parse(_ session: Session) -> SessionStats? {
        let databaseURL = URL(fileURLWithPath: session.filePath)
        guard let connection = try? SQLiteConnection(url: databaseURL, readOnly: true),
              let row = sessionRow(connection: connection, sessionID: session.externalID) else {
            return nil
        }
        let messages = messageRows(connection: connection, sessionID: session.externalID)
        let fallbackUsage = usageFromMessages(connection: connection, sessionID: session.externalID)
        let usage = row.usage.total > 0 ? row.usage : fallbackUsage
        let messageCount = messages.filter { $0.role == .user || $0.role == .assistant }.count
        guard usage.total > 0 || messageCount > 0 else { return nil }

        let model = row.model ?? "hermes"
        let modelUsage = ModelUsage(
            model: model,
            messageCount: max(1, messageCount),
            usage: usage,
            costEstimate: row.cost.map { CostEstimate(standardAPI: $0) }
                ?? pricing.costEstimate(model: model, usage: usage)
        )
        let first = row.startedAt ?? messages.compactMap(\.timestamp).min()
        let last = row.endedAt ?? row.updatedAt ?? messages.compactMap(\.timestamp).max() ?? session.lastModified
        let bucketStart = Calendar.current.dateInterval(of: .hour, for: last)?.start ?? last
        return SessionStats(
            title: row.title
                ?? messages.first(where: { $0.role == .user }).flatMap { TitleSanitizer.sanitize($0.text) }
                ?? session.projectDisplayName,
            messageCount: messageCount,
            firstActivity: first,
            lastActivity: last,
            models: usage.total > 0 ? [modelUsage] : [],
            timeline: usage.total > 0 ? [ModelBucket(model: model, start: bucketStart, usage: usage)] : [],
            activityIntervals: TranscriptParser.coalesceBursts(messages.compactMap(\.timestamp))
        )
    }

    func messages(for session: Session) -> [SessionTranscriptMessage] {
        guard let connection = try? SQLiteConnection(url: URL(fileURLWithPath: session.filePath), readOnly: true) else {
            return []
        }
        return messageRows(connection: connection, sessionID: session.externalID)
    }

    func executedCommands(for session: Session) -> [SessionCommandEvent] {
        guard let connection = try? SQLiteConnection(url: URL(fileURLWithPath: session.filePath), readOnly: true),
              ProviderSQLiteHelpers.tableExists("messages", in: connection) else {
            return []
        }
        let columns = ProviderSQLiteHelpers.columns(in: "messages", connection: connection)
        guard sessionIDColumn(in: columns) != nil else { return [] }
        let q = ProviderSQLiteHelpers.self
        let sessionColumn = sessionIDColumn(in: columns)!
        let select = [
            q.coalescedExpression(["created_at", "timestamp", "time_created"], columns: columns, default: "0", alias: "created_at"),
            q.expression("content", columns: columns, default: "''", alias: "content"),
            q.expression("tool_name", columns: columns, default: "NULL", alias: "tool_name"),
            q.coalescedExpression(["tool_calls", "toolCalls"], columns: columns, default: "NULL", alias: "tool_calls"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM messages WHERE \(q.quotedIdentifier(sessionColumn)) = ?") else {
            return []
        }
        try? statement.bind(session.externalID, at: 1)

        var events: [SessionCommandEvent] = []
        while (try? statement.step()) == true {
            let timestamp = date(from: statement, index: 0)
            var object: [String: Any] = [:]
            object["content"] = statement.columnString(1)
            object["tool_name"] = statement.columnString(2)
            if let toolCalls = ProviderJSON.object(from: statement.columnString(3)) {
                object["tool_calls"] = toolCalls
            }
            events += ProviderTranscriptExtraction.commands(from: object)
                .map { SessionCommandEvent(command: $0, timestamp: timestamp) }
        }
        var seen: Set<String> = []
        return events.compactMap { event in
            let key = "\(event.command)|\(event.timestamp?.timeIntervalSince1970 ?? 0)"
            guard seen.insert(key).inserted else { return nil }
            return event
        }
    }

    private struct SessionRow {
        let title: String?
        let model: String?
        let startedAt: Date?
        let endedAt: Date?
        let updatedAt: Date?
        let usage: TokenUsage
        let cost: Double?
    }

    private func sessionRow(connection: SQLiteConnection, sessionID: String) -> SessionRow? {
        guard ProviderSQLiteHelpers.tableExists("sessions", in: connection) else { return nil }
        let columns = ProviderSQLiteHelpers.columns(in: "sessions", connection: connection)
        let idColumn = ["id", "session_id"].first(where: columns.contains)
        guard let idColumn else { return nil }
        let q = ProviderSQLiteHelpers.self
        let select = [
            q.coalescedExpression(["title", "name"], columns: columns, default: "NULL", alias: "title"),
            q.coalescedExpression(["model", "model_name", "model_id"], columns: columns, default: "NULL", alias: "model"),
            q.coalescedExpression(["started_at", "created_at"], columns: columns, default: "0", alias: "started_at"),
            q.coalescedExpression(["ended_at", "updated_at"], columns: columns, default: "0", alias: "ended_at"),
            q.expression("updated_at", columns: columns, default: "0", alias: "updated_at"),
            q.coalescedExpression(["input_tokens", "tokens_input", "prompt_tokens"], columns: columns, default: "0", alias: "input_tokens"),
            q.coalescedExpression(["output_tokens", "tokens_output", "completion_tokens"], columns: columns, default: "0", alias: "output_tokens"),
            q.coalescedExpression(["cache_read_tokens", "tokens_cache_read", "cache_read"], columns: columns, default: "0", alias: "cache_read_tokens"),
            q.coalescedExpression(["cache_write_tokens", "tokens_cache_write", "cache_write"], columns: columns, default: "0", alias: "cache_write_tokens"),
            q.expression("token_count", columns: columns, default: "0", alias: "token_count"),
            q.coalescedExpression(["cost", "cost_usd", "total_cost"], columns: columns, default: "NULL", alias: "cost"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM sessions WHERE \(q.quotedIdentifier(idColumn)) = ? LIMIT 1") else {
            return nil
        }
        try? statement.bind(sessionID, at: 1)
        guard (try? statement.step()) == true else { return nil }

        var usage = TokenUsage(
            inputTokens: q.columnInt(statement, 5),
            outputTokens: q.columnInt(statement, 6),
            cacheReadTokens: q.columnInt(statement, 7),
            cacheCreation5mTokens: q.columnInt(statement, 8),
            cacheCreation1hTokens: 0
        )
        if usage.total == 0 {
            usage.inputTokens = q.columnInt(statement, 9)
        }
        return SessionRow(
            title: statement.columnString(0)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            model: statement.columnString(1)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            startedAt: date(from: statement, index: 2),
            endedAt: date(from: statement, index: 3),
            updatedAt: date(from: statement, index: 4),
            usage: usage,
            cost: q.columnDouble(statement, 10)
        )
    }

    private func messageRows(connection: SQLiteConnection, sessionID: String) -> [SessionTranscriptMessage] {
        guard ProviderSQLiteHelpers.tableExists("messages", in: connection) else { return [] }
        let columns = ProviderSQLiteHelpers.columns(in: "messages", connection: connection)
        guard let sessionColumn = sessionIDColumn(in: columns) else { return [] }
        let q = ProviderSQLiteHelpers.self
        let select = [
            q.coalescedExpression(["id", "message_id"], columns: columns, default: "''", alias: "id"),
            q.expression("role", columns: columns, default: "''", alias: "role"),
            q.expression("content", columns: columns, default: "''", alias: "content"),
            q.coalescedExpression(["created_at", "timestamp", "time_created"], columns: columns, default: "0", alias: "created_at"),
            q.expression("tool_name", columns: columns, default: "NULL", alias: "tool_name"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM messages WHERE \(q.quotedIdentifier(sessionColumn)) = ? ORDER BY created_at, id") else {
            return []
        }
        try? statement.bind(sessionID, at: 1)
        var messages: [SessionTranscriptMessage] = []
        while (try? statement.step()) == true {
            let roleString = statement.columnString(1)?.lowercased() ?? ""
            let role: SessionTranscriptMessage.Role
            if roleString.contains("assistant") || roleString.contains("agent") {
                role = .assistant
            } else if roleString.contains("tool") {
                role = .tool
            } else if roleString.contains("system") {
                role = .system
            } else {
                role = .user
            }
            let content = statement.columnString(2)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !content.isEmpty else { continue }
            messages.append(SessionTranscriptMessage(
                id: "hermes-\(statement.columnString(0) ?? UUID().uuidString)",
                role: role,
                text: content,
                timestamp: date(from: statement, index: 3),
                model: nil
            ))
        }
        return messages
    }

    private func usageFromMessages(connection: SQLiteConnection, sessionID: String) -> TokenUsage {
        guard ProviderSQLiteHelpers.tableExists("messages", in: connection) else { return .zero }
        let columns = ProviderSQLiteHelpers.columns(in: "messages", connection: connection)
        guard let sessionColumn = sessionIDColumn(in: columns) else { return .zero }
        let q = ProviderSQLiteHelpers.self
        let select = [
            q.expression("role", columns: columns, default: "''", alias: "role"),
            q.coalescedExpression(["input_tokens", "tokens_input", "prompt_tokens"], columns: columns, default: "0", alias: "input_tokens"),
            q.coalescedExpression(["output_tokens", "tokens_output", "completion_tokens"], columns: columns, default: "0", alias: "output_tokens"),
            q.coalescedExpression(["cache_read_tokens", "tokens_cache_read", "cache_read"], columns: columns, default: "0", alias: "cache_read_tokens"),
            q.coalescedExpression(["cache_write_tokens", "tokens_cache_write", "cache_write"], columns: columns, default: "0", alias: "cache_write_tokens"),
            q.expression("token_count", columns: columns, default: "0", alias: "token_count"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM messages WHERE \(q.quotedIdentifier(sessionColumn)) = ?") else {
            return .zero
        }
        try? statement.bind(sessionID, at: 1)
        var usage = TokenUsage.zero
        while (try? statement.step()) == true {
            let explicit = TokenUsage(
                inputTokens: q.columnInt(statement, 1),
                outputTokens: q.columnInt(statement, 2),
                cacheReadTokens: q.columnInt(statement, 3),
                cacheCreation5mTokens: q.columnInt(statement, 4),
                cacheCreation1hTokens: 0
            )
            if explicit.total > 0 {
                usage += explicit
                continue
            }

            let tokenCount = q.columnInt(statement, 5)
            let role = statement.columnString(0)?.lowercased() ?? ""
            if role.contains("assistant") || role.contains("agent") {
                usage.outputTokens += tokenCount
            } else if role.contains("tool") || role.contains("system") {
                usage.cacheCreation5mTokens += tokenCount
            } else {
                usage.inputTokens += tokenCount
            }
        }
        return usage
    }

    private func sessionIDColumn(in columns: Set<String>) -> String? {
        ["session_id", "sessionId"].first(where: columns.contains)
    }

    private func date(from statement: SQLiteStatement, index: Int32) -> Date? {
        if let string = statement.columnString(index),
           let date = ProviderDateParser.date(from: string) {
            return date
        }
        return ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(index))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
