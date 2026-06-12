import AppKit
import CryptoKit
import Foundation
import OSLog

enum GitOperationLogRetention: Int, CaseIterable, Identifiable, Sendable, Hashable {
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sevenDays: "7 days"
        case .fourteenDays: "14 days"
        case .thirtyDays: "30 days"
        }
    }
}

struct GitOperationFailureNotice: Sendable, Hashable {
    let title: String
    let message: String
    let logEntryID: String?
}

struct GitOperationLogEntry: Sendable, Hashable {
    let id: String
    let summary: String
    let readableLogPath: String
}

struct GitOperationLog {
    static let defaultRetentionDays = 7
    static let retentionDefaultsKey = "git.operationLog.retentionDays"

    private static let logger = Logger(subsystem: "com.claudestats.git", category: "operation-log")
    private static let logFilePrefix = "git-operations-"
    private static let maxOutputCharacters = 24_000

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
        rootDirectory.appendingPathComponent("git-operations", isDirectory: true)
    }

    static func sourceRootLogDirectory(filePath: String = #filePath) -> URL? {
        guard let root = sourceRootDirectory(filePath: filePath) else { return nil }
        return root
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("git-operations", isDirectory: true)
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

    @discardableResult
    static func recordCommandFailure(
        commandName: String,
        result: GitCommandResult,
        retentionDays: Int = configuredRetentionDays,
        directories: [URL] = logDirectories(),
        date: Date = .now
    ) -> GitOperationLogEntry {
        let id = UUID().uuidString.lowercased()
        let summary = userFacingSummary(commandName: commandName, result: result)
        let repoRoot = repoRootPath(from: result.arguments) ?? ""
        let stdout = sanitizedOutput(result.stdout)
        let stderr = sanitizedOutput(result.stderr)
        let fields: [(String, String)] = [
            ("id", id),
            ("operation", operationName(commandName)),
            ("command", commandName),
            ("summary", summary),
            ("repo_root", repoRoot),
            ("repo_root_hash", repoRoot.isEmpty ? "" : hash(repoRoot)),
            ("arguments", redactedArguments(result.arguments).joined(separator: " ")),
            ("exit_code", "\(result.exitCode)"),
            ("timed_out", result.timedOut ? "true" : "false"),
            ("cancelled", result.cancelled ? "true" : "false"),
            ("stderr", stderr),
            ("stdout", stdout),
        ]
        prune(retentionDays: retentionDays, directories: directories, now: date)
        let jsonData = recordData(fields: fields, date: date)
        let readableData = readableRecordData(fields: fields, date: date)
        for directory in directories {
            append(jsonData, to: currentLogURL(directory: directory, date: date))
            append(readableData, to: currentReadableLogURL(directory: directory, date: date))
        }
        return GitOperationLogEntry(
            id: id,
            summary: summary,
            readableLogPath: currentReadableLogURL(directory: directories.first, date: date).path
        )
    }

    static func recordData(fields: [(String, String)], date: Date = .now) -> Data {
        let pairs = [("ts", iso8601Milliseconds(date)), ("level", "error"), ("event", "git.command.failed")] + fields
        let body = pairs
            .map { key, value in
                "\"\(jsonEscaped(key))\": \"\(jsonEscaped(value))\""
            }
            .joined(separator: ", ")
        return Data("{\(body)}\n".utf8)
    }

    static func readableRecordData(fields: [(String, String)], date: Date = .now) -> Data {
        let dictionary = Dictionary(uniqueKeysWithValues: fields)
        var lines = ["[\(iso8601Milliseconds(date))] ERROR git.command.failed"]
        for (key, value) in fields where key != "stdout" && key != "stderr" {
            lines.append("  \(key): \(readableInline(value))")
        }
        if let stderr = dictionary["stderr"], !stderr.isEmpty {
            lines.append("  stderr:")
            lines.append(indent(stderr))
        }
        if let stdout = dictionary["stdout"], !stdout.isEmpty {
            lines.append("  stdout:")
            lines.append(indent(stdout))
        }
        lines.append("")
        lines.append("")
        return Data(lines.joined(separator: "\n").utf8)
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

    static func failureNotice(
        from error: Error,
        title: String,
        fallbackMessage: String
    ) -> GitOperationFailureNotice {
        if let error = error as? GitCommitCommandError {
            return GitOperationFailureNotice(
                title: title,
                message: error.errorDescription ?? fallbackMessage,
                logEntryID: error.logEntryID
            )
        }
        return GitOperationFailureNotice(
            title: title,
            message: error.localizedDescription.isEmpty ? fallbackMessage : error.localizedDescription,
            logEntryID: nil
        )
    }

    private static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
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
        if days >= 30 { return 30 }
        if days >= 14 { return 14 }
        return 7
    }

    private static func userFacingSummary(commandName: String, result: GitCommandResult) -> String {
        if result.timedOut {
            return "\(commandName) timed out. View Logs for details."
        }

        let output = [result.stderr, result.stdout]
            .joined(separator: "\n")
            .lowercased()

        switch commandName {
        case "git add -A":
            return "Commit failed: git could not stage the working tree. View Logs for details."
        case "git commit":
            if output.contains("pre-commit") || output.contains("lint-staged") || output.contains("husky") ||
                output.contains("eslint") || output.contains("[failed]") {
                return "Commit failed: pre-commit checks failed. View Logs for details."
            }
            if output.contains("nothing to commit") {
                return "Commit failed: there are no changes to commit. View Logs for details."
            }
            return "Commit failed. View Logs for details."
        case "git push":
            if output.contains("non-fast-forward") || output.contains("fetch first") || output.contains("rejected") {
                return "Push failed: the remote rejected the update. View Logs for details."
            }
            return "Push failed. View Logs for details."
        default:
            return "\(commandName) failed. View Logs for details."
        }
    }

    private static func operationName(_ commandName: String) -> String {
        switch commandName {
        case "git add -A", "git commit": "git.commit"
        case "git push": "git.push"
        default: "git.command"
        }
    }

    private static func repoRootPath(from arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-C") else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return nil }
        return arguments[next]
    }

    private static func redactedArguments(_ arguments: [String]) -> [String] {
        arguments.map { argument in
            let lower = argument.lowercased()
            if lower.contains("password") || lower.contains("secret") || lower.contains("token") ||
                lower.contains("authorization") || lower.contains("api_key") {
                return "[redacted]"
            }
            return argument
        }
    }

    private static func sanitizedOutput(_ output: String) -> String {
        let redacted = output
            .components(separatedBy: .newlines)
            .map { line -> String in
                let lower = line.lowercased()
                if lower.contains("authorization:") || lower.contains("api_key") ||
                    lower.contains("api-key") || lower.contains("password=") ||
                    lower.contains("secret=") || lower.contains("token=") {
                    return "[redacted line]"
                }
                return line
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard redacted.count > maxOutputCharacters else { return redacted }
        return "[truncated to last \(maxOutputCharacters) characters]\n" + String(redacted.suffix(maxOutputCharacters))
    }

    private static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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
            logger.debug("Git operation log write failed: \(error.localizedDescription, privacy: .public)")
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

    private static func readableInline(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func indent(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .map { "    \($0)" }
            .joined(separator: "\n")
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
