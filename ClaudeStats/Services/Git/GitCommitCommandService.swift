import Foundation

struct GitWorkingTreeCommitResult: Sendable, Hashable {
    let hash: String
    let subject: String
    let pushTarget: GitPushTarget?

    var shortHash: String { String(hash.prefix(7)) }
}

struct GitPushResult: Sendable, Hashable {
    let target: GitPushTarget
    let output: String
}

struct GitPushTarget: Sendable, Hashable {
    enum Mode: Sendable, Hashable {
        case upstream
        case publishBranch
    }

    let mode: Mode
    let remoteName: String?
    let branchName: String?

    var buttonLabel: String {
        switch mode {
        case .upstream:
            if let remoteName, !remoteName.isEmpty {
                return "Push \(remoteName)"
            }
            return "Push"
        case .publishBranch:
            return "Publish Branch"
        }
    }
}

enum GitCommitCommandError: Error, LocalizedError, Sendable {
    case gitUnavailable
    case emptyMessage
    case staleDiff
    case conflictedWorkingTree
    case mergeInProgress
    case rebaseInProgress
    case gitTimedOut(String, logEntryID: String?)
    case gitFailed(summary: String, logEntryID: String?)
    case missingHead
    case missingPushTarget

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            return "git executable is unavailable."
        case .emptyMessage:
            return "The generated commit message is empty."
        case .staleDiff:
            return "Working tree changes changed after this message was generated. Refresh the message before committing."
        case .conflictedWorkingTree:
            return "Resolve working tree conflicts before committing."
        case .mergeInProgress:
            return "A merge is in progress. Finish it in your git client or terminal before committing from this panel."
        case .rebaseInProgress:
            return "A rebase is in progress. Finish it in your git client or terminal before committing from this panel."
        case .gitTimedOut(let command, _):
            return "\(command) timed out."
        case .gitFailed(let summary, _):
            return summary
        case .missingHead:
            return "The commit was created, but git did not return the new HEAD."
        case .missingPushTarget:
            return "No remote push target is configured for the current branch."
        }
    }

    var logEntryID: String? {
        switch self {
        case .gitTimedOut(_, let logEntryID), .gitFailed(_, let logEntryID):
            return logEntryID
        default:
            return nil
        }
    }
}

struct GitCommitCommandService: Sendable {
    private let runner: GitCommandRunner
    private let snapshotBuilder: GitCommitMessageSnapshotBuilder

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
        self.snapshotBuilder = GitCommitMessageSnapshotBuilder(runner: runner)
    }

    func commitAllWorkingTreeChanges(
        repo: GitRepo,
        result: GitCommitMessageResult
    ) async throws -> GitWorkingTreeCommitResult {
        guard runner.isAvailable else { throw GitCommitCommandError.gitUnavailable }

        let message = result.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw GitCommitCommandError.emptyMessage }

        let snapshot = try await snapshotBuilder.snapshot(for: .workingTree, repo: repo)
        guard snapshot.diffHash == result.diffHash else { throw GitCommitCommandError.staleDiff }
        guard !snapshot.files.contains(where: { $0.status == .conflicted }) else {
            throw GitCommitCommandError.conflictedWorkingTree
        }

        return try await Task.detached(priority: .userInitiated) {
            try validateRepositoryOperationState(repo: repo, runner: runner)
            return try runCommit(repo: repo, message: message, runner: runner)
        }.value
    }

    func pushCommittedChanges(repo: GitRepo, target: GitPushTarget) async throws -> GitPushResult {
        guard runner.isAvailable else { throw GitCommitCommandError.gitUnavailable }
        return try await Task.detached(priority: .userInitiated) {
            try validateRepositoryOperationState(repo: repo, runner: runner)
            let output = try runPush(repo: repo, target: target, runner: runner)
            return GitPushResult(target: target, output: output)
        }.value
    }
}

private func validateRepositoryOperationState(repo: GitRepo, runner: GitCommandRunner) throws {
    let directories = repositoryStateDirectories(repo: repo, runner: runner)
    let fileManager = FileManager.default

    if directories.contains(where: { directory in
        fileManager.fileExists(atPath: directory.appendingPathComponent("MERGE_HEAD").path)
    }) {
        throw GitCommitCommandError.mergeInProgress
    }

    if directories.contains(where: { directory in
        fileManager.fileExists(atPath: directory.appendingPathComponent("rebase-apply").path)
            || fileManager.fileExists(atPath: directory.appendingPathComponent("rebase-merge").path)
    }) {
        throw GitCommitCommandError.rebaseInProgress
    }
}

private func repositoryStateDirectories(repo: GitRepo, runner: GitCommandRunner) -> [URL] {
    let explicit = [repo.gitDirPath, repo.commonDirPath]
        .compactMap { $0 }
        .map { URL(fileURLWithPath: $0).standardizedFileURL }
    let discovered = ["--git-dir", "--git-common-dir"].compactMap {
        gitDirectory(repo: repo, runner: runner, argument: $0)
    }
    var seen = Set<String>()
    return (explicit + discovered).filter { url in
        let path = url.path
        guard !seen.contains(path) else { return false }
        seen.insert(path)
        return true
    }
}

