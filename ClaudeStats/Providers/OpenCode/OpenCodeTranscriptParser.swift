import Foundation

struct OpenCodeTranscriptParser: Sendable {
    let pricing: ModelPricing

    func parse(_ session: Session) -> SessionStats? {
        let databaseURL = URL(fileURLWithPath: session.filePath)
        guard let row = sessionRow(databaseURL: databaseURL, sessionID: session.externalID) else { return nil }

        let usage = row.usage
        let messages = messages(for: session)
        let messageCount = max(row.messageCount, messages.filter { $0.role == .user || $0.role == .assistant }.count)
        guard usage.total > 0 || messageCount > 0 else { return nil }

        let model = row.model ?? "opencode"
        let cost = row.cost.map { CostEstimate(standardAPI: $0) }
            ?? pricing.costEstimate(model: model, usage: usage)
        let usageModel = ModelUsage(model: model, messageCount: max(1, messageCount), usage: usage, costEstimate: cost)
        let activity = row.updatedAt ?? row.createdAt ?? session.lastModified
        let bucketStart = Calendar.current.dateInterval(of: .hour, for: activity)?.start ?? activity
        let timeline = usage.total > 0 ? [ModelBucket(model: model, start: bucketStart, usage: usage)] : []
        let messageTimestamps = messages.compactMap(\.timestamp)

        return SessionStats(
            title: row.title ?? messages.first(where: { $0.role == .user }).flatMap { TitleSanitizer.sanitize($0.text) } ?? session.projectDisplayName,
            messageCount: messageCount,
            firstActivity: row.createdAt ?? messageTimestamps.min(),
            lastActivity: row.updatedAt ?? messageTimestamps.max() ?? activity,
            models: usage.total > 0 ? [usageModel] : [],
            timeline: timeline,
            activityIntervals: TranscriptParser.coalesceBursts(messageTimestamps)
        )
    }

    func messages(for session: Session) -> [SessionTranscriptMessage] {
        let databaseURL = URL(fileURLWithPath: session.filePath)
        guard let connection = try? SQLiteConnection(url: databaseURL, readOnly: true) else { return [] }
        var rows: [SessionTranscriptMessage] = []

        if ProviderSQLiteHelpers.tableExists("message", in: connection) {
            rows += messageRows(connection: connection, sessionID: session.externalID)
        }
        if rows.isEmpty, ProviderSQLiteHelpers.tableExists("session_message", in: connection) {
            rows += sessionMessageRows(connection: connection, sessionID: session.externalID)
        }
        return rows.sorted {
            ($0.timestamp ?? .distantPast) != ($1.timestamp ?? .distantPast)
                ? ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
                : $0.id < $1.id
        }
    }

    func executedCommands(for session: Session) -> [SessionCommandEvent] {
        let databaseURL = URL(fileURLWithPath: session.filePath)
        guard let connection = try? SQLiteConnection(url: databaseURL, readOnly: true) else { return [] }
        var events: [SessionCommandEvent] = []

        if ProviderSQLiteHelpers.tableExists("part", in: connection) {
            events += commandEvents(table: "part", connection: connection, sessionID: session.externalID)
        }
        if ProviderSQLiteHelpers.tableExists("message", in: connection) {
            events += commandEvents(table: "message", connection: connection, sessionID: session.externalID)
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
        let createdAt: Date?
        let updatedAt: Date?
        let usage: TokenUsage
        let cost: Double?
        let messageCount: Int
    }

    private func sessionRow(databaseURL: URL, sessionID: String) -> SessionRow? {
        guard let connection = try? SQLiteConnection(url: databaseURL, readOnly: true),
              ProviderSQLiteHelpers.tableExists("session", in: connection) else {
            return nil
        }
        let columns = ProviderSQLiteHelpers.columns(in: "session", connection: connection)
        guard columns.contains("id") else { return nil }
        let q = ProviderSQLiteHelpers.self
        let select = [
            q.coalescedExpression(["title", "slug"], columns: columns, default: "NULL", alias: "title"),
            q.expression("model", columns: columns, default: "NULL", alias: "model"),
            q.expression("time_created", columns: columns, default: "0", alias: "time_created"),
            q.expression("time_updated", columns: columns, default: "0", alias: "time_updated"),
            q.expression("tokens_input", columns: columns, default: "0", alias: "tokens_input"),
            q.expression("tokens_output", columns: columns, default: "0", alias: "tokens_output"),
            q.expression("tokens_reasoning", columns: columns, default: "0", alias: "tokens_reasoning"),
            q.expression("tokens_cache_read", columns: columns, default: "0", alias: "tokens_cache_read"),
            q.expression("tokens_cache_write", columns: columns, default: "0", alias: "tokens_cache_write"),
            q.expression("cost", columns: columns, default: "NULL", alias: "cost"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM session WHERE id = ? LIMIT 1") else {
            return nil
        }
        try? statement.bind(sessionID, at: 1)
        guard (try? statement.step()) == true else { return nil }

        let usage = TokenUsage(
            inputTokens: q.columnInt(statement, 4),
            outputTokens: q.columnInt(statement, 5) + q.columnInt(statement, 6),
            cacheReadTokens: q.columnInt(statement, 7),
            cacheCreation5mTokens: q.columnInt(statement, 8),
            cacheCreation1hTokens: 0
        )
        return SessionRow(
            title: statement.columnString(0)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            model: statement.columnString(1)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(2)),
            updatedAt: ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(3)),
            usage: usage,
            cost: q.columnDouble(statement, 9),
            messageCount: messageCount(connection: connection, sessionID: sessionID)
        )
    }

