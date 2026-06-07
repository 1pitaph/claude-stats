import Foundation

struct KiroTranscriptParser: Sendable {
    let pricing: ModelPricing

    func parse(_ session: Session) -> SessionStats? {
        let parsed: ParsedConversation?
        if isSQLitePath(session.filePath) {
            parsed = parseSQLite(session: session)
        } else {
            parsed = parseJSONBacked(session: session)
        }
        guard let parsed else { return nil }
        let messages = parsed.messages
        let usage = parsed.usage ?? estimatedUsage(messages: messages)
        let messageCount = messages.filter { $0.role == .user || $0.role == .assistant }.count
        guard usage.total > 0 || messageCount > 0 else { return nil }

        let model = parsed.model ?? "kiro"
        let modelUsage = ModelUsage(
            model: model,
            messageCount: max(1, messageCount),
            usage: usage,
            costEstimate: pricing.costEstimate(model: model, usage: usage)
        )
        let first = parsed.createdAt ?? messages.compactMap(\.timestamp).min()
        let last = parsed.updatedAt ?? messages.compactMap(\.timestamp).max() ?? session.lastModified
        let bucketStart = Calendar.current.dateInterval(of: .hour, for: last)?.start ?? last
        return SessionStats(
            title: parsed.title
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
        if isSQLitePath(session.filePath) {
            return parseSQLite(session: session)?.messages ?? []
        }
        return parseJSONBacked(session: session)?.messages ?? []
    }

    func executedCommands(for session: Session) -> [SessionCommandEvent] {
        let objects: [(Any, Date?)]
        if isSQLitePath(session.filePath) {
            objects = sqliteObjects(session: session)
        } else {
            objects = jsonBackedObjects(session: session)
        }
        var events: [SessionCommandEvent] = []
        for (object, timestamp) in objects {
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

    private struct ParsedConversation {
        var title: String?
        var model: String?
        var createdAt: Date?
        var updatedAt: Date?
        var usage: TokenUsage?
        var messages: [SessionTranscriptMessage]
    }

    private func parseJSONBacked(session: Session) -> ParsedConversation? {
        let url = URL(fileURLWithPath: session.filePath)
        guard let root = (try? Data(contentsOf: url)).flatMap(ProviderJSON.object(from:)) else { return nil }
        let rootDictionary = root as? [String: Any] ?? [:]
        let jsonlURL = url.deletingPathExtension().appendingPathExtension("jsonl")
        let objects = FileManager.default.fileExists(atPath: jsonlURL.path)
            ? jsonlObjects(url: jsonlURL)
            : conversationObjects(from: root)
        let messages = messages(from: objects, providerPrefix: "kiro")
        let usage = exactUsage(from: [root] + objects.map(\.0))
        return ParsedConversation(
            title: ProviderJSON.string(rootDictionary, keys: ["title", "summary", "latest_summary"]),
            model: recursiveString(in: root, keys: ["model", "model_id", "modelId", "model_name"]),
            createdAt: ProviderJSON.date(rootDictionary, keys: ["created_at", "createdAt", "time_created"]),
            updatedAt: ProviderJSON.date(rootDictionary, keys: ["updated_at", "updatedAt", "time_updated"]),
            usage: usage,
            messages: messages
        )
    }

    private func parseSQLite(session: Session) -> ParsedConversation? {
        guard let row = sqliteRow(session: session) else { return nil }
        let object = ProviderJSON.object(from: row.value) ?? [:]
        let nestedObjects = conversationObjects(from: object)
        let messages = messages(from: nestedObjects, providerPrefix: "kiro")
        let usage = exactUsage(from: [object] + nestedObjects.map(\.0))
        return ParsedConversation(
            title: recursiveString(in: object, keys: ["title", "summary", "latest_summary"]),
            model: recursiveString(in: object, keys: ["model", "model_id", "modelId", "model_name"]),
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            usage: usage,
            messages: messages
        )
    }

    private struct SQLiteRow {
        let value: String
        let createdAt: Date?
        let updatedAt: Date?
    }

    private func sqliteRow(session: Session) -> SQLiteRow? {
        let databaseURL = URL(fileURLWithPath: session.filePath)
        guard let connection = try? SQLiteConnection(url: databaseURL, readOnly: true) else { return nil }
        if let row = sqliteRow(table: "conversations_v2", connection: connection, sessionID: session.externalID) {
            return row
        }
        return sqliteRow(table: "conversations", connection: connection, sessionID: session.externalID)
    }

    private func sqliteRow(table: String, connection: SQLiteConnection, sessionID: String) -> SQLiteRow? {
        guard ProviderSQLiteHelpers.tableExists(table, in: connection) else { return nil }
        let columns = ProviderSQLiteHelpers.columns(in: table, connection: connection)
        guard columns.contains("value") else { return nil }
        let q = ProviderSQLiteHelpers.self
        let idExpression = q.coalescedExpression(["conversation_id", "id"], columns: columns, default: "''", alias: "conversation_id")
        let select = [
            idExpression,
            q.expression("value", columns: columns, default: "''", alias: "value"),
            q.expression("created_at", columns: columns, default: "0", alias: "created_at"),
            q.expression("updated_at", columns: columns, default: "0", alias: "updated_at"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM \(q.quotedIdentifier(table))") else { return nil }
        while (try? statement.step()) == true {
            let rawID = statement.columnString(0)
            let value = statement.columnString(1) ?? ""
            let object = ProviderJSON.object(from: value)
            let nestedID = object.flatMap { recursiveString(in: $0, keys: ["conversation_id", "session_id", "id"]) }
            guard rawID == sessionID || nestedID == sessionID else { continue }
            return SQLiteRow(
                value: value,
                createdAt: ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(2)),
                updatedAt: ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(3))
            )
        }
        return nil
    }

    private func sqliteObjects(session: Session) -> [(Any, Date?)] {
        guard let row = sqliteRow(session: session),
              let object = ProviderJSON.object(from: row.value) else {
            return []
        }
        return conversationObjects(from: object)
    }

    private func jsonBackedObjects(session: Session) -> [(Any, Date?)] {
        let url = URL(fileURLWithPath: session.filePath)
        let jsonlURL = url.deletingPathExtension().appendingPathExtension("jsonl")
        if FileManager.default.fileExists(atPath: jsonlURL.path) {
            return jsonlObjects(url: jsonlURL)
        }
        guard let object = (try? Data(contentsOf: url)).flatMap(ProviderJSON.object(from:)) else { return [] }
        return conversationObjects(from: object)
    }

    private func jsonlObjects(url: URL) -> [(Any, Date?)] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return data
            .split(separator: 0x0A, omittingEmptySubsequences: true)
            .compactMap { line -> (Any, Date?)? in
                let lineData = Data(line)
                guard let object = ProviderJSON.object(from: lineData) else { return nil }
                return (object, timestamp(from: object))
            }
    }

    private func conversationObjects(from object: Any) -> [(Any, Date?)] {
        if let dictionary = object as? [String: Any] {
            for key in ["transcript", "history", "messages", "conversation", "turns"] {
                if let array = dictionary[key] as? [Any] {
                    return array.map { ($0, timestamp(from: $0)) }
                }
            }
            if let data = dictionary["data"] {
                return conversationObjects(from: data)
            }
        }
        if let array = object as? [Any] {
            return array.map { ($0, timestamp(from: $0)) }
        }
        return [(object, timestamp(from: object))]
    }

    private func messages(from objects: [(Any, Date?)], providerPrefix: String) -> [SessionTranscriptMessage] {
        objects.enumerated().compactMap { index, pair in
            let object = normalizedMessageObject(pair.0)
            let role = ProviderTranscriptExtraction.role(from: object)
                ?? roleFromKind(pair.0)
            guard let role,
                  let text = ProviderTranscriptExtraction.text(from: object) else {
                return nil
            }
            return SessionTranscriptMessage(
                id: "\(providerPrefix)-\(index)",
                role: role,
                text: text,
                timestamp: pair.1 ?? timestamp(from: object),
                model: recursiveString(in: object, keys: ["model", "model_id", "modelId"])
            )
        }
    }

    private func normalizedMessageObject(_ object: Any) -> Any {
        if let dictionary = object as? [String: Any],
           let data = dictionary["data"] as? [String: Any] {
            var merged = data
            for key in ["kind", "type", "role", "timestamp", "created_at", "updated_at"] where merged[key] == nil {
                merged[key] = dictionary[key]
            }
            return merged
        }
        return object
    }

    private func roleFromKind(_ object: Any) -> SessionTranscriptMessage.Role? {
        guard let dictionary = object as? [String: Any],
              let kind = ProviderJSON.string(dictionary, keys: ["kind", "type"])?.lowercased() else {
            return nil
        }
        if kind.contains("prompt") || kind.contains("user") { return .user }
        if kind.contains("assistant") { return .assistant }
        if kind.contains("tool") { return .tool }
        return nil
    }

    private func exactUsage(from objects: [Any]) -> TokenUsage? {
        var usage = TokenUsage.zero
        for object in objects {
            if let next = ProviderTranscriptExtraction.usage(from: object) {
                usage += next
            }
        }
        return usage.total > 0 ? usage : nil
    }

    private func estimatedUsage(messages: [SessionTranscriptMessage]) -> TokenUsage {
        var usage = TokenUsage.zero
        var contextTokens = 0
        for message in messages.sorted(by: {
            ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
        }) {
            let tokens = ProviderTranscriptExtraction.estimatedTokens(for: message.text)
            switch message.role {
            case .assistant:
                usage.cacheReadTokens += contextTokens
                usage.outputTokens += tokens
                contextTokens += tokens
            case .user, .system, .tool:
                usage.cacheCreation5mTokens += tokens
                contextTokens += tokens
            }
        }
        return usage
    }

    private func timestamp(from object: Any) -> Date? {
        guard let dictionary = object as? [String: Any] else { return nil }
        if let date = ProviderJSON.date(dictionary, keys: [
            "timestamp", "created_at", "createdAt", "updated_at", "updatedAt",
            "time_created", "time_updated",
        ]) {
            return date
        }
        if let data = dictionary["data"] as? [String: Any] {
            return ProviderJSON.date(data, keys: ["timestamp", "created_at", "createdAt", "updated_at", "updatedAt"])
        }
        return nil
    }

    private func recursiveString(in value: Any, keys: [String]) -> String? {
        if let dictionary = value as? [String: Any] {
            if let direct = ProviderJSON.string(dictionary, keys: keys) { return direct }
            for key in ["model_info", "modelInfo", "metadata", "session_state", "data"] {
                if let child = dictionary[key],
                   let found = recursiveString(in: child, keys: keys) {
                    return found
                }
            }
        }
        return nil
    }

    private func isSQLitePath(_ path: String) -> Bool {
        path.hasSuffix(".sqlite3") || path.hasSuffix(".db")
    }
}