private func gitDirectory(repo: GitRepo, runner: GitCommandRunner, argument: String) -> URL? {
    let result = runner.run(["-C", repo.rootPath, "rev-parse", argument], timeout: 15)
    guard result.succeeded else { return nil }
    let rawPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawPath.isEmpty else { return nil }
    if rawPath.hasPrefix("/") {
        return URL(fileURLWithPath: rawPath).standardizedFileURL
    }
    return URL(fileURLWithPath: repo.rootPath)
        .appendingPathComponent(rawPath)
        .standardizedFileURL
}

private func runCommit(repo: GitRepo, message: String, runner: GitCommandRunner) throws -> GitWorkingTreeCommitResult {
    try runGit(["-C", repo.rootPath, "add", "-A"], runner: runner, timeout: 60, commandName: "git add -A")
    let commitInput = message.hasSuffix("\n") ? message : message + "\n"
    try runGit(
        ["-C", repo.rootPath, "commit", "-F", "-"],
        runner: runner,
        timeout: 180,
        commandName: "git commit",
        standardInput: commitInput
    )
    let hash = try runGitText(["-C", repo.rootPath, "rev-parse", "--verify", "HEAD"], runner: runner, timeout: 15, commandName: "git rev-parse")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !hash.isEmpty else { throw GitCommitCommandError.missingHead }
    let subject = (try? runGitText(
        ["-C", repo.rootPath, "log", "-1", "--pretty=format:%s"],
        runner: runner,
        timeout: 15,
        commandName: "git log",
        logFailures: false
    ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return GitWorkingTreeCommitResult(hash: hash, subject: subject, pushTarget: resolvePushTarget(repo: repo, runner: runner))
}

private func runPush(repo: GitRepo, target: GitPushTarget, runner: GitCommandRunner) throws -> String {
    let arguments: [String]
    switch target.mode {
    case .upstream:
        arguments = ["-C", repo.rootPath, "push"]
    case .publishBranch:
        guard let remoteName = target.remoteName, let branchName = target.branchName else {
            throw GitCommitCommandError.missingPushTarget
        }
        arguments = ["-C", repo.rootPath, "push", "-u", remoteName, branchName]
    }
    return try runGitText(arguments, runner: runner, timeout: 180, commandName: "git push")
}

private func resolvePushTarget(repo: GitRepo, runner: GitCommandRunner) -> GitPushTarget? {
    if let upstream = try? runGitText(
        ["-C", repo.rootPath, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
        runner: runner,
        timeout: 15,
        commandName: "git rev-parse",
        logFailures: false
    ).trimmingCharacters(in: .whitespacesAndNewlines),
       !upstream.isEmpty {
        return GitPushTarget(
            mode: .upstream,
            remoteName: upstreamRemoteName(from: upstream),
            branchName: nil
        )
    }

    guard let branch = try? runGitText(
        ["-C", repo.rootPath, "branch", "--show-current"],
        runner: runner,
        timeout: 15,
        commandName: "git branch",
        logFailures: false
    ).trimmingCharacters(in: .whitespacesAndNewlines),
          !branch.isEmpty
    else {
        return nil
    }

    let remotes = ((try? runGitText(
        ["-C", repo.rootPath, "remote"],
        runner: runner,
        timeout: 15,
        commandName: "git remote",
        logFailures: false
    )) ?? "")
        .split(separator: "\n")
        .map(String.init)
        .filter { !$0.isEmpty }
    guard let remoteName = remotes.contains("origin") ? "origin" : remotes.first else { return nil }
    return GitPushTarget(mode: .publishBranch, remoteName: remoteName, branchName: branch)
}

private func upstreamRemoteName(from upstream: String) -> String? {
    guard let slash = upstream.firstIndex(of: "/") else { return nil }
    let remote = String(upstream[..<slash]).trimmingCharacters(in: .whitespacesAndNewlines)
    return remote.isEmpty ? nil : remote
}

private func runGit(
    _ arguments: [String],
    runner: GitCommandRunner,
    timeout: TimeInterval,
    commandName: String,
    standardInput: String? = nil,
    logFailures: Bool = true
) throws {
    _ = try runGitText(
        arguments,
        runner: runner,
        timeout: timeout,
        commandName: commandName,
        standardInput: standardInput,
        logFailures: logFailures
    )
}

private func runGitText(
    _ arguments: [String],
    runner: GitCommandRunner,
    timeout: TimeInterval,
    commandName: String,
    standardInput: String? = nil,
    logFailures: Bool = true
) throws -> String {
    let result = runner.run(arguments, timeout: timeout, standardInput: standardInput)
    guard result.succeeded else {
        if result.cancelled { throw CancellationError() }
        if logFailures {
            let entry = GitOperationLog.recordCommandFailure(commandName: commandName, result: result)
            if result.timedOut {
                throw GitCommitCommandError.gitTimedOut(commandName, logEntryID: entry.id)
            }
            throw GitCommitCommandError.gitFailed(summary: entry.summary, logEntryID: entry.id)
        }
        if result.timedOut {
            throw GitCommitCommandError.gitTimedOut(commandName, logEntryID: nil)
        }
        throw GitCommitCommandError.gitFailed(
            summary: gitFailureMessage(result, fallback: "\(commandName) failed."),
            logEntryID: nil
        )
    }
    return result.stdout
}

private func gitFailureMessage(_ result: GitCommandResult, fallback: String) -> String {
    let detail = [result.stderr, result.stdout]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return detail.isEmpty ? fallback : detail
}
