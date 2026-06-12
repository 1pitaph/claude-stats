import Darwin
import Foundation

struct GitCommandResult: Sendable, Hashable {
    let arguments: [String]
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let timedOut: Bool
    let cancelled: Bool

    var succeeded: Bool { exitCode == 0 && !timedOut && !cancelled }
}

struct GitCommandRunner: Sendable {
    private static let defaultTimeout: TimeInterval = 30
    private let executablePath: String

    init(executablePath: String = GitAnalyzer.gitPath) {
        self.executablePath = executablePath
    }

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executablePath)
    }

    func run(
        _ arguments: [String],
        timeout: TimeInterval = Self.defaultTimeout,
        standardInput: String? = nil
    ) -> GitCommandResult {
        guard !Task.isCancelled else {
            return GitCommandResult(arguments: arguments, stdout: "", stderr: "", exitCode: -1, timedOut: false, cancelled: true)
        }
        guard isAvailable else {
            return GitCommandResult(arguments: arguments, stdout: "", stderr: "git executable is unavailable", exitCode: -1, timedOut: false, cancelled: false)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = standardInput.map { _ in Pipe() }
        let stdoutBuffer = GitCommandOutputBuffer()
        let stderrBuffer = GitCommandOutputBuffer()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stdoutBuffer.append(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stderrBuffer.append(data) }
        }
        process.standardOutput = stdout
        process.standardError = stderr
        if let stdin {
            process.standardInput = stdin
        }

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_PAGER"] = "cat"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["LC_ALL"] = "C"
        process.environment = environment

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
            if let standardInput, let stdin {
                stdin.fileHandleForWriting.write(Data(standardInput.utf8))
                try? stdin.fileHandleForWriting.close()
            }
        } catch {
            process.terminationHandler = nil
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            if let stdin {
                try? stdin.fileHandleForWriting.close()
            }
            return GitCommandResult(
                arguments: arguments,
                stdout: "",
                stderr: error.localizedDescription,
                exitCode: -1,
                timedOut: false,
                cancelled: false
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        var cancelled = false
        while finished.wait(timeout: .now() + 0.05) == .timedOut {
            if Task.isCancelled {
                cancelled = true
                terminate(process, finished: finished)
                break
            }
            if Date() >= deadline {
                timedOut = true
                terminate(process, finished: finished)
                break
            }
        }

        process.terminationHandler = nil
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())

        return GitCommandResult(
            arguments: arguments,
            stdout: stdoutBuffer.stringValue,
            stderr: stderrBuffer.stringValue,
            exitCode: process.terminationStatus,
            timedOut: timedOut,
            cancelled: cancelled
        )
    }

    private func terminate(_ process: Process, finished: DispatchSemaphore) {
        guard process.isRunning else { return }
        process.terminate()
        if finished.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 1)
        }
    }
}

private final class GitCommandOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    var stringValue: String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}
