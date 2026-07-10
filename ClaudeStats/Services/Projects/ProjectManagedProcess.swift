import Darwin
import Foundation

enum ProjectManagedProcessEvent: Sendable {
    case output(
        actionID: ProjectLaunchAction.ID,
        runID: UUID,
        stream: ProjectLaunchLogStream,
        text: String
    )
    case terminated(
        actionID: ProjectLaunchAction.ID,
        runID: UUID,
        pid: Int32,
        exitCode: Int32,
        requestedStop: Bool
    )
}

final class ProjectManagedProcess: @unchecked Sendable {
    let runID = UUID()
    let action: ProjectLaunchAction

    private let eventHandler: @Sendable (ProjectManagedProcessEvent) -> Void
    private let lock = NSLock()
    private var process: Process?
    private var requestedStop = false
    private var stopWorkStarted = false
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    init(
        action: ProjectLaunchAction,
        eventHandler: @escaping @Sendable (ProjectManagedProcessEvent) -> Void
    ) {
        self.action = action
        self.eventHandler = eventHandler
    }

    @discardableResult
    func start() throws -> Int32 {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: action.command.executablePath)
        process.arguments = action.command.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: action.workingDirectory, isDirectory: true)
        process.environment = Self.launchEnvironment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.emitAvailableData(from: handle, stream: .stdout)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.emitAvailableData(from: handle, stream: .stderr)
        }
        process.terminationHandler = { [weak self] terminatedProcess in
            self?.finish(terminatedProcess)
        }

        lock.lock()
        self.process = process
        stdoutPipe = stdout
        stderrPipe = stderr
        lock.unlock()

        do {
            try process.run()
            return process.processIdentifier
        } catch {
            cleanupHandlers(stdout: stdout, stderr: stderr, process: process)
            lock.lock()
            self.process = nil
            stdoutPipe = nil
            stderrPipe = nil
            lock.unlock()
            throw error
        }
    }

    func stop() {
        lock.lock()
        requestedStop = true
        guard !stopWorkStarted, let process else {
            lock.unlock()
            return
        }
        stopWorkStarted = true
        let pid = process.processIdentifier
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async {
            Self.terminateProcessTree(rootPID: pid)
        }
    }

    private func emitAvailableData(from handle: FileHandle, stream: ProjectLaunchLogStream) {
        let data = handle.availableData
        guard !data.isEmpty else { return }
        emit(data, stream: stream)
    }

    private func emit(_ data: Data, stream: ProjectLaunchLogStream) {
        guard !data.isEmpty else { return }
        eventHandler(.output(
            actionID: action.id,
            runID: runID,
            stream: stream,
            text: String(decoding: data, as: UTF8.self)
        ))
    }

    private func finish(_ terminatedProcess: Process) {
        let stdout: Pipe?
        let stderr: Pipe?
        let wasRequested: Bool
        lock.lock()
        stdout = stdoutPipe
        stderr = stderrPipe
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        wasRequested = requestedStop
        lock.unlock()

        cleanupHandlers(stdout: stdout, stderr: stderr, process: terminatedProcess)
        if let stdout {
            emit(stdout.fileHandleForReading.readDataToEndOfFile(), stream: .stdout)
        }
        if let stderr {
            emit(stderr.fileHandleForReading.readDataToEndOfFile(), stream: .stderr)
        }

        if wasRequested, let stopCommand = action.stopCommand {
            runStopCommand(stopCommand)
        }

        eventHandler(.terminated(
            actionID: action.id,
            runID: runID,
            pid: terminatedProcess.processIdentifier,
            exitCode: terminatedProcess.terminationStatus,
            requestedStop: wasRequested
        ))
    }

    private func cleanupHandlers(stdout: Pipe?, stderr: Pipe?, process: Process) {
        process.terminationHandler = nil
        stdout?.fileHandleForReading.readabilityHandler = nil
        stderr?.fileHandleForReading.readabilityHandler = nil
    }

    private func runStopCommand(_ command: ProjectLaunchCommand) {
        eventHandler(.output(
            actionID: action.id,
            runID: runID,
            stream: .system,
            text: "\n$ \(command.displayString)\n"
        ))

        let stopProcess = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        stopProcess.executableURL = URL(fileURLWithPath: command.executablePath)
        stopProcess.arguments = command.arguments
        stopProcess.currentDirectoryURL = URL(fileURLWithPath: action.workingDirectory, isDirectory: true)
        stopProcess.environment = Self.launchEnvironment()
        stopProcess.standardInput = FileHandle.nullDevice
        stopProcess.standardOutput = stdout
        stopProcess.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.emitAvailableData(from: handle, stream: .stdout)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.emitAvailableData(from: handle, stream: .stderr)
        }

        do {
            try stopProcess.run()
        } catch {
            emit(Data("Stop command failed: \(error.localizedDescription)\n".utf8), stream: .stderr)
            cleanupHandlers(stdout: stdout, stderr: stderr, process: stopProcess)
            return
        }

        let deadline = Date().addingTimeInterval(30)
        while stopProcess.isRunning, Date() < deadline {
            usleep(50_000)
        }
        if stopProcess.isRunning {
            stopProcess.terminate()
        }
        cleanupHandlers(stdout: stdout, stderr: stderr, process: stopProcess)
        emit(stdout.fileHandleForReading.readDataToEndOfFile(), stream: .stdout)
        emit(stderr.fileHandleForReading.readDataToEndOfFile(), stream: .stderr)
    }

    private static func launchEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        var pathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        pathEntries += [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent(".volta/bin").path,
            home.appendingPathComponent(".asdf/shims").path,
            home.appendingPathComponent(".cargo/bin").path,
            home.appendingPathComponent(".local/share/mise/shims").path,
        ]
        pathEntries += nvmNodeBinDirectories(home: home)
        var seen = Set<String>()
        environment["PATH"] = pathEntries
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
        environment["NO_COLOR"] = environment["NO_COLOR"] ?? "1"
        return environment
    }

    private static func nvmNodeBinDirectories(home: URL) -> [String] {
        let versions = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: versions,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return directories
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { $0.appendingPathComponent("bin", isDirectory: true).path }
    }

    private static func terminateProcessTree(rootPID: Int32) {
        let descendants = descendantPIDs(rootPID: rootPID)
        Darwin.kill(rootPID, SIGTERM)
        for pid in descendants {
            Darwin.kill(pid, SIGTERM)
        }

        for _ in 0..<40 {
            let living = ([rootPID] + descendants).filter(processIsRunning)
            if living.isEmpty { return }
            usleep(50_000)
        }

        for pid in [rootPID] + descendants where processIsRunning(pid) {
            Darwin.kill(pid, SIGKILL)
        }
    }

    private static func descendantPIDs(rootPID: Int32) -> [Int32] {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid="]
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        var childrenByParent: [Int32: [Int32]] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2,
                  let pid = Int32(fields[0]),
                  let parent = Int32(fields[1]) else { continue }
            childrenByParent[parent, default: []].append(pid)
        }

        var result: [Int32] = []
        var pending = childrenByParent[rootPID] ?? []
        while let pid = pending.popLast() {
            result.append(pid)
            pending.append(contentsOf: childrenByParent[pid] ?? [])
        }
        return result
    }

    private static func processIsRunning(_ pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0
    }
}