    private func messageRows(connection: SQLiteConnection, sessionID: String) -> [SessionTranscriptMessage] {
        let columns = ProviderSQLiteHelpers.columns(in: "message", connection: connection)
        guard columns.contains("session_id"), columns.contains("data") else { return [] }
        let q = ProviderSQLiteHelpers.self
        let select = [
            q.expression("id", columns: columns, default: "''", alias: "id"),
            q.expression("time_created", columns: columns, default: "0", alias: "time_created"),
            q.expression("data", columns: columns, default: "''", alias: "data"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM message WHERE session_id = ? ORDER BY time_created, id") else {
            return []
        }
        try? statement.bind(sessionID, at: 1)
        var messages: [SessionTranscriptMessage] = []
        while (try? statement.step()) == true {
            guard let data = statement.columnString(2),
                  let object = ProviderJSON.object(from: data) else { continue }
            let role = ProviderTranscriptExtraction.role(from: object) ?? .assistant
            guard let text = ProviderTranscriptExtraction.text(from: object) else { continue }
            messages.append(SessionTranscriptMessage(
                id: "opencode-\(statement.columnString(0) ?? UUID().uuidString)",
                role: role,
                text: text,
                timestamp: ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(1)),
                model: nil
            ))
        }
        return messages
    }

    private func sessionMessageRows(connection: SQLiteConnection, sessionID: String) -> [SessionTranscriptMessage] {
        let columns = ProviderSQLiteHelpers.columns(in: "session_message", connection: connection)
        guard columns.contains("session_id"), columns.contains("data") else { return [] }
        let q = ProviderSQLiteHelpers.self
        let select = [
            q.expression("id", columns: columns, default: "''", alias: "id"),
            q.expression("type", columns: columns, default: "''", alias: "type"),
            q.expression("time_created", columns: columns, default: "0", alias: "time_created"),
            q.expression("data", columns: columns, default: "''", alias: "data"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM session_message WHERE session_id = ? ORDER BY time_created, id") else {
            return []
        }
        try? statement.bind(sessionID, at: 1)
        var messages: [SessionTranscriptMessage] = []
        while (try? statement.step()) == true {
            let rawType = statement.columnString(1)?.lowercased()
            let object = ProviderJSON.object(from: statement.columnString(3) ?? "") ?? [:]
            let role = ProviderTranscriptExtraction.role(from: object)
                ?? (rawType?.contains("user") == true ? .user : .assistant)
            guard let text = ProviderTranscriptExtraction.text(from: object) else { continue }
            messages.append(SessionTranscriptMessage(
                id: "opencode-\(statement.columnString(0) ?? UUID().uuidString)",
                role: role,
                text: text,
                timestamp: ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(2)),
                model: nil
            ))
        }
        return messages
    }

    private func commandEvents(table: String, connection: SQLiteConnection, sessionID: String) -> [SessionCommandEvent] {
        let columns = ProviderSQLiteHelpers.columns(in: table, connection: connection)
        guard columns.contains("session_id"), columns.contains("data") else { return [] }
        let q = ProviderSQLiteHelpers.self
        let select = [
            q.expression("time_created", columns: columns, default: "0", alias: "time_created"),
            q.expression("data", columns: columns, default: "''", alias: "data"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM \(q.quotedIdentifier(table)) WHERE session_id = ? ORDER BY time_created") else {
            return []
        }
        try? statement.bind(sessionID, at: 1)
        var events: [SessionCommandEvent] = []
        while (try? statement.step()) == true {
            guard let object = ProviderJSON.object(from: statement.columnString(1)) else { continue }
            let timestamp = ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(0))
            events += ProviderTranscriptExtraction.commands(from: object)
                .map { SessionCommandEvent(command: $0, timestamp: timestamp) }
        }
        return events
    }

    private func messageCount(connection: SQLiteConnection, sessionID: String) -> Int {
        for table in ["message", "session_message"] where ProviderSQLiteHelpers.tableExists(table, in: connection) {
            let columns = ProviderSQLiteHelpers.columns(in: table, connection: connection)
            guard columns.contains("session_id"),
                  let statement = try? connection.prepare("SELECT COUNT(*) FROM \(ProviderSQLiteHelpers.quotedIdentifier(table)) WHERE session_id = ?") else {
                continue
            }
            try? statement.bind(sessionID, at: 1)
            if (try? statement.step()) == true {
                return statement.columnInt(0)
            }
        }
        return 0
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
