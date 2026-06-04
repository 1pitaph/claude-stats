import AppKit
import CryptoKit
import Foundation
import OSLog

enum GitCommitMessageDiagnosticsRetention: Int, CaseIterable, Identifiable, Sendable, Hashable {
    case threeDays = 3
    case sevenDays = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .threeDays: "3 days"
        case .sevenDays: "7 days"
        }
    }
}

struct GitCommitMessageDiagnosticsLog {
    static let defaultRetentionDays = 3
    static let retentionDefaultsKey = "gitCommitMessage.diagnostics.retentionDays"

    private static let logger = Logger(subsystem: "com.claudestats.git", category: "commit-message-diagnostics")
    private static let logFilePrefix = "git-commit-message-"
    private static let canonicalFieldOrder = [
        "run_id",
        "call_id",
        "phase",
        "algorithm",
        "target_kind",
        "target_id_hash",
        "repo_key_hash",
        "diff_hash",
        "chunk_id",
        "file_count",
        "risk_categories",
        "prompt_version",
        "algorithm_version",
        "mode",
        "protocol",
        "base_host",
        "model",
        "output_shape",
        "max_tokens",
        "temperature",
        "prompt_chars",
        "prompt_hash",
        "duration_ms",
        "input_tokens",
        "output_tokens",
        "total_tokens",
        "response_chars",
        "response_hash",
        "json_parse_ok",
        "cache_hit",
        "error_type",
        "error",
    ]
    private static let canonicalFieldKeys = Set(canonicalFieldOrder)
    private static let reservedRecordKeys: Set<String> = ["ts", "level", "event"]

    static var configuredRetentionDays: Int {
        let raw = UserDefaults.standard.integer(forKey: retentionDefaultsKey)
        return normalizedRetentionDays(raw == 0 ? defaultRetentionDays : raw)
    }

    static func setConfiguredRetentionDays(_ days: Int) {
        let normalized = normalizedRetentionDays(days)
        UserDefaults.standard.set(normalized, forKey: retentionDefaultsKey)
        prune(retentionDays: normalized, directories: logDirectories())
    }

    static func appLogDirectory(rootDirectory: URL = defaultRootDirectory()) -> URL {
        rootDirectory.appendingPathComponent("diagnostics", isDirectory: true)
    }

    static func sourceRootLogDirectory(filePath: String = #filePath) -> URL? {
        guard let root = sourceRootDirectory(filePath: filePath) else { return nil }
        return root
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("git-commit-message", isDirectory: true)
    }

    static func logDirectories(filePath: String = #filePath) -> [URL] {
        var directories = [appLogDirectory()]
        if let source = sourceRootLogDirectory(filePath: filePath),
           !directories.contains(where: { $0.standardizedFileURL == source.standardizedFileURL }) {
            directories.append(source)
        }
        return directories
    }

    static func currentLogURL(directory: URL? = nil, date: Date = .now) -> URL {
        let directory = directory ?? appLogDirectory()
        return directory.appendingPathComponent("\(logFilePrefix)\(hourStamp(date)).jsonl", isDirectory: false)
    }

    static func currentReadableLogURL(directory: URL? = nil, date: Date = .now) -> URL {
        let directory = directory ?? appLogDirectory()
        return directory.appendingPathComponent("\(logFilePrefix)\(hourStamp(date)).log", isDirectory: false)
    }

    static func currentLogSize(directory: URL? = nil, date: Date = .now) -> Int {
        size(of: currentLogURL(directory: directory, date: date))
    }

    static func currentReadableLogSize(directory: URL? = nil, date: Date = .now) -> Int {
        size(of: currentReadableLogURL(directory: directory, date: date))
    }

    static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func record(
        _ event: String,
        level: String = "info",
        retentionDays: Int = configuredRetentionDays,
        fields: [String: String] = [:]
    ) {
        record(
            event,
            level: level,
            retentionDays: retentionDays,
            directories: logDirectories(),
            date: .now,
            fields: fields
        )
    }

    static func record(
        _ event: String,
        level: String = "info",
        retentionDays: Int = configuredRetentionDays,
        directories: [URL],
        date: Date = .now,
        fields: [String: String] = [:]
    ) {
        prune(retentionDays: retentionDays, directories: directories, now: date)
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

    static func prune(retentionDays: Int, directories: [URL] = logDirectories(), now: Date = .now) {
        let boundedDays = normalizedRetentionDays(retentionDays)
        let cutoff = now.addingTimeInterval(-TimeInterval(boundedDays * 24 * 60 * 60))
        let fileManager = FileManager.default
        for directory in directories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in contents where file.lastPathComponent.hasPrefix(logFilePrefix) && ["jsonl", "log"].contains(file.pathExtension) {
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

    static func revealSourceRootLogFolder() {
        guard let directory = sourceRootLogDirectory() else {
            revealLogFolder()
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([currentReadableLogURL(directory: directory)])
    }

    private static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("GitCommitMessage", isDirectory: true)
    }

    private static func sourceRootDirectory(filePath: String) -> URL? {
        var url = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while url.path != "/" {
            if url.lastPathComponent == "ClaudeStats" || url.lastPathComponent == "ClaudeStatsTests" {
                return url.deletingLastPathComponent()
            }
            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path else { return nil }
            url = parent
        }
        return nil
    }

    private static func normalizedRetentionDays(_ days: Int) -> Int {
        days >= 7 ? 7 : 3
    }

    private static func recordPairs(
        _ event: String,
        level: String,
        date: Date,
        fields: [String: String]
    ) -> [(String, String)] {
        let cleanFields = sanitized(fields)
        var pairs: [(String, String)] = [
            ("ts", iso8601Milliseconds(date)),
            ("level", level),
            ("event", event),
        ]

        for key in canonicalFieldOrder {
            guard let value = cleanFields[key] else { continue }
            pairs.append((key, value))
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

    private static func sanitized(_ fields: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in fields where canonicalFieldKeys.contains(key) {
            let lower = key.lowercased()
            if lower.contains("api_key") || lower.contains("authorization") ||
                lower.contains("secret") || lower.contains("password") {
                result[key] = "[redacted]"
            } else {
                result[key] = String(value.prefix(600))
            }
        }
        return result
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
            logger.debug("Git commit message diagnostics log write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func size(of url: URL) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.intValue ?? 0
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

    private static func iso8601Milliseconds(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
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
        guard filename.hasPrefix(logFilePrefix) else { return nil }
        guard filename.hasSuffix(".jsonl") || filename.hasSuffix(".log") else { return nil }
        let start = filename.index(filename.startIndex, offsetBy: logFilePrefix.count)
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
}
