import Foundation

struct OpenCodeSessionScanner: Sendable {
    let paths: OpenCodePaths

    func scan() -> [Session] {
        paths.databaseURLs.flatMap(scan(databaseURL:))
            .sorted { $0.lastModified > $1.lastModified }
    }

    private func scan(databaseURL: URL) -> [Session] {
        guard let connection = try? SQLiteConnection(url: databaseURL, readOnly: true),
              ProviderSQLiteHelpers.tableExists("session", in: connection) else {
            return []
        }
        let columns = ProviderSQLiteHelpers.columns(in: "session", connection: connection)
        guard columns.contains("id") else { return [] }

        let q = ProviderSQLiteHelpers.self
        let select = [
            q.expression("id", columns: columns, alias: "id"),
            q.coalescedExpression(["directory", "path"], columns: columns, default: "''", alias: "cwd"),
            q.coalescedExpression(["title", "slug"], columns: columns, default: "''", alias: "title"),
            q.expression("time_created", columns: columns, default: "0", alias: "time_created"),
            q.expression("time_updated", columns: columns, default: "0", alias: "time_updated"),
        ].joined(separator: ", ")
        let archivedFilter = columns.contains("time_archived") ? " WHERE time_archived IS NULL" : ""
        let sql = "SELECT \(select) FROM session\(archivedFilter)"
        guard let statement = try? connection.prepare(sql) else { return [] }

        let snapshot = ProviderStorageHelpers.sqliteSnapshot(for: databaseURL)
        let databaseID = ProviderStorageHelpers.pathDigest(databaseURL.path)
        var sessions: [Session] = []
        while (try? statement.step()) == true {
            guard let id = statement.columnString(0), !id.isEmpty else { continue }
            let cwd = statement.columnString(1)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = statement.columnString(2)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let created = ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(3))
            let updated = ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(4))
            let modified = updated ?? created ?? snapshot.modified
            let projectName = projectDirectoryName(cwd: cwd, title: title, fallback: id)
            sessions.append(Session(
                id: "opencode::\(databaseID)::\(id)",
                externalID: id,
                provider: .opencode,
                projectDirectoryName: projectName,
                filePath: databaseURL.path,
                cwd: cwd?.isEmpty == false ? cwd : nil,
                lastModified: modified,
                fileSize: snapshot.size
            ))
        }
        return sessions
    }

    private func projectDirectoryName(cwd: String?, title: String?, fallback: String) -> String {
        if let cwd, !cwd.isEmpty {
            let name = (cwd as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }
        if let title, !title.isEmpty { return title }
        return fallback
    }
}
