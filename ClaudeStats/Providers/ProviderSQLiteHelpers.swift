import Foundation

enum ProviderSQLiteHelpers {
    static func tableExists(_ table: String, in connection: SQLiteConnection) -> Bool {
        guard let statement = try? connection.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1") else {
            return false
        }
        try? statement.bind(table, at: 1)
        return (try? statement.step()) == true
    }

    static func columns(in table: String, connection: SQLiteConnection) -> Set<String> {
        guard let statement = try? connection.prepare("PRAGMA table_info(\(quotedIdentifier(table)))") else {
            return []
        }
        var columns: Set<String> = []
        while (try? statement.step()) == true {
            if let name = statement.columnString(1), !name.isEmpty {
                columns.insert(name)
            }
        }
        return columns
    }

    static func expression(_ column: String,
                           columns: Set<String>,
                           default defaultExpression: String = "NULL",
                           alias: String? = nil) -> String {
        let base = columns.contains(column) ? quotedIdentifier(column) : defaultExpression
        guard let alias else { return base }
        return "\(base) AS \(quotedIdentifier(alias))"
    }

    static func coalescedExpression(_ candidates: [String],
                                    columns: Set<String>,
                                    default defaultExpression: String = "NULL",
                                    alias: String) -> String {
        let existing = candidates
            .filter { columns.contains($0) }
            .map(quotedIdentifier)
        let base: String
        if existing.isEmpty {
            base = defaultExpression
        } else if existing.count == 1 {
            base = existing[0]
        } else {
            base = "COALESCE(\(existing.joined(separator: ", ")))"
        }
        return "\(base) AS \(quotedIdentifier(alias))"
    }

    static func quotedIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func columnInt(_ statement: SQLiteStatement, _ index: Int32) -> Int {
        statement.columnIsNull(index) ? 0 : statement.columnInt(index)
    }

    static func columnInt64(_ statement: SQLiteStatement, _ index: Int32) -> Int64 {
        statement.columnIsNull(index) ? 0 : statement.columnInt64(index)
    }

    static func columnDouble(_ statement: SQLiteStatement, _ index: Int32) -> Double? {
        statement.columnIsNull(index) ? nil : statement.columnDouble(index)
    }
}
