import AppKit
import Foundation

struct MemoryDiagnosticsLog {
    static let devLogDirectoryEnvironmentKey = "CLAUDE_STATS_MEMORY_DEV_LOG_DIR"
    static let defaultRetentionDays = 3

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

    static func record(
        _ event: String,
        level: String = "info",
        retentionDays: Int = defaultRetentionDays,
        fields: [String: String] = [:]
    ) {
        let directories = logDirectories()
        prune(retentionDays: retentionDays, directories: directories)
        let payload = MemoryDiagnosticsEvent(
            ts: iso8601Milliseconds(.now),
            level: level,
            event: event,
            fields: sanitized(fields)
        )
        guard var data = try? JSONEncoder.codeMemoryEncoder.encode(payload) else { return }
        data.append(Data("\n".utf8))
        for directory in directories {
            append(data, to: currentLogURL(directory: directory))
        }
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
            for file in contents where file.lastPathComponent.hasPrefix("memory-capture-") && file.pathExtension == "jsonl" {
                guard let date = dateFromLogFilename(file.lastPathComponent), date < cutoff else { continue }
                try? fileManager.removeItem(at: file)
            }
        }
    }

    static func revealLogFolder() {
        let directory = appLogDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([currentLogURL(directory: directory)])
    }

    static func openCurrentLog() {
        let directory = appLogDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = currentLogURL(directory: directory)
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
            Log.app.debug("Memory diagnostics log write failed: \(error.localizedDescription, privacy: .public)")
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

    private static func hourStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HH"
        return formatter.string(from: date)
    }

    private static func dateFromLogFilename(_ filename: String) -> Date? {
        guard filename.hasPrefix("memory-capture-"), filename.hasSuffix(".jsonl") else { return nil }
        let start = filename.index(filename.startIndex, offsetBy: "memory-capture-".count)
        let end = filename.index(filename.endIndex, offsetBy: -".jsonl".count)
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

private struct MemoryDiagnosticsEvent: Encodable {
    var ts: String
    var level: String
    var event: String
    var fields: [String: String]
}
