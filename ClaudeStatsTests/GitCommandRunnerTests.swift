import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git command runner")
struct GitCommandRunnerTests {
    @Test("Runner disables optional git locks for read-only queries")
    func runnerDisablesOptionalLocks() {
        let runner = GitCommandRunner(executablePath: "/bin/sh")

        let result = runner.run(["-c", "printf '%s' \"$GIT_OPTIONAL_LOCKS\""])

        #expect(result.succeeded)
        #expect(result.stdout == "0")
    }

    @Test("Runner writes supplied standard input")
    func runnerWritesStandardInput() {
        let runner = GitCommandRunner(executablePath: "/bin/sh")

        let result = runner.run(["-c", "cat"], standardInput: "hello\nstdin\n")

        #expect(result.succeeded)
        #expect(result.stdout == "hello\nstdin\n")
    }

    @Test("Runner returns a bounded timeout result")
    func timeoutTerminatesProcess() {
        let runner = GitCommandRunner(executablePath: "/bin/sh")
        let start = Date()

        let result = runner.run(["-c", "printf hello; exec sleep 5"], timeout: 0.15)

        #expect(result.timedOut)
        #expect(!result.cancelled)
        #expect(!result.succeeded)
        #expect(result.stdout == "hello")
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test("Runner terminates the process when its task is cancelled")
    func cancellationTerminatesProcess() async throws {
        let runner = GitCommandRunner(executablePath: "/bin/sh")
        let task = Task.detached {
            runner.run(["-c", "exec sleep 5"], timeout: 10)
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.value

        #expect(result.cancelled)
        #expect(!result.timedOut)
        #expect(!result.succeeded)
    }
}
