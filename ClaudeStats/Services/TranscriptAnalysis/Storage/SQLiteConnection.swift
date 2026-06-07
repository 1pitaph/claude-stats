import Foundation
import SQLite3

enum SQLiteStorageError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case executeFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): "SQLite open failed: \(message)"
        case .prepareFailed(let message): "SQLite prepare failed: \(message)"
        case .stepFailed(let message): "SQLite step failed: \(message)"
        case .bindFailed(let message): "SQLite bind failed: \(message)"
        case .executeFailed(let message): "SQLite execute failed: \(message)"
        }
    }
}

final class SQLiteConnection {
    private var db: OpaquePointer?

    init(url: URL, readOnly: Bool = false) throws {
        if !readOnly {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw SQLiteStorageError.openFailed(message)
        }
        if readOnly {
            try? execute("PRAGMA query_only = ON")
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
            throw SQLiteStorageError.executeFailed(message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(lastErrorMessage)
        }
        return SQLiteStatement(connection: self, statement: statement)
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

    var raw: OpaquePointer? { db }

    var lastErrorMessage: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }
}
