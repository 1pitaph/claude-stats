import Foundation

struct KiroSessionScanner: Sendable {
    let paths: KiroPaths

    func scan() -> [Session] {
        var byID: [String: Session] = [:]
        for session in fileSessions() + sqliteSessions() + archiveSessions() {
            byID[session.externalID] = byID[session.externalID] ?? session
        }
        return byID.values.sorted { $0.lastModified > $1.lastModified }
    }

    private func fileSessions() -> [Session] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: paths.cliSessionsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { metadataURL -> Session? in
                guard let data = try? Data(contentsOf: metadataURL),
                      let object = ProviderJSON.object(from: data) as? [String: Any] else {
                    return nil
                }
                let sessionID = ProviderJSON.string(object, keys: ["session_id", "conversation_id", "id"])
                    ?? metadataURL.deletingPathExtension().lastPathComponent
                let cwd = ProviderJSON.string(object, keys: ["cwd", "directory", "workspace", "key"])
                let title = ProviderJSON.string(object, keys: ["title", "summary"])
                let created = ProviderJSON.date(object, keys: ["created_at", "createdAt", "time_created"])
                let updated = ProviderJSON.date(object, keys: ["updated_at", "updatedAt", "time_updated"])
                let jsonl = metadataURL.deletingPathExtension().appendingPathExtension("jsonl")
                let snapshot = ProviderStorageHelpers.snapshot(for: [metadataURL, jsonl])
                return makeSession(
                    externalID: sessionID,
                    cwd: cwd,
                    title: title,
                    filePath: metadataURL.path,
                    lastModified: updated ?? created ?? snapshot.modified,
                    fileSize: snapshot.size
                )
            }
    }

    private func sqliteSessions() -> [Session] {
        var seenDatabasePaths: Set<String> = []
        return paths.databaseURLs.flatMap { databaseURL -> [Session] in
            guard FileManager.default.fileExists(atPath: databaseURL.path),
                  seenDatabasePaths.insert(databaseURL.path).inserted,
                  let connection = try? SQLiteConnection(url: databaseURL, readOnly: true) else {
                return []
            }
            return conversationsV2(databaseURL: databaseURL, connection: connection)
                + legacyConversations(databaseURL: databaseURL, connection: connection)
        }
    }

    private func conversationsV2(databaseURL: URL, connection: SQLiteConnection) -> [Session] {
        guard ProviderSQLiteHelpers.tableExists("conversations_v2", in: connection) else { return [] }
        let columns = ProviderSQLiteHelpers.columns(in: "conversations_v2", connection: connection)
        guard columns.contains("conversation_id") || columns.contains("id") else { return [] }
        let q = ProviderSQLiteHelpers.self
        let select = [
            q.coalescedExpression(["conversation_id", "id"], columns: columns, default: "''", alias: "conversation_id"),
            q.expression("key", columns: columns, default: "''", alias: "key"),
            q.expression("value", columns: columns, default: "''", alias: "value"),
            q.expression("created_at", columns: columns, default: "0", alias: "created_at"),
            q.expression("updated_at", columns: columns, default: "0", alias: "updated_at"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM conversations_v2") else { return [] }

        let snapshot = ProviderStorageHelpers.sqliteSnapshot(for: databaseURL)
        var sessions: [Session] = []
        while (try? statement.step()) == true {
            guard let id = statement.columnString(0), !id.isEmpty else { continue }
            let value = ProviderJSON.dictionary(from: statement.columnString(2))
            let cwd = ProviderJSON.string(value ?? [:], keys: ["cwd", "directory", "workspace", "key"])
                ?? statement.columnString(1)
            let title = ProviderJSON.string(value ?? [:], keys: ["title", "summary", "latest_summary"])
            let created = ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(3))
            let updated = ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(4))
            sessions.append(makeSession(
                externalID: id,
                cwd: cwd,
                title: title,
                filePath: databaseURL.path,
                lastModified: updated ?? created ?? snapshot.modified,
                fileSize: snapshot.size
            ))
        }
        return sessions
    }

    private func legacyConversations(databaseURL: URL, connection: SQLiteConnection) -> [Session] {
        guard ProviderSQLiteHelpers.tableExists("conversations", in: connection) else { return [] }
        let columns = ProviderSQLiteHelpers.columns(in: "conversations", connection: connection)
        let q = ProviderSQLiteHelpers.self
        let select = [
            q.coalescedExpression(["conversation_id", "id"], columns: columns, default: "''", alias: "conversation_id"),
            q.coalescedExpression(["key", "cwd", "directory"], columns: columns, default: "''", alias: "cwd"),
            q.expression("value", columns: columns, default: "''", alias: "value"),
            q.expression("created_at", columns: columns, default: "0", alias: "created_at"),
            q.expression("updated_at", columns: columns, default: "0", alias: "updated_at"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM conversations") else { return [] }
        let snapshot = ProviderStorageHelpers.sqliteSnapshot(for: databaseURL)
        var sessions: [Session] = []
        while (try? statement.step()) == true {
            let value = ProviderJSON.dictionary(from: statement.columnString(2))
            let id = statement.columnString(0)?.nilIfEmpty
                ?? ProviderJSON.string(value ?? [:], keys: ["conversation_id", "session_id", "id"])
            guard let id, !id.isEmpty else { continue }
            let cwd = ProviderJSON.string(value ?? [:], keys: ["cwd", "directory", "workspace", "key"])
                ?? statement.columnString(1)
            let title = ProviderJSON.string(value ?? [:], keys: ["title", "summary", "latest_summary"])
            let created = ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(3))
            let updated = ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(4))
            sessions.append(makeSession(
                externalID: id,
                cwd: cwd,
                title: title,
                filePath: databaseURL.path,
                lastModified: updated ?? created ?? snapshot.modified,
                fileSize: snapshot.size
            ))
        }
        return sessions
    }

    private func archiveSessions() -> [Session] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: paths.archiveDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let object = ProviderJSON.object(from: data) as? [String: Any] else {
                    return nil
                }
                let id = ProviderJSON.string(object, keys: ["session_id", "conversation_id", "id"])
                    ?? url.deletingPathExtension().lastPathComponent
                let cwd = ProviderJSON.string(object, keys: ["cwd", "directory", "workspace", "key"])
                let title = ProviderJSON.string(object, keys: ["title", "summary"])
                let snapshot = ProviderStorageHelpers.snapshot(for: [url])
                return makeSession(
                    externalID: id,
                    cwd: cwd,
                    title: title,
                    filePath: url.path,
                    lastModified: ProviderJSON.date(object, keys: ["updated_at", "updatedAt", "created_at"]) ?? snapshot.modified,
                    fileSize: snapshot.size
                )
            }
    }

    private func makeSession(externalID: String,
                             cwd: String?,
                             title: String?,
                             filePath: String,
                             lastModified: Date,
                             fileSize: Int64) -> Session {
        let projectName: String
        if let cwd, !cwd.isEmpty {
            projectName = (cwd as NSString).lastPathComponent
        } else {
            projectName = title?.nilIfEmpty ?? externalID
        }
        return Session(
            id: "kiro::\(externalID)",
            externalID: externalID,
            provider: .kiro,
            projectDirectoryName: projectName,
            filePath: filePath,
            cwd: cwd?.nilIfEmpty,
            lastModified: lastModified,
            fileSize: fileSize
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
