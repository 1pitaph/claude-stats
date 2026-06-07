import Foundation

enum ProviderStorageHelpers {
    struct FileSnapshot: Sendable, Hashable {
        let size: Int64
        let modified: Date

        static let missing = FileSnapshot(size: 0, modified: .distantPast)
    }

    static func sqliteSnapshot(for databaseURL: URL) -> FileSnapshot {
        let urls = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ]
        return snapshot(for: urls)
    }

    static func snapshot(for urls: [URL]) -> FileSnapshot {
        var size: Int64 = 0
        var modified = Date.distantPast
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                continue
            }
            size += Int64(values.fileSize ?? 0)
            if let date = values.contentModificationDate, date > modified {
                modified = date
            }
        }
        return FileSnapshot(size: size, modified: modified)
    }

    static func pathDigest(_ path: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    static func firstExistingDirectory(_ urls: [URL]) -> URL? {
        urls.first { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    static func databaseURLs(in directory: URL, prefix: String) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            .filter { url in
                guard url.pathExtension == "db" || url.pathExtension == "sqlite3" else { return false }
                return url.lastPathComponent.hasPrefix(prefix)
                    && ((try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true)
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

enum ProviderDateParser {
    private static let isoWithFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let isoWithoutFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func date(from value: Any?) -> Date? {
        if let value = value as? Date { return value }
        if let value = value as? Int { return date(fromNumeric: Double(value)) }
        if let value = value as? Int64 { return date(fromNumeric: Double(value)) }
        if let value = value as? Double { return date(fromNumeric: value) }
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let number = Double(trimmed) { return date(fromNumeric: number) }
            if let date = try? isoWithFraction.parse(trimmed) { return date }
            if let date = try? isoWithoutFraction.parse(trimmed) { return date }
            return nil
        }
        return nil
    }

    static func date(fromSQLiteNumber value: Int64) -> Date? {
        guard value > 0 else { return nil }
        return date(fromNumeric: Double(value))
    }

    private static func date(fromNumeric value: Double) -> Date? {
        guard value > 0 else { return nil }
        if value > 10_000_000_000 {
            return Date(timeIntervalSince1970: value / 1_000)
        }
        return Date(timeIntervalSince1970: value)
    }
}

enum ProviderJSON {
    static func object(from data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }

    static func object(from string: String?) -> Any? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8) else {
            return nil
        }
        return object(from: data)
    }

    static func dictionary(from string: String?) -> [String: Any]? {
        object(from: string) as? [String: Any]
    }

    static func string(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    static func int(_ dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let int = value as? Int { return int }
            if let int64 = value as? Int64 { return Int(int64) }
            if let double = value as? Double { return Int(double) }
            if let number = value as? NSNumber { return number.intValue }
            if let string = value as? String, let int = Int(string) { return int }
        }
        return nil
    }

    static func double(_ dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let double = value as? Double { return double }
            if let int = value as? Int { return Double(int) }
            if let number = value as? NSNumber { return number.doubleValue }
            if let string = value as? String, let double = Double(string) { return double }
        }
        return nil
    }

    static func date(_ dictionary: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let date = ProviderDateParser.date(from: dictionary[key]) { return date }
        }
        return nil
    }
}

enum ProviderTranscriptExtraction {
    static func role(from object: Any) -> SessionTranscriptMessage.Role? {
        guard let dictionary = object as? [String: Any] else { return nil }
        let raw = ProviderJSON.string(dictionary, keys: ["role", "type", "kind", "author", "speaker"])?.lowercased()
        switch raw {
        case "user", "human", "prompt":
            return .user
        case "assistant", "agent", "assistantmessage", "assistant_message":
            return .assistant
        case "tool", "tooluse", "tool_use", "toolresult", "tool_result":
            return .tool
        case "system":
            return .system
        default:
            return nil
        }
    }

