import Foundation

enum MemoryShell: String, CaseIterable, Identifiable, Sendable, Hashable {
    case zsh
    case bash

    var id: String { rawValue }

    var rcURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .zsh:
            return home.appendingPathComponent(".zshrc", isDirectory: false)
        case .bash:
            return home.appendingPathComponent(".bashrc", isDirectory: false)
        }
    }
}

struct MemoryShellIntegrationStatus: Identifiable, Sendable, Hashable {
    let shell: MemoryShell
    let rcPath: String
    let isInstalled: Bool
    let helperPath: String?

    var id: String { shell.rawValue }
}

struct MemoryShellIntegrationManager: Sendable {
    private static let beginMarker = "# >>> Claude Stats Memory >>>"
    private static let endMarker = "# <<< Claude Stats Memory <<<"

    func status(shell: MemoryShell) -> MemoryShellIntegrationStatus {
        let text = (try? String(contentsOf: shell.rcURL, encoding: .utf8)) ?? ""
        let block = existingBlock(in: text)
        let helperPath = block.flatMap { lineValue(prefix: "# helper: ", in: $0) }
        return MemoryShellIntegrationStatus(
            shell: shell,
            rcPath: shell.rcURL.path,
            isInstalled: block != nil,
            helperPath: helperPath
        )
    }

    func install(shell: MemoryShell, helperPath: String) throws -> URL? {
        let url = shell.rcURL
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let block = render(shell: shell, helperPath: helperPath)
        let next = replacingBlock(in: existing, with: block)
        guard next != existing else { return nil }
        let backupURL = try backupIfNeeded(url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try next.write(to: url, atomically: true, encoding: .utf8)
        return backupURL
    }

    func uninstall(shell: MemoryShell) throws -> URL? {
        let url = shell.rcURL
        guard let existing = try? String(contentsOf: url, encoding: .utf8),
              existingBlock(in: existing) != nil else {
            return nil
        }
        let backupURL = try backupIfNeeded(url)
        let next = replacingBlock(in: existing, with: nil)
        try next.write(to: url, atomically: true, encoding: .utf8)
        return backupURL
    }

    func render(shell: MemoryShell, helperPath: String) -> String {
        let quoted = shellQuoted(helperPath)
        switch shell {
        case .zsh:
            return """
            \(Self.beginMarker)
            # helper: \(helperPath)
            if [ -x \(quoted) ]; then
              autoload -Uz add-zsh-hook
              _claude_stats_memory_preexec() {
                export __CLAUDE_STATS_MEMORY_COMMAND="$1"
                export __CLAUDE_STATS_MEMORY_STARTED_AT="$(date +%s)"
              }
              _claude_stats_memory_precmd() {
                local __claude_stats_memory_status="$?"
                if [ -n "${__CLAUDE_STATS_MEMORY_COMMAND:-}" ]; then
                  \(quoted) record-shell --shell zsh --command "$__CLAUDE_STATS_MEMORY_COMMAND" --exit "$__claude_stats_memory_status" --cwd "$PWD" --started-at "${__CLAUDE_STATS_MEMORY_STARTED_AT:-}"
                  unset __CLAUDE_STATS_MEMORY_COMMAND
                  unset __CLAUDE_STATS_MEMORY_STARTED_AT
                fi
              }
              add-zsh-hook preexec _claude_stats_memory_preexec
              add-zsh-hook precmd _claude_stats_memory_precmd
            fi
            \(Self.endMarker)
            """
        case .bash:
            return """
            \(Self.beginMarker)
            # helper: \(helperPath)
            if [ -x \(quoted) ]; then
              _claude_stats_memory_prompt() {
                local __claude_stats_memory_status="$?"
                local __claude_stats_memory_command
                __claude_stats_memory_command="$(HISTTIMEFORMAT= history 1 | sed 's/^ *[0-9][0-9]* *//')"
                if [ -n "$__claude_stats_memory_command" ]; then
                  \(quoted) record-shell --shell bash --command "$__claude_stats_memory_command" --exit "$__claude_stats_memory_status" --cwd "$PWD"
                fi
              }
              case ";$PROMPT_COMMAND;" in
                *";_claude_stats_memory_prompt;"*) ;;
                *) PROMPT_COMMAND="_claude_stats_memory_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
              esac
            fi
            \(Self.endMarker)
            """
        }
    }

    private func existingBlock(in text: String) -> String? {
        guard let start = text.range(of: Self.beginMarker),
              let end = text.range(of: Self.endMarker, range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.lowerBound..<end.upperBound])
    }

    private func replacingBlock(in text: String, with block: String?) -> String {
        guard let start = text.range(of: Self.beginMarker),
              let end = text.range(of: Self.endMarker, range: start.upperBound..<text.endIndex) else {
            guard let block else { return text }
            let separator = text.hasSuffix("\n") || text.isEmpty ? "" : "\n"
            return text + separator + block + "\n"
        }

        var next = text
        let replacement: String
        if let block {
            replacement = block + "\n"
        } else {
            replacement = ""
        }
        next.replaceSubrange(start.lowerBound..<end.upperBound, with: replacement)
        return next
    }

    private func backupIfNeeded(_ url: URL) throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).claude-stats-memory.\(stamp).bak", isDirectory: false)
        try FileManager.default.copyItem(at: url, to: backup)
        return backup
    }

    private func lineValue(prefix: String, in block: String) -> String? {
        guard let line = block
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return String(line.dropFirst(prefix.count))
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
