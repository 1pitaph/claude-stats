import Darwin
import Foundation

struct CodeMemorySidecarConfiguration: Sendable, Hashable {
    var host: String = "127.0.0.1"
    var port: Int = 8765
    var rootDirectory: URL = MemoryPaths.rootDirectory()

    var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }
}

struct CodeMemorySidecarManager: Sendable {
    var configuration: CodeMemorySidecarConfiguration = CodeMemorySidecarConfiguration()
    var pidURL: URL = MemoryPaths.sidecarPIDURL()

    static func defaultHelperPath(bundle: Bundle = .main) -> String {
        if let bundled = bundledHelperPath(bundle: bundle) {
            return bundled
        }
        return "claude-stats-memory"
    }

    static func bundledHelperPath(bundle: Bundle = .main) -> String? {
        let bundled = bundle.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("claude-stats-memory", isDirectory: false)
            .path
        return FileManager.default.isExecutableFile(atPath: bundled) ? bundled : nil
    }

    static func shellCommand(arguments: [String], bundle: Bundle = .main) -> String {
        ([defaultHelperPath(bundle: bundle)] + arguments)
            .map(shellQuoted)
            .joined(separator: " ")
    }

    static func shellQuoted(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-=/:.,")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func status() async -> String {
        do {
            let health = try await CodeMemoryHTTPClient(baseURL: configuration.baseURL).health()
            return "running \(health.status) events=\(health.eventCount) memories=\(health.memoryCount)"
        } catch {
            if let pid = try? readPID(), processIsRunning(pid) {
                return "process \(pid) is running but HTTP health failed: \(error.localizedDescription)"
            }
            return "stopped"
        }
    }

    func start(helperPath: String) throws -> Int32 {
        if let pid = try? readPID(), processIsRunning(pid) {
            return pid
        }

        let sidecarPath = resolveSidecarPath(helperPath: helperPath)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            "-m",
            "memoryd",
            "serve",
            "--root",
            configuration.rootDirectory.path,
            "--host",
            configuration.host,
            "--port",
            "\(configuration.port)",
        ]
        var environment = ProcessInfo.processInfo.environment
        let existing = environment["PYTHONPATH"]
        environment["PYTHONPATH"] = existing.map { "\(sidecarPath.path):\($0)" } ?? sidecarPath.path
        process.environment = environment
        if let devNull = FileHandle(forWritingAtPath: "/dev/null") {
            process.standardOutput = devNull
            process.standardError = devNull
        }
        try FileManager.default.createDirectory(at: pidURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try process.run()
        let pid = process.processIdentifier
        try "\(pid)\n".write(to: pidURL, atomically: true, encoding: .utf8)
        return pid
    }

    func stop() throws -> Bool {
        guard let pid = try? readPID(), processIsRunning(pid) else {
            try? FileManager.default.removeItem(at: pidURL)
            return false
        }
        Darwin.kill(pid, SIGTERM)
        try? FileManager.default.removeItem(at: pidURL)
        return true
    }

    private func readPID() throws -> Int32 {
        let raw = try String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(raw) else { throw CodeMemorySidecarError.invalidPID(raw) }
        return pid
    }

    private func processIsRunning(_ pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0
    }

    private func resolveSidecarPath(helperPath: String) -> URL {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_STATS_MEMORYD_PATH"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("MemorySidecar", isDirectory: true)
        if FileManager.default.fileExists(atPath: cwd.appendingPathComponent("memoryd", isDirectory: true).path) {
            return cwd
        }
        let helper = URL(fileURLWithPath: helperPath)
        let bundleSidecar = helper
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("MemorySidecar", isDirectory: true)
        return bundleSidecar
    }
}

enum CodeMemorySidecarError: Error, LocalizedError {
    case invalidPID(String)

    var errorDescription: String? {
        switch self {
        case .invalidPID(let raw):
            "Invalid memoryd pid: \(raw)"
        }
    }
}

struct CodeMemoryTerminalRecorder: Sendable {
    var client: CodeMemoryHTTPClient = CodeMemoryHTTPClient()

    func record(
        title: String,
        body: String,
        kind: MemoryRecordKind,
        cwd: String?,
        ref: String,
        sourceKind: String = "terminal_capture"
    ) async -> Bool {
        let projectID = projectID(cwd: cwd)
        let event = CodeMemoryEventInput(
            projectID: projectID,
            eventType: "memory.observed",
            actor: ["kind": "tool", "id": "claude-stats-memory"],
            after: CodeMemoryNewMemory(
                projectID: projectID,
                title: title,
                body: body,
                type: kind == .shellMetadata ? "fact" : "workflow",
                scope: CodeMemoryNewScope(kind: "project", key: projectID, title: cwd),
                sourceRefs: [["kind": sourceKind, "uri": ref]]
            ),
            sourceRefs: [["kind": sourceKind, "uri": ref]]
        )
        do {
            try await client.recordEvent(event)
            return true
        } catch {
            return false
        }
    }

    private func projectID(cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "terminal" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "terminal" : name
    }
}
