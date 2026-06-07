import Foundation

struct HermesSessionScanner: Sendable {
    let paths: HermesPaths

    func scan() -> [Session] {
        paths.databaseURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .flatMap(scan(databaseURL:))
            .sorted { $0.lastModified > $1.lastModified }
    }

    private func scan(databaseURL: URL) -> [Session] {
        guard let connection = try? SQLiteConnection(url: databaseURL, readOnly: true),
              ProviderSQLiteHelpers.tableExists("sessions", in: connection) else {
            return []
        }
        let columns = ProviderSQLiteHelpers.columns(in: "sessions", connection: connection)
        let q = ProviderSQLiteHelpers.self
        let idCandidates = ["id", "session_id"]
        guard idCandidates.contains(where: columns.contains) else { return [] }
        let select = [
            q.coalescedExpression(idCandidates, columns: columns, default: "''", alias: "session_id"),
            q.coalescedExpression(["title", "name"], columns: columns, default: "''", alias: "title"),
            q.coalescedExpression(["cwd", "directory", "workspace_path", "working_directory"], columns: columns, default: "''", alias: "cwd"),
            q.coalescedExpression(["updated_at", "ended_at", "created_at", "started_at"], columns: columns, default: "0", alias: "updated_at"),
        ].joined(separator: ", ")
        guard let statement = try? connection.prepare("SELECT \(select) FROM sessions") else { return [] }

        let snapshot = ProviderStorageHelpers.sqliteSnapshot(for: databaseURL)
        let databaseID = ProviderStorageHelpers.pathDigest(databaseURL.path)
        var sessions: [Session] = []
        while (try? statement.step()) == true {
            guard let id = statement.columnString(0), !id.isEmpty else { continue }
            let title = statement.columnString(1)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cwd = statement.columnString(2)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let modified = ProviderDateParser.date(from: statement.columnString(3) ?? "")
                ?? ProviderDateParser.date(fromSQLiteNumber: statement.columnInt64(3))
                ?? snapshot.modified
            sessions.append(Session(
                id: "hermes::\(databaseID)::\(id)",
                externalID: id,
                provider: .hermes,
                projectDirectoryName: projectName(cwd: cwd, title: title, fallback: id),
                filePath: databaseURL.path,
                cwd: cwd?.isEmpty == false ? cwd : nil,
                lastModified: modified,
                fileSize: snapshot.size
            ))
        }
        return sessions
    }

    private func projectName(cwd: String?, title: String?, fallback: String) -> String {
        if let cwd, !cwd.isEmpty {
            let name = (cwd as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }
        if let title, !title.isEmpty { return title }
        return fallback
    }
}
