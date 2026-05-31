import AppKit
import Foundation
import OSLog

struct MemoryDiagnosticsLog {
    static let devLogDirectoryEnvironmentKey = "CLAUDE_STATS_MEMORY_DEV_LOG_DIR"
    static let defaultRetentionDays = 3
    private static let logger = Logger(subsystem: "com.claudestats.memory", category: "diagnostics")
    private static let canonicalFieldOrder = [
        "run_id",
        "source_id",
        "source_kind",
        "project_id",
        "chunk_index",
        "duration_ms",
        "counts",
        "model",
        "error",
    ]
    private static let canonicalFieldKeys = Set(canonicalFieldOrder)
    private static let reservedRecordKeys: Set<String> = ["ts", "level", "event"]

    static func appLogDirectory(rootDirectory: URL = MemoryPaths.rootDirectory()) -> URL {
        rootDirectory.appendingPathComponent("diagnostics", isDirectory: true)
    }

    static func devLogDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let raw = environment[devLogDirectoryEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    static func logDirectories(rootDirectory: URL = MemoryPaths.rootDirectory()) -> [URL] {
        var directories = [appLogDirectory(rootDirectory: rootDirectory)]
        if let dev = devLogDirectory() {
            directories.append(dev)
        }
        return directories
    }

    static func currentLogURL(directory: URL? = nil, date: Date = .now) -> URL {
        let directory = directory ?? appLogDirectory()
        return directory.appendingPathComponent("memory-capture-\(hourStamp(date)).jsonl", isDirectory: false)
    }

    static func currentReadableLogURL(directory: URL? = nil, date: Date = .now) -> URL {
        let directory = directory ?? appLogDirectory()
        return directory.appendingPathComponent("memory-capture-\(hourStamp(date)).log", isDirectory: false)
    }

    static func record(
        _ event: String,
        level: String = "info",
        retentionDays: Int = defaultRetentionDays,
        fields: [String: String] = [:]
    ) {
        let directories = logDirectories()
        prune(retentionDays: retentionDays, directories: directories)
        let date = Date.now
        let pairs = recordPairs(event, level: level, date: date, fields: fields)
        let jsonData = recordData(pairs: pairs)
        let readableData = readableRecordData(pairs: pairs)
        for directory in directories {
            append(jsonData, to: currentLogURL(directory: directory, date: date))
            append(readableData, to: currentReadableLogURL(directory: directory, date: date))
        }
    }

    static func recordData(
        _ event: String,
        level: String = "info",
        date: Date = .now,
        fields: [String: String] = [:]
    ) -> Data {
        recordData(pairs: recordPairs(event, level: level, date: date, fields: fields))
    }

    static func readableRecordData(
        _ event: String,
        level: String = "info",
        date: Date = .now,
        fields: [String: String] = [:]
    ) -> Data {
        readableRecordData(pairs: recordPairs(event, level: level, date: date, fields: fields))
    }

    private static func recordPairs(
        _ event: String,
        level: String,
        date: Date,
        fields: [String: String]
    ) -> [(String, String)] {
        let cleanFields = sanitized(fields)
        var emittedOutputKeys = reservedRecordKeys
        var pairs: [(String, String)] = [
            ("ts", iso8601Milliseconds(date)),
            ("level", level),
            ("event", event),
        ]

        for key in canonicalFieldOrder {
            guard let value = cleanFields[key] else { continue }
            pairs.append((key, value))
            emittedOutputKeys.insert(key)
        }

        for key in cleanFields.keys.sorted() where !canonicalFieldKeys.contains(key) {
            let outputKey = reservedRecordKeys.contains(key) ? "field_\(key)" : key
            guard !emittedOutputKeys.contains(outputKey) else { continue }
            pairs.append((outputKey, cleanFields[key] ?? ""))
            emittedOutputKeys.insert(outputKey)
        }

        return pairs
    }

    private static func recordData(pairs: [(String, String)]) -> Data {
        let body = pairs
            .map { key, value in
                "\"\(jsonEscaped(key))\": \"\(jsonEscaped(value))\""
            }
            .joined(separator: ", ")
        return Data("{\(body)}\n".utf8)
    }

    private static func readableRecordData(pairs: [(String, String)]) -> Data {
        let dictionary = Dictionary(uniqueKeysWithValues: pairs)
        let timestamp = dictionary["ts"] ?? "-"
        let level = dictionary["level"] ?? "info"
        let event = dictionary["event"] ?? "-"
        let fields = pairs.filter { key, _ in !reservedRecordKeys.contains(key) }
        let keyWidth = min(max(fields.map { $0.0.count }.max() ?? 0, 1), 24)
        var lines = ["[\(timestamp)] \(level.uppercased()) \(event)"]
        for (key, value) in fields {
            let padding = String(repeating: " ", count: max(keyWidth - key.count, 0))
            lines.append("  \(key)\(padding)  \(readableEscaped(value))")
        }
        lines.append("")
        lines.append("")
        return Data(lines.joined(separator: "\n").utf8)
    }

    static func prune(retentionDays: Int, directories: [URL] = logDirectories(), now: Date = .now) {
        let boundedDays = retentionDays >= 7 ? 7 : 3
        let cutoff = now.addingTimeInterval(-TimeInterval(boundedDays * 24 * 60 * 60))
        let fileManager = FileManager.default
        for directory in directories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in contents where file.lastPathComponent.hasPrefix("memory-capture-") && ["jsonl", "log"].contains(file.pathExtension) {
                guard let date = dateFromLogFilename(file.lastPathComponent), date < cutoff else { continue }
                try? fileManager.removeItem(at: file)
            }
        }
    }

    static func revealLogFolder() {
        let directory = appLogDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([currentReadableLogURL(directory: directory)])
    }

    static func openCurrentLog() {
        let directory = appLogDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = currentReadableLogURL(directory: directory)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data().write(to: url, options: [.atomic])
        }
        NSWorkspace.shared.open(url)
    }

    private static func append(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: [.atomic])
            }
        } catch {
            logger.debug("Memory diagnostics log write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func sanitized(_ fields: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in fields {
            let lower = key.lowercased()
            if lower.contains("api_key") || lower.contains("token") || lower.contains("secret") || lower.contains("password") {
                result[key] = "[redacted]"
            } else {
                result[key] = String(value.prefix(600))
            }
        }
        return result
    }

    private static func jsonEscaped(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22:
                result += "\\\""
            case 0x5C:
                result += "\\\\"
            case 0x0A:
                result += "\\n"
            case 0x0D:
                result += "\\r"
            case 0x09:
                result += "\\t"
            case 0x00..<0x20:
                result += String(format: "\\u%04X", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func readableEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func hourStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HH"
        return formatter.string(from: date)
    }

    private static func dateFromLogFilename(_ filename: String) -> Date? {
        guard filename.hasPrefix("memory-capture-") else { return nil }
        guard filename.hasSuffix(".jsonl") || filename.hasSuffix(".log") else { return nil }
        let start = filename.index(filename.startIndex, offsetBy: "memory-capture-".count)
        let suffixLength = filename.hasSuffix(".jsonl") ? ".jsonl".count : ".log".count
        let end = filename.index(filename.endIndex, offsetBy: -suffixLength)
        let stamp = String(filename[start..<end])
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HH"
        return formatter.date(from: stamp)
    }

    private static func iso8601Milliseconds(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
