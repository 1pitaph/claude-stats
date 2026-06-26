import Foundation

/// Discovers ZCode CLI sessions by reading rows out of
/// `~/.zcode/cli/db/db.sqlite`. Each row in the `session` table becomes one
/// ``Session``; the session id (`sess_…`) round-trips as `externalID` and is
/// used by the parser to look up usage and message rows.
///
/// When the database is missing (fresh install or a different ZCode version),
/// the scanner falls back to enumerating rollout JSONL files under
/// `~/.zcode/cli/rollout/` via ``ZCodeRolloutParser``.
struct ZCodeSessionScanner: Sendable {
    let paths: ZCodePaths

    func scan() -> [Session] {
        var sessions = scanDatabase()
        if sessions.isEmpty {
            sessions = ZCodeRolloutParser(paths: paths).discoverSessions()
        }
        return sessions.sorted { $0.lastModified > $1.lastModified }
    }

    private func scanDatabase() -> [Session] {
        let databaseURL = paths.databaseURL
        guard FileManager.default.fileExists(atPath: databaseURL.path),
              let connection = try? SQLiteConnection(url: databaseURL, readOnly: true),
              ProviderSQLiteHelpers.tableExists("session", in: connection) else {
            return []
        }
        let columns = ProviderSQLiteHelpers.columns(in: "session", connection: connection)
        guard columns.contains("id") else { return [] }
        let q = ProviderSQLiteHelpers.self
        let select = [
            q.expression("id", columns: columns, default: "''", alias: "session_id"),
            q.coalescedExpression(["title", "slug"], columns: columns, default: "''", alias: "title"),
            q.coalescedExpression(["directory", "path"], columns: columns, default: "''", alias: "directory"),
            q.coalescedExpression(["time_updated", "time_created"], columns: columns, default: "0", alias: "updated_at"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM session ORDER BY updated_at DESC") else {
            return []
        }

        let snapshot = ProviderStorageHelpers.sqliteSnapshot(for: databaseURL)
        let databaseID = ProviderStorageHelpers.pathDigest(databaseURL.path)
        var sessions: [Session] = []
        while (try? statement.step()) == true {
            guard let id = statement.columnString(0), !id.isEmpty else { continue }
            let title = statement.columnString(1)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let directory = statement.columnString(2)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let modified = ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(3))
                ?? snapshot.modified
            sessions.append(Session(
                id: "zcode::\(databaseID)::\(id)",
                externalID: id,
                provider: .zcode,
                projectDirectoryName: projectName(directory: directory, title: title, fallback: id),
                filePath: databaseURL.path,
                cwd: directory?.isEmpty == false ? directory : nil,
                lastModified: modified,
                fileSize: snapshot.size
            ))
        }
        return sessions
    }

    private func projectName(directory: String?, title: String?, fallback: String) -> String {
        if let directory, !directory.isEmpty {
            let name = (directory as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }
        if let title, !title.isEmpty { return title }
        return fallback
    }
}