    static func text(from object: Any, maxFragments: Int = 80) -> String? {
        var fragments: [String] = []
        collectText(from: object, into: &fragments, maxFragments: maxFragments, inToolContext: false)
        let joined = fragments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    static func usage(from object: Any) -> TokenUsage? {
        var usage = TokenUsage.zero
        collectUsage(from: object, into: &usage)
        return usage.total > 0 ? usage : nil
    }

    static func commands(from object: Any) -> [String] {
        var commands: [String] = []
        collectCommands(from: object, into: &commands, inheritedToolContext: false)
        var seen: Set<String> = []
        return commands.compactMap { command in
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    static func estimatedTokens(for text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }

    private static func collectText(from value: Any,
                                    into fragments: inout [String],
                                    maxFragments: Int,
                                    inToolContext: Bool) {
        guard fragments.count < maxFragments else { return }
        if let dictionary = value as? [String: Any] {
            let type = ProviderJSON.string(dictionary, keys: ["type", "kind", "role", "name"])?.lowercased() ?? ""
            let isToolContext = inToolContext || type.contains("tool")
            for key in ["text", "content", "message", "response", "output", "input"] {
                guard !isToolContext || key == "text" || key == "content" || key == "message" else { continue }
                if let string = dictionary[key] as? String {
                    if ProviderJSON.object(from: string) == nil {
                        fragments.append(string)
                    }
                }
            }
            for key in ["content", "parts", "messages", "data", "delta"] {
                if let child = dictionary[key] {
                    collectText(from: child, into: &fragments, maxFragments: maxFragments, inToolContext: isToolContext)
                }
            }
            return
        }
        if let array = value as? [Any] {
            for child in array {
                collectText(from: child, into: &fragments, maxFragments: maxFragments, inToolContext: inToolContext)
            }
        }
    }

    private static func collectUsage(from value: Any, into usage: inout TokenUsage) {
        if let dictionary = value as? [String: Any] {
            usage.inputTokens += ProviderJSON.int(dictionary, keys: [
                "input_tokens", "inputTokens", "prompt_tokens", "promptTokens",
            ]) ?? 0
            usage.outputTokens += ProviderJSON.int(dictionary, keys: [
                "output_tokens", "outputTokens", "completion_tokens", "completionTokens",
            ]) ?? 0
            usage.outputTokens += ProviderJSON.int(dictionary, keys: [
                "reasoning_tokens", "reasoningTokens", "tokens_reasoning",
            ]) ?? 0
            usage.cacheReadTokens += ProviderJSON.int(dictionary, keys: [
                "cache_read_tokens", "cacheReadTokens", "cached_input_tokens",
                "cachedInputTokens", "cache_read", "cacheRead",
            ]) ?? 0
            usage.cacheCreation5mTokens += ProviderJSON.int(dictionary, keys: [
                "cache_write_tokens", "cacheWriteTokens", "cache_creation_input_tokens",
                "cacheCreationInputTokens", "cache_write", "cacheWrite",
            ]) ?? 0

            for key in ["usage", "token_usage", "tokenUsage", "metadata", "details"] {
                if let child = dictionary[key] {
                    collectUsage(from: child, into: &usage)
                }
            }
            return
        }
        if let array = value as? [Any] {
            for child in array { collectUsage(from: child, into: &usage) }
        }
    }

    private static func collectCommands(from value: Any,
                                        into commands: inout [String],
                                        inheritedToolContext: Bool) {
        if let dictionary = value as? [String: Any] {
            let isToolContext = inheritedToolContext || indicatesCommandTool(dictionary)
            if isToolContext {
                for key in commandKeys {
                    if let command = dictionary[key] as? String {
                        commands.append(command)
                    }
                }
            }
            for key in jsonArgumentKeys {
                if let string = dictionary[key] as? String,
                   let parsed = ProviderJSON.object(from: string) {
                    collectCommands(from: parsed, into: &commands, inheritedToolContext: isToolContext)
                }
            }
            for (key, child) in dictionary where !commandKeys.contains(key) {
                collectCommands(from: child, into: &commands, inheritedToolContext: isToolContext)
            }
            return
        }
        if let array = value as? [Any] {
            for child in array {
                collectCommands(from: child, into: &commands, inheritedToolContext: inheritedToolContext)
            }
        }
    }

    private static func indicatesCommandTool(_ dictionary: [String: Any]) -> Bool {
        for key in contextKeys {
            guard let raw = dictionary[key] as? String else { continue }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty else { continue }
            if ["bash", "shell", "terminal", "exec_command", "run_command", "command"].contains(value) {
                return true
            }
            if value.contains("shell") || value.contains("terminal") || value.contains("command") || value.contains("exec") {
                return true
            }
        }
        return false
    }

    private static let commandKeys: Set<String> = [
        "command", "cmd", "command_line", "shell_command",
    ]

    private static let jsonArgumentKeys: Set<String> = [
        "arguments", "args", "input", "tool_calls", "toolCalls",
    ]

    private static let contextKeys: Set<String> = [
        "type", "name", "tool", "tool_name", "toolName", "kind", "event", "subtype", "category",
    ]
}
