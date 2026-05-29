import Darwin
import Foundation

struct LocalAIHelperManager: Sendable {
    var helperPath: String
    var configURL: URL
    var pidURL: URL
    var metaURL: URL

    init(
        helperPath: String = Self.defaultHelperPath(),
        configURL: URL = LocalAIPaths.helperRuntimeConfigURL(),
        pidURL: URL = LocalAIPaths.helperPIDURL(),
        metaURL: URL = LocalAIPaths.helperMetaURL()
    ) {
        self.helperPath = helperPath
        self.configURL = configURL
        self.pidURL = pidURL
        self.metaURL = metaURL
    }

    static func defaultHelperPath(bundle: Bundle = .main) -> String {
        bundledHelperPath(bundle: bundle) ?? "claude-stats-local-ai"
    }

    static func bundledHelperPath(bundle: Bundle = .main) -> String? {
        let path = bundle.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("claude-stats-local-ai", isDirectory: false)
            .path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    @discardableResult
    func start(config: LocalAIHelperRuntimeConfig) throws -> LocalAIOpenAIEndpoint {
        try config.write(to: configURL)

        if let pid = try? readPID(), processIsRunning(pid) {
            if existingProcessCanServe(config: config) {
                try writeMeta(pid: pid, config: config)
                return LocalAIOpenAIEndpoint(baseURL: config.baseURL, token: config.token)
            }
            terminateProcess(pid)
            try? FileManager.default.removeItem(at: pidURL)
            try? FileManager.default.removeItem(at: metaURL)
        } else {
            try? FileManager.default.removeItem(at: pidURL)
            try? FileManager.default.removeItem(at: metaURL)
        }

        if existingProcessCanServe(config: config) {
            return LocalAIOpenAIEndpoint(baseURL: config.baseURL, token: config.token)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = ["serve", "--config", configURL.path]
        if let devNull = FileHandle(forWritingAtPath: "/dev/null") {
            process.standardOutput = devNull
            process.standardError = devNull
        }
        try FileManager.default.createDirectory(at: pidURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try process.run()
        let pid = process.processIdentifier
        try "\(pid)\n".write(to: pidURL, atomically: true, encoding: .utf8)
        try writeMeta(pid: pid, config: config)

        for _ in 0..<40 {
            if existingProcessCanServe(config: config) {
                return LocalAIOpenAIEndpoint(baseURL: config.baseURL, token: config.token)
            }
            usleep(50_000)
        }

        terminateProcess(pid)
        try? FileManager.default.removeItem(at: pidURL)
        throw LocalAIHelperError.healthCheckFailed("Local AI helper did not become healthy at \(config.healthURL.absoluteString).")
    }

    func stop() throws -> Bool {
        guard let pid = try? readPID(), processIsRunning(pid) else {
            try? FileManager.default.removeItem(at: pidURL)
            try? FileManager.default.removeItem(at: metaURL)
            return false
        }
        terminateProcess(pid)
        try? FileManager.default.removeItem(at: pidURL)
        try? FileManager.default.removeItem(at: metaURL)
        return true
    }

    func health(config: LocalAIHelperRuntimeConfig) -> [String: String]? {
        guard let body = httpBody(url: config.healthURL),
              let data = body.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        return decoded
    }

    func existingProcessCanServe(config: LocalAIHelperRuntimeConfig) -> Bool {
        guard let health = health(config: config) else { return false }
        return health["config_hash"] == config.configHash
            && health["schema_version"] == "\(config.schemaVersion)"
    }

    private func readPID() throws -> Int32 {
        let raw = try String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(raw) else { throw LocalAIHelperError.invalidPID(raw) }
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

    private func writeMeta(pid: Int32, config: LocalAIHelperRuntimeConfig) throws {
        let meta = LocalAIHelperLaunchMeta(pid: pid, configHash: config.configHash, port: config.port)
        try FileManager.default.createDirectory(at: metaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.localAIHelperEncoder.encode(meta).write(to: metaURL, options: [.atomic])
    }

    private func httpBody(url: URL) -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        let semaphore = DispatchSemaphore(value: 0)
        let box = LocalAIHelperHTTPBox()
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let body = data.flatMap { String(data: $0, encoding: .utf8) }
            box.set(statusCode: statusCode, body: body)
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 0.6) == .timedOut {
            task.cancel()
            return nil
        }
        guard box.statusCode == 200 else { return nil }
        return box.body
    }
}

enum LocalAIHelperError: Error, LocalizedError {
    case invalidPID(String)
    case healthCheckFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPID(let raw):
            "Invalid Local AI helper PID: \(raw)"
        case .healthCheckFailed(let message):
            message
        }
    }
}

private struct LocalAIHelperLaunchMeta: Codable {
    var pid: Int32
    var configHash: String
    var port: UInt16
}

private final class LocalAIHelperHTTPBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _statusCode: Int?
    private var _body: String?

    var statusCode: Int? {
        lock.lock()
        defer { lock.unlock() }
        return _statusCode
    }

    var body: String? {
        lock.lock()
        defer { lock.unlock() }
        return _body
    }

    func set(statusCode: Int?, body: String?) {
        lock.lock()
        _statusCode = statusCode
        _body = body
        lock.unlock()
    }
}
