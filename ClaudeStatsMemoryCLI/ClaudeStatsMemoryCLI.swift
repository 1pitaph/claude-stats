import Darwin
import Foundation

@main
enum ClaudeStatsMemoryCLI {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            return
        }
        arguments.removeFirst()

        do {
            switch command {
            case "run":
                let exitCode = try await runCommand(arguments)
                exit(Int32(exitCode))
            case "pipe":
                try await pipe()
            case "history":
                try await history(arguments)
            case "init":
                try shellInit(arguments)
            case "record-shell":
                try await recordShell(arguments)
            case "-h", "--help", "help":
                printUsage()
            default:
                throw CLIError.message("Unknown command: \(command)")
            }
        } catch {
            FileHandle.standardError.write(Data("claude-stats-memory: \(error.localizedDescription)\n".utf8))
            exit(2)
        }
    }

    private static func runCommand(_ arguments: [String]) async throws -> Int {
        guard let executable = arguments.first else {
            throw CLIError.message("Usage: claude-stats-memory run <command> [args...]")
        }
        let commandArguments = Array(arguments.dropFirst())
        let startedAt = Date()
        let cwd = FileManager.default.currentDirectoryPath
        let capture = ProcessCaptureBuffer(limit: MemoryTerminalCaptureWriter.maxCapturedBytes)

        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = commandArguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + commandArguments
        }
        process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            FileHandle.standardOutput.write(data)
            capture.appendStdout(data)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            FileHandle.standardError.write(data)
            capture.appendStderr(data)
        }

        try process.run()
        process.waitUntilExit()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil

        let remainingOut = stdout.fileHandleForReading.readDataToEndOfFile()
        if !remainingOut.isEmpty {
            FileHandle.standardOutput.write(remainingOut)
            capture.appendStdout(remainingOut)
        }
        let remainingErr = stderr.fileHandleForReading.readDataToEndOfFile()
        if !remainingErr.isEmpty {
            FileHandle.standardError.write(remainingErr)
            capture.appendStderr(remainingErr)
        }

        let result = capture.result()
        _ = try await MemoryTerminalCaptureWriter().saveRunCapture(
            command: executable,
            arguments: commandArguments,
            cwd: cwd,
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: Int(process.terminationStatus),
            startedAt: startedAt,
            endedAt: Date(),
            truncated: result.truncated
        )
        return Int(process.terminationStatus)
    }

    private static func pipe() async throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        if !data.isEmpty {
            FileHandle.standardOutput.write(data)
        }
        let limit = MemoryTerminalCaptureWriter.maxCapturedBytes
        let truncated = data.count > limit
        let captured = truncated ? data.prefix(limit) : data[...]
        let text = String(data: Data(captured), encoding: .utf8) ?? ""
        _ = try await MemoryTerminalCaptureWriter().savePipeCapture(
            text: text,
            cwd: FileManager.default.currentDirectoryPath,
            truncated: truncated
        )
    }

    private static func history(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.message("Usage: claude-stats-memory history list|search|show")
        }
        let storage = MemorySQLiteStore()
        switch subcommand {
        case "list":
            let records = try await storage.records(limit: 50)
            for record in records where record.kind == .terminalRun || record.kind == .terminalPipe || record.kind == .shellMetadata {
                print("\(record.id)\t\(record.title)\t\(record.exitCode.map(String.init) ?? "-")")
            }
        case "search":
            let query = Array(arguments.dropFirst()).joined(separator: " ")
            guard !query.isEmpty else { throw CLIError.message("Usage: claude-stats-memory history search <query>") }
            let results = try await storage.search(query: query, limit: 30)
            for result in results where result.record.kind == .terminalRun || result.record.kind == .terminalPipe || result.record.kind == .shellMetadata {
                print("\(result.record.id)\t\(result.record.title)\t\(result.block.excerpt)")
            }
        case "show":
            guard let id = arguments.dropFirst().first else {
                throw CLIError.message("Usage: claude-stats-memory history show <record-id>")
            }
            guard let record = try await storage.record(id: id) else {
                throw CLIError.message("No history record found for \(id).")
            }
            print("\(record.title)")
            if let cwd = record.cwd { print("cwd: \(cwd)") }
            if let exitCode = record.exitCode { print("exit: \(exitCode)") }
            let blocks = try await storage.blocks(recordID: id)
            for block in blocks {
                print("\n[\(block.role.rawValue)]")
                print(block.text)
            }
        default:
            throw CLIError.message("Usage: claude-stats-memory history list|search|show")
        }
    }

    private static func shellInit(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError.message("Usage: claude-stats-memory init zsh|bash|show|uninstall")
        }
        let manager = MemoryShellIntegrationManager()
        switch subcommand {
        case "zsh", "bash":
            guard let shell = MemoryShell(rawValue: subcommand) else { return }
            let backup = try manager.install(shell: shell, helperPath: helperPath())
            print(backup.map { "Installed \(shell.rawValue). Backup: \($0.path)" } ?? "\(shell.rawValue) integration already installed.")
        case "show":
            for shell in MemoryShell.allCases {
                let status = manager.status(shell: shell)
                print("\(shell.rawValue): \(status.isInstalled ? "installed" : "not installed") \(status.rcPath)")
            }
        case "uninstall":
            let shells = arguments.dropFirst().compactMap(MemoryShell.init(rawValue:))
            let targets = shells.isEmpty ? MemoryShell.allCases : shells
            for shell in targets {
                let backup = try manager.uninstall(shell: shell)
                print(backup.map { "Uninstalled \(shell.rawValue). Backup: \($0.path)" } ?? "\(shell.rawValue) integration not installed.")
            }
        default:
            throw CLIError.message("Usage: claude-stats-memory init zsh|bash|show|uninstall")
        }
    }

    private static func recordShell(_ arguments: [String]) async throws {
        let options = parseOptions(arguments)
        let shell = options["shell"] ?? "shell"
        let command = options["command"] ?? ""
        let cwd = options["cwd"] ?? FileManager.default.currentDirectoryPath
        let exitCode = Int(options["exit"] ?? "") ?? 0
        let startedAt: Date? = options["started-at"].flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        _ = try await MemoryTerminalCaptureWriter().saveShellMetadata(
            shell: shell,
            command: command,
            cwd: cwd,
            exitCode: exitCode,
            startedAt: startedAt
        )
    }

    private static func parseOptions(_ arguments: [String]) -> [String: String] {
        var options: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--") else {
                index += 1
                continue
            }
            let name = String(key.dropFirst(2))
            let value = index + 1 < arguments.count ? arguments[index + 1] : ""
            options[name] = value
            index += 2
        }
        return options
    }

    private static func helperPath() -> String {
        let raw = CommandLine.arguments.first ?? "claude-stats-memory"
        if raw.hasPrefix("/") { return raw }
        if raw.contains("/") {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(raw)
                .standardizedFileURL
                .path
        }
        return raw
    }

    private static func printUsage() {
        print(
            """
            Usage:
              claude-stats-memory run <command> [args...]
              claude-stats-memory pipe
              claude-stats-memory history list|search|show
              claude-stats-memory init zsh|bash|show|uninstall
            """
        )
    }
}

private enum CLIError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}

private final class ProcessCaptureBuffer: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var truncated = false

    init(limit: Int) {
        self.limit = limit
    }

    func appendStdout(_ data: Data) {
        append(data, toStdout: true)
    }

    func appendStderr(_ data: Data) {
        append(data, toStdout: false)
    }

    func result() -> (stdout: String, stderr: String, truncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (
            String(data: stdout, encoding: .utf8) ?? "",
            String(data: stderr, encoding: .utf8) ?? "",
            truncated
        )
    }

    private func append(_ data: Data, toStdout: Bool) {
        lock.lock()
        defer { lock.unlock() }
        var target = toStdout ? stdout : stderr
        let remaining = max(0, limit - stdout.count - stderr.count)
        if remaining <= 0 {
            truncated = true
        } else if data.count > remaining {
            target.append(data.prefix(remaining))
            truncated = true
        } else {
            target.append(data)
        }
        if toStdout {
            stdout = target
        } else {
            stderr = target
        }
    }
}
