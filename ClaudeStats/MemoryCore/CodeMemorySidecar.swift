import Darwin
import Foundation

struct CodeMemoryLocalAIEnvironment: Sendable, Hashable {
    var baseURL: URL
    var token: String
    var llmModelID: String
    var embeddingModelID: String
    var embeddingDimensions: Int
    var adaptersEnabled: Bool
}

struct CodeMemorySidecarConfiguration: Sendable, Hashable {
    var host: String = "127.0.0.1"
    var port: Int = 8765
    var rootDirectory: URL = MemoryPaths.rootDirectory()
    var localAI: CodeMemoryLocalAIEnvironment?

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
            if existingProcessCanServeCurrentContract() {
                return pid
            }
            terminateProcess(pid)
            try? FileManager.default.removeItem(at: pidURL)
        }

        let resolvedPaths = resolvePythonPaths(helperPath: helperPath)
        let process = Process()
        process.executableURL = pythonExecutable()
        process.arguments = [
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
        let pythonPath = resolvedPaths.map(\.path).joined(separator: ":")
        environment["PYTHONPATH"] = existing.map { "\(pythonPath):\($0)" } ?? pythonPath
        environment["MEM0_TELEMETRY"] = "false"
        environment["GRAPHITI_TELEMETRY_ENABLED"] = "false"
        if let localAI = configuration.localAI {
            environment["CLAUDE_STATS_LOCAL_AI_BASE_URL"] = localAI.baseURL.absoluteString
            environment["CLAUDE_STATS_LOCAL_AI_TOKEN"] = localAI.token
            environment["CLAUDE_STATS_LOCAL_LLM_MODEL"] = localAI.llmModelID
            environment["CLAUDE_STATS_LOCAL_EMBEDDING_MODEL"] = localAI.embeddingModelID
            environment["CLAUDE_STATS_LOCAL_EMBEDDING_DIMS"] = "\(localAI.embeddingDimensions)"
            environment["CLAUDE_STATS_MEM0_ENABLED"] = localAI.adaptersEnabled ? "1" : "0"
            environment["CLAUDE_STATS_GRAPHITI_ENABLED"] = localAI.adaptersEnabled ? "1" : "0"
        }
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

    private func terminateProcess(_ pid: Int32) {
        Darwin.kill(pid, SIGTERM)
        for _ in 0..<20 {
            if !processIsRunning(pid) { return }
            usleep(50_000)
        }
        Darwin.kill(pid, SIGKILL)
    }

    private func existingProcessCanServeCurrentContract() -> Bool {
        guard httpStatus(path: "/health") == 200 else { return false }
        guard httpStatus(path: "/v1/modules") == 200 else { return false }
        guard httpStatus(path: "/v1/memories/proposals") == 200 else { return false }
        if configuration.localAI?.adaptersEnabled == true {
            guard let healthBody = httpBody(path: "/health") else { return false }
            let missingAdapterMarkers = [
                "No module named 'mem0'",
                "No module named \"mem0\"",
                "No module named 'graphiti_core'",
                "No module named \"graphiti_core\"",
                "validation error for GraphitiClients",
            ]
            if missingAdapterMarkers.contains(where: { healthBody.contains($0) }) {
                return false
            }
        }
        return true
    }

    private func httpStatus(path: String) -> Int? {
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = configuration.baseURL.appendingPathComponent(trimmedPath)
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.4

        let semaphore = DispatchSemaphore(value: 0)
        let statusBox = CodeMemoryHTTPStatusBox()
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            statusBox.set((response as? HTTPURLResponse)?.statusCode)
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 0.5) == .timedOut {
            task.cancel()
            return nil
        }
        return statusBox.value
    }

    private func httpBody(path: String) -> String? {
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = configuration.baseURL.appendingPathComponent(trimmedPath)
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.4

        let semaphore = DispatchSemaphore(value: 0)
        let bodyBox = CodeMemoryHTTPBodyBox()
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let body = data.flatMap { String(data: $0, encoding: .utf8) }
            bodyBox.set(statusCode: statusCode, body: body)
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 0.5) == .timedOut {
            task.cancel()
            return nil
        }
        guard bodyBox.statusCode == 200 else { return nil }
        return bodyBox.body
    }

    private func pythonExecutable() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["CLAUDE_STATS_MEMORYD_PYTHON"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        let venvPython = configuration.rootDirectory
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: venvPython.path) {
            return venvPython
        }

        let homebrewPython = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
        if FileManager.default.isExecutableFile(atPath: homebrewPython.path) {
            return homebrewPython
        }

        return URL(fileURLWithPath: "/usr/bin/python3")
    }

    private func resolvePythonPaths(helperPath: String) -> [URL] {
        let sidecarPath = resolveSidecarPath(helperPath: helperPath)
        let repoRoot = sidecarPath.deletingLastPathComponent()
        let thirdParty = repoRoot.appendingPathComponent("ThirdParty", isDirectory: true)
        var paths = [sidecarPath]
        for child in ["mem0", "graphiti"] {
            let url = thirdParty.appendingPathComponent(child, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                paths.append(url)
            }
        }
        return paths
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

private final class CodeMemoryHTTPStatusBox: @unchecked Sendable {
    private let lock = NSLock()
    private var statusCode: Int?

    var value: Int? {
        lock.withLock { statusCode }
    }

    func set(_ nextStatusCode: Int?) {
        lock.withLock {
            statusCode = nextStatusCode
        }
    }
}

private final class CodeMemoryHTTPBodyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var responseStatusCode: Int?
    private var responseBody: String?

    var statusCode: Int? {
        lock.withLock { responseStatusCode }
    }

    var body: String? {
        lock.withLock { responseBody }
    }

    func set(statusCode nextStatusCode: Int?, body nextBody: String?) {
        lock.withLock {
            responseStatusCode = nextStatusCode
            responseBody = nextBody
        }
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
    var recordHandler: (@Sendable (CodeMemoryEventInput) async -> Bool)?

    init(
        client: CodeMemoryHTTPClient = CodeMemoryHTTPClient(),
        recordHandler: (@Sendable (CodeMemoryEventInput) async -> Bool)? = nil
    ) {
        self.client = client
        self.recordHandler = recordHandler
    }

    func record(_ event: CodeMemoryEventInput) async -> Bool {
        if let recordHandler {
            return await recordHandler(event)
        }
        do {
            try await client.recordEvent(event)
            return true
        } catch {
            return false
        }
    }

    func record(
        title: String,
        body: String,
        kind: MemoryRecordKind,
        cwd: String?,
        ref: String,
        sourceKind: String = "terminal_capture"
    ) async -> Bool {
        await record(
            event(
                title: title,
                body: body,
                kind: kind,
                cwd: cwd,
                ref: ref,
                sourceKind: sourceKind
            )
        )
    }

    func event(
        title: String,
        body: String,
        kind: MemoryRecordKind,
        cwd: String?,
        ref: String,
        sourceKind: String = "terminal_capture"
    ) -> CodeMemoryEventInput {
        let projectID = projectID(cwd: cwd)
        return CodeMemoryEventInput(
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
    }

    private func projectID(cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "terminal" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "terminal" : name
    }
}
