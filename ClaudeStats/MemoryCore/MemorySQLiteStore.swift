import CryptoKit
import Foundation
import SQLite3

enum MemorySQLiteError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case executeFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): "Memory SQLite open failed: \(message)"
        case .prepareFailed(let message): "Memory SQLite prepare failed: \(message)"
        case .stepFailed(let message): "Memory SQLite step failed: \(message)"
        case .bindFailed(let message): "Memory SQLite bind failed: \(message)"
        case .executeFailed(let message): "Memory SQLite execute failed: \(message)"
        }
    }
}

final class MemorySQLiteConnection {
    private var db: OpaquePointer?

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw MemorySQLiteError.openFailed(message)
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        guard result == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(error)
            throw MemorySQLiteError.executeFailed(message)
        }
    }

    func prepare(_ sql: String) throws -> MemorySQLiteStatement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MemorySQLiteError.prepareFailed(lastErrorMessage)
        }
        return MemorySQLiteStatement(connection: self, statement: statement)
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var lastErrorMessage: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }
}

final class MemorySQLiteStatement {
    private unowned let connection: MemorySQLiteConnection
    private var statement: OpaquePointer?

    init(connection: MemorySQLiteConnection, statement: OpaquePointer?) {
        self.connection = connection
        self.statement = statement
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ value: String?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, MemorySQLiteStatement.transient)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw MemorySQLiteError.bindFailed(connection.lastErrorMessage) }
    }

    func bind(_ value: Int, at index: Int32) throws {
        let result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        guard result == SQLITE_OK else { throw MemorySQLiteError.bindFailed(connection.lastErrorMessage) }
    }

    func bind(_ value: Double?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_double(statement, index, value)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw MemorySQLiteError.bindFailed(connection.lastErrorMessage) }
    }

    func bind(_ date: Date?, at index: Int32) throws {
        try bind(date?.timeIntervalSinceReferenceDate, at: index)
    }

    func step() throws -> Bool {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw MemorySQLiteError.stepFailed(connection.lastErrorMessage)
        }
    }

    func finish() throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw MemorySQLiteError.stepFailed(connection.lastErrorMessage)
        }
    }

    func reset() {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    func columnString(_ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    func columnInt(_ index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    func columnDouble(_ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    func columnDate(_ index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSinceReferenceDate: columnDouble(index))
    }

    func columnIsNull(_ index: Int32) -> Bool {
        sqlite3_column_type(statement, index) == SQLITE_NULL
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

actor MemorySQLiteStore {
    private static let schemaVersion = 1

    private let url: URL
    private var connection: MemorySQLiteConnection?

    init(url: URL = MemoryPaths.databaseURL()) {
        self.url = url
    }

    func upsertSources(_ sources: [MemorySource]) throws {
        let connection = try openConnection()
        let statement = try connection.prepare(
            """
            INSERT INTO sources (
                id, kind, provider, title, path, is_enabled, is_default,
                created_at, updated_at, last_indexed_at, last_error
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                kind = excluded.kind,
                provider = excluded.provider,
                title = excluded.title,
                path = excluded.path,
                is_enabled = excluded.is_enabled,
                is_default = excluded.is_default,
                updated_at = excluded.updated_at,
                last_indexed_at = excluded.last_indexed_at,
                last_error = excluded.last_error
            """
        )
        for source in sources {
            try statement.bind(source.id, at: 1)
            try statement.bind(source.kind.rawValue, at: 2)
            try statement.bind(source.providerRaw, at: 3)
            try statement.bind(source.title, at: 4)
            try statement.bind(source.path, at: 5)
            try statement.bind(source.isEnabled ? 1 : 0, at: 6)
            try statement.bind(source.isDefault ? 1 : 0, at: 7)
            try statement.bind(source.createdAt, at: 8)
            try statement.bind(source.updatedAt, at: 9)
            try statement.bind(source.lastIndexedAt, at: 10)
            try statement.bind(source.lastError, at: 11)
            try statement.finish()
            statement.reset()
        }
    }

    func sources() throws -> [MemorySource] {
        let connection = try openConnection()
        let statement = try connection.prepare(
            """
            SELECT id, kind, provider, title, path, is_enabled, is_default,
                   created_at, updated_at, last_indexed_at, last_error
            FROM sources
            ORDER BY is_default DESC, kind, provider, title
            """
        )
        var rows: [MemorySource] = []
        while try statement.step() {
            if let source = readSource(from: statement) {
                rows.append(source)
            }
        }
        return rows
    }

    func deleteSource(id: String) throws {
        let connection = try openConnection()
        try connection.transaction {
            let blockFTS = try connection.prepare("DELETE FROM blocks_fts WHERE source_id = ?")
            try blockFTS.bind(id, at: 1)
            try blockFTS.finish()

            let blocks = try connection.prepare("DELETE FROM blocks WHERE source_id = ?")
            try blocks.bind(id, at: 1)
            try blocks.finish()

            let records = try connection.prepare("DELETE FROM records WHERE source_id = ?")
            try records.bind(id, at: 1)
            try records.finish()

            let sources = try connection.prepare("DELETE FROM sources WHERE id = ?")
            try sources.bind(id, at: 1)
            try sources.finish()
        }
    }

    func upsertRecord(_ record: MemoryRecord, blocks: [MemoryBlock]) throws {
        let connection = try openConnection()
        try connection.transaction {
            try deleteBlocks(recordID: record.id, connection: connection)
            try insertRecord(record, connection: connection)
            try insertBlocks(blocks, record: record, connection: connection)
        }
    }

    func pruneRecords(sourceID: String, keeping liveIDs: Set<String>) throws {
        let connection = try openConnection()
        let statement = try connection.prepare("SELECT id FROM records WHERE source_id = ?")
        try statement.bind(sourceID, at: 1)
        var staleIDs: [String] = []
        while try statement.step() {
            guard let id = statement.columnString(0), !liveIDs.contains(id) else { continue }
            staleIDs.append(id)
        }
        guard !staleIDs.isEmpty else { return }

        try connection.transaction {
            for id in staleIDs {
                try deleteRecord(id: id, connection: connection)
            }
        }
    }

    func records(kind: MemoryRecordKind? = nil, sourceID: String? = nil, limit: Int = 250) throws -> [MemoryRecord] {
        let connection = try openConnection()
        let sql: String
        switch (kind, sourceID) {
        case (.some, .some):
            sql = "SELECT \(recordColumns) FROM records WHERE kind = ? AND source_id = ? ORDER BY COALESCE(started_at, updated_at, created_at) DESC LIMIT ?"
        case (.some, .none):
            sql = "SELECT \(recordColumns) FROM records WHERE kind = ? ORDER BY COALESCE(started_at, updated_at, created_at) DESC LIMIT ?"
        case (.none, .some):
            sql = "SELECT \(recordColumns) FROM records WHERE source_id = ? ORDER BY COALESCE(started_at, updated_at, created_at) DESC LIMIT ?"
        case (.none, .none):
            sql = "SELECT \(recordColumns) FROM records ORDER BY COALESCE(started_at, updated_at, created_at) DESC LIMIT ?"
        }
        let statement = try connection.prepare(sql)
        switch (kind, sourceID) {
        case (.some(let kind), .some(let sourceID)):
            try statement.bind(kind.rawValue, at: 1)
            try statement.bind(sourceID, at: 2)
            try statement.bind(limit, at: 3)
        case (.some(let kind), .none):
            try statement.bind(kind.rawValue, at: 1)
            try statement.bind(limit, at: 2)
        case (.none, .some(let sourceID)):
            try statement.bind(sourceID, at: 1)
            try statement.bind(limit, at: 2)
        case (.none, .none):
            try statement.bind(limit, at: 1)
        }
        var rows: [MemoryRecord] = []
        while try statement.step() {
            if let record = readRecord(from: statement) {
                rows.append(record)
            }
        }
        return rows
    }

    func blocks(recordID: String, limit: Int = 500) throws -> [MemoryBlock] {
        let connection = try openConnection()
        let statement = try connection.prepare(
            """
            SELECT \(blockColumns)
            FROM blocks
            WHERE record_id = ?
            ORDER BY ordinal ASC
            LIMIT ?
            """
        )
        try statement.bind(recordID, at: 1)
        try statement.bind(limit, at: 2)
        var rows: [MemoryBlock] = []
        while try statement.step() {
            if let block = readBlock(from: statement) {
                rows.append(block)
            }
        }
        return rows
    }

    func firstBlock(recordID: String, containing excerpt: String? = nil) throws -> MemoryBlock? {
        let candidates = try blocks(recordID: recordID, limit: 100)
        let needle = excerpt?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let needle, !needle.isEmpty,
           let match = candidates.first(where: { $0.text.lowercased().contains(needle) || $0.excerpt.lowercased().contains(needle) }) {
            return match
        }
        return candidates.first
    }

    func record(id: String) throws -> MemoryRecord? {
        let connection = try openConnection()
        let statement = try connection.prepare("SELECT \(recordColumns) FROM records WHERE id = ?")
        try statement.bind(id, at: 1)
        guard try statement.step() else { return nil }
        return readRecord(from: statement)
    }

    func search(query: String, limit: Int = 80) throws -> [MemorySearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        do {
            return try ftsSearch(query: trimmed, limit: limit)
        } catch {
            return try likeSearch(query: trimmed, limit: limit)
        }
    }

    func deleteAll() throws {
        let connection = try openConnection()
        try connection.transaction {
            try connection.execute("DELETE FROM blocks_fts")
            try connection.execute("DELETE FROM blocks")
            try connection.execute("DELETE FROM records")
        }
    }

    func counts() throws -> MemoryCounts {
        let connection = try openConnection()
        let sources = try count(sql: "SELECT COUNT(*) FROM sources", connection: connection)
        let records = try count(sql: "SELECT COUNT(*) FROM records", connection: connection)
        let blocks = try count(sql: "SELECT COUNT(*) FROM blocks", connection: connection)
        let terminal = try count(sql: "SELECT COUNT(*) FROM records WHERE kind IN ('terminalRun', 'terminalPipe', 'shellMetadata')", connection: connection)
        return MemoryCounts(sourceCount: sources, recordCount: records, blockCount: blocks, terminalRecordCount: terminal)
    }

    static func textHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Search

    private func ftsSearch(query: String, limit: Int) throws -> [MemorySearchResult] {
        let connection = try openConnection()
        let sourcesByID = Dictionary(uniqueKeysWithValues: try sources().map { ($0.id, $0) })
        let match = ftsQuery(from: query)
        let statement = try connection.prepare(
            """
            SELECT b.id, b.record_id, b.source_id, b.ordinal, b.role, b.text, b.excerpt,
                   b.timestamp, b.model, b.ref, b.text_hash, b.created_at,
                   r.id, r.source_id, r.kind, r.provider, r.external_id, r.title, r.subtitle,
                   r.project_path, r.file_path, r.command, r.cwd, r.exit_code, r.started_at,
                   r.ended_at, r.created_at, r.updated_at, r.metadata_json,
                   bm25(blocks_fts) AS rank,
                   snippet(blocks_fts, 4, '', '', '...', 18) AS snippet
            FROM blocks_fts
            JOIN blocks b ON b.id = blocks_fts.block_id
            JOIN records r ON r.id = b.record_id
            WHERE blocks_fts MATCH ?
            ORDER BY rank ASC
            LIMIT ?
            """
        )
        try statement.bind(match, at: 1)
        try statement.bind(limit, at: 2)
        var results: [MemorySearchResult] = []
        while try statement.step() {
            guard let block = readBlock(from: statement, offset: 0),
                  let record = readRecord(from: statement, offset: 12) else { continue }
            results.append(
                MemorySearchResult(
                    block: block,
                    record: record,
                    source: sourcesByID[record.sourceID],
                    score: statement.columnDouble(29),
                    snippet: statement.columnString(30),
                    matchKind: .text
                )
            )
        }
        return results
    }

    private func likeSearch(query: String, limit: Int) throws -> [MemorySearchResult] {
        let connection = try openConnection()
        let sourcesByID = Dictionary(uniqueKeysWithValues: try sources().map { ($0.id, $0) })
        let statement = try connection.prepare(
            """
            SELECT b.id, b.record_id, b.source_id, b.ordinal, b.role, b.text, b.excerpt,
                   b.timestamp, b.model, b.ref, b.text_hash, b.created_at,
                   r.id, r.source_id, r.kind, r.provider, r.external_id, r.title, r.subtitle,
                   r.project_path, r.file_path, r.command, r.cwd, r.exit_code, r.started_at,
                   r.ended_at, r.created_at, r.updated_at, r.metadata_json
            FROM blocks b
            JOIN records r ON r.id = b.record_id
            WHERE lower(b.text) LIKE ? OR lower(r.title) LIKE ? OR lower(COALESCE(r.command, '')) LIKE ?
            ORDER BY COALESCE(b.timestamp, r.started_at, r.updated_at, r.created_at) DESC
            LIMIT ?
            """
        )
        let like = "%\(query.lowercased())%"
        try statement.bind(like, at: 1)
        try statement.bind(like, at: 2)
        try statement.bind(like, at: 3)
        try statement.bind(limit, at: 4)
        var results: [MemorySearchResult] = []
        while try statement.step() {
            guard let block = readBlock(from: statement, offset: 0),
                  let record = readRecord(from: statement, offset: 12) else { continue }
            results.append(
                MemorySearchResult(
                    block: block,
                    record: record,
                    source: sourcesByID[record.sourceID],
                    score: nil,
                    snippet: block.excerpt,
                    matchKind: .text
                )
            )
        }
        return results
    }

    private func ftsQuery(from query: String) -> String {
        let tokens = query
            .split { character in
                character.isWhitespace || character.isPunctuation || character.isSymbol
            }
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            return "\"\(query.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return tokens.map { token in
            let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\"*"
        }.joined(separator: " OR ")
    }

    // MARK: - Writes

    private func insertRecord(_ record: MemoryRecord, connection: MemorySQLiteConnection) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO records (
                id, source_id, kind, provider, external_id, title, subtitle, project_path,
                file_path, command, cwd, exit_code, started_at, ended_at, created_at,
                updated_at, metadata_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                source_id = excluded.source_id,
                kind = excluded.kind,
                provider = excluded.provider,
                external_id = excluded.external_id,
                title = excluded.title,
                subtitle = excluded.subtitle,
                project_path = excluded.project_path,
                file_path = excluded.file_path,
                command = excluded.command,
                cwd = excluded.cwd,
                exit_code = excluded.exit_code,
                started_at = excluded.started_at,
                ended_at = excluded.ended_at,
                updated_at = excluded.updated_at,
                metadata_json = excluded.metadata_json
            """
        )
        try statement.bind(record.id, at: 1)
        try statement.bind(record.sourceID, at: 2)
        try statement.bind(record.kind.rawValue, at: 3)
        try statement.bind(record.providerRaw, at: 4)
        try statement.bind(record.externalID, at: 5)
        try statement.bind(record.title, at: 6)
        try statement.bind(record.subtitle, at: 7)
        try statement.bind(record.projectPath, at: 8)
        try statement.bind(record.filePath, at: 9)
        try statement.bind(record.command, at: 10)
        try statement.bind(record.cwd, at: 11)
        if let exitCode = record.exitCode {
            try statement.bind(exitCode, at: 12)
        } else {
            try statement.bind(nil as Double?, at: 12)
        }
        try statement.bind(record.startedAt, at: 13)
        try statement.bind(record.endedAt, at: 14)
        try statement.bind(record.createdAt, at: 15)
        try statement.bind(record.updatedAt, at: 16)
        try statement.bind(record.metadataJSON, at: 17)
        try statement.finish()
    }

    private func insertBlocks(_ blocks: [MemoryBlock], record: MemoryRecord, connection: MemorySQLiteConnection) throws {
        let insertBlock = try connection.prepare(
            """
            INSERT INTO blocks (
                id, record_id, source_id, ordinal, role, text, excerpt,
                timestamp, model, ref, text_hash, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        let insertFTS = try connection.prepare(
            """
            INSERT INTO blocks_fts (block_id, record_id, source_id, title, content, role)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        )

        for block in blocks {
            try insertBlock.bind(block.id, at: 1)
            try insertBlock.bind(block.recordID, at: 2)
            try insertBlock.bind(block.sourceID, at: 3)
            try insertBlock.bind(block.ordinal, at: 4)
            try insertBlock.bind(block.role.rawValue, at: 5)
            try insertBlock.bind(block.text, at: 6)
            try insertBlock.bind(block.excerpt, at: 7)
            try insertBlock.bind(block.timestamp, at: 8)
            try insertBlock.bind(block.model, at: 9)
            try insertBlock.bind(block.ref, at: 10)
            try insertBlock.bind(block.textHash, at: 11)
            try insertBlock.bind(block.createdAt, at: 12)
            try insertBlock.finish()
            insertBlock.reset()

            try insertFTS.bind(block.id, at: 1)
            try insertFTS.bind(block.recordID, at: 2)
            try insertFTS.bind(block.sourceID, at: 3)
            try insertFTS.bind(record.title, at: 4)
            try insertFTS.bind(block.text, at: 5)
            try insertFTS.bind(block.role.rawValue, at: 6)
            try insertFTS.finish()
            insertFTS.reset()
        }
    }

    private func deleteRecord(id: String, connection: MemorySQLiteConnection) throws {
        try deleteBlocks(recordID: id, connection: connection)
        let record = try connection.prepare("DELETE FROM records WHERE id = ?")
        try record.bind(id, at: 1)
        try record.finish()
    }

    private func deleteBlocks(recordID: String, connection: MemorySQLiteConnection) throws {
        let fts = try connection.prepare("DELETE FROM blocks_fts WHERE record_id = ?")
        try fts.bind(recordID, at: 1)
        try fts.finish()

        let blocks = try connection.prepare("DELETE FROM blocks WHERE record_id = ?")
        try blocks.bind(recordID, at: 1)
        try blocks.finish()
    }

    // MARK: - Reads

    private var recordColumns: String {
        """
        id, source_id, kind, provider, external_id, title, subtitle, project_path,
        file_path, command, cwd, exit_code, started_at, ended_at, created_at,
        updated_at, metadata_json
        """
    }

    private var blockColumns: String {
        """
        id, record_id, source_id, ordinal, role, text, excerpt,
        timestamp, model, ref, text_hash, created_at
        """
    }

    private func readSource(from statement: MemorySQLiteStatement) -> MemorySource? {
        guard let id = statement.columnString(0),
              let kindRaw = statement.columnString(1),
              let kind = MemorySourceKind(rawValue: kindRaw),
              let title = statement.columnString(3),
              let createdAt = statement.columnDate(7),
              let updatedAt = statement.columnDate(8) else {
            return nil
        }
        return MemorySource(
            id: id,
            kind: kind,
            providerRaw: statement.columnString(2),
            title: title,
            path: statement.columnString(4),
            isEnabled: statement.columnInt(5) != 0,
            isDefault: statement.columnInt(6) != 0,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastIndexedAt: statement.columnDate(9),
            lastError: statement.columnString(10)
        )
    }

    private func readRecord(from statement: MemorySQLiteStatement, offset: Int32 = 0) -> MemoryRecord? {
        guard let id = statement.columnString(offset),
              let sourceID = statement.columnString(offset + 1),
              let kindRaw = statement.columnString(offset + 2),
              let kind = MemoryRecordKind(rawValue: kindRaw),
              let title = statement.columnString(offset + 5),
              let createdAt = statement.columnDate(offset + 14),
              let updatedAt = statement.columnDate(offset + 15) else {
            return nil
        }
        return MemoryRecord(
            id: id,
            sourceID: sourceID,
            kind: kind,
            providerRaw: statement.columnString(offset + 3),
            externalID: statement.columnString(offset + 4),
            title: title,
            subtitle: statement.columnString(offset + 6),
            projectPath: statement.columnString(offset + 7),
            filePath: statement.columnString(offset + 8),
            command: statement.columnString(offset + 9),
            cwd: statement.columnString(offset + 10),
            exitCode: statement.columnIsNull(offset + 11) ? nil : statement.columnInt(offset + 11),
            startedAt: statement.columnDate(offset + 12),
            endedAt: statement.columnDate(offset + 13),
            createdAt: createdAt,
            updatedAt: updatedAt,
            metadataJSON: statement.columnString(offset + 16)
        )
    }

    private func readBlock(from statement: MemorySQLiteStatement, offset: Int32 = 0) -> MemoryBlock? {
        guard let id = statement.columnString(offset),
              let recordID = statement.columnString(offset + 1),
              let sourceID = statement.columnString(offset + 2),
              let roleRaw = statement.columnString(offset + 4),
              let role = MemoryBlockRole(rawValue: roleRaw),
              let text = statement.columnString(offset + 5),
              let excerpt = statement.columnString(offset + 6),
              let ref = statement.columnString(offset + 9),
              let textHash = statement.columnString(offset + 10),
              let createdAt = statement.columnDate(offset + 11) else {
            return nil
        }
        return MemoryBlock(
            id: id,
            recordID: recordID,
            sourceID: sourceID,
            ordinal: statement.columnInt(offset + 3),
            role: role,
            text: text,
            excerpt: excerpt,
            timestamp: statement.columnDate(offset + 7),
            model: statement.columnString(offset + 8),
            ref: ref,
            textHash: textHash,
            createdAt: createdAt
        )
    }

    private func count(sql: String, connection: MemorySQLiteConnection) throws -> Int {
        let statement = try connection.prepare(sql)
        guard try statement.step() else { return 0 }
        return statement.columnInt(0)
    }

    // MARK: - Schema

    private func openConnection() throws -> MemorySQLiteConnection {
        if let connection { return connection }
        let connection = try MemorySQLiteConnection(url: url)
        try configure(connection)
        self.connection = connection
        return connection
    }

    private func configure(_ connection: MemorySQLiteConnection) throws {
        try connection.execute("PRAGMA journal_mode=WAL")
        try connection.execute("PRAGMA synchronous=NORMAL")
        try connection.execute("PRAGMA busy_timeout=2500")

        let current = try userVersion(connection)
        if current < Self.schemaVersion {
            try migrate(connection, from: current)
        }
    }

    private func userVersion(_ connection: MemorySQLiteConnection) throws -> Int {
        let statement = try connection.prepare("PRAGMA user_version")
        guard try statement.step() else { return 0 }
        return statement.columnInt(0)
    }

    private func migrate(_ connection: MemorySQLiteConnection, from version: Int) throws {
        var version = version
        if version < 1 {
            try connection.execute(
                """
                CREATE TABLE IF NOT EXISTS sources (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    provider TEXT,
                    title TEXT NOT NULL,
                    path TEXT,
                    is_enabled INTEGER NOT NULL,
                    is_default INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    last_indexed_at REAL,
                    last_error TEXT
                );

                CREATE TABLE IF NOT EXISTS records (
                    id TEXT PRIMARY KEY,
                    source_id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    provider TEXT,
                    external_id TEXT,
                    title TEXT NOT NULL,
                    subtitle TEXT,
                    project_path TEXT,
                    file_path TEXT,
                    command TEXT,
                    cwd TEXT,
                    exit_code INTEGER,
                    started_at REAL,
                    ended_at REAL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    metadata_json TEXT
                );

                CREATE TABLE IF NOT EXISTS blocks (
                    id TEXT PRIMARY KEY,
                    record_id TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    ordinal INTEGER NOT NULL,
                    role TEXT NOT NULL,
                    text TEXT NOT NULL,
                    excerpt TEXT NOT NULL,
                    timestamp REAL,
                    model TEXT,
                    ref TEXT NOT NULL,
                    text_hash TEXT NOT NULL,
                    created_at REAL NOT NULL
                );

                CREATE VIRTUAL TABLE IF NOT EXISTS blocks_fts USING fts5(
                    block_id UNINDEXED,
                    record_id UNINDEXED,
                    source_id UNINDEXED,
                    title,
                    content,
                    role UNINDEXED,
                    tokenize='unicode61'
                );

                CREATE INDEX IF NOT EXISTS idx_memory_records_source ON records(source_id);
                CREATE INDEX IF NOT EXISTS idx_memory_records_kind ON records(kind);
                CREATE INDEX IF NOT EXISTS idx_memory_records_provider_external ON records(provider, external_id);
                CREATE INDEX IF NOT EXISTS idx_memory_blocks_record ON blocks(record_id);
                CREATE INDEX IF NOT EXISTS idx_memory_blocks_source ON blocks(source_id);
                """
            )
            version = 1
        }
        try connection.execute("PRAGMA user_version = \(version)")
    }
}

struct MemoryCounts: Sendable, Hashable {
    var sourceCount: Int
    var recordCount: Int
    var blockCount: Int
    var terminalRecordCount: Int

    static let empty = MemoryCounts(sourceCount: 0, recordCount: 0, blockCount: 0, terminalRecordCount: 0)
}
