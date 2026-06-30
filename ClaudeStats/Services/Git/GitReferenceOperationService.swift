import Foundation

enum GitReferenceOperationError: Error, LocalizedError, Sendable {
    case gitUnavailable
    case emptyName(String)
    case mergeInProgress
    case rebaseInProgress
    case gitTimedOut(String, logEntryID: String?)
    case gitFailed(summary: String, logEntryID: String?)

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            return "git executable is unavailable."
        case .emptyName(let label):
            return "\(label) is required."
        case .mergeInProgress:
            return "A merge is in progress. Finish it in your git client or terminal before changing refs."
        case .rebaseInProgress:
            return "A rebase is in progress. Finish it in your git client or terminal before changing refs."
        case .gitTimedOut(let command, _):
            return "\(command) timed out."
        case .gitFailed(let summary, _):
            return summary
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

struct GitReferenceOperationService: Sendable {
    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    func checkoutLocalBranch(repo: GitRepo, name: String) async throws {
        let branchName = try normalized(name, label: "Branch name")
        try await runOperation(
            repo: repo,
            arguments: ["-C", repo.rootPath, "switch", branchName],
            commandName: "git switch"
        )
    }

    func checkoutDetached(repo: GitRepo, target: String) async throws {
        let target = try normalized(target, label: "Target")
        try await runOperation(
            repo: repo,
            arguments: ["-C", repo.rootPath, "switch", "--detach", target],
            commandName: "git switch --detach"
        )
    }

    func createBranch(repo: GitRepo, name: String, startPoint: String) async throws {
        let branchName = try normalized(name, label: "Branch name")
        let startPoint = try normalized(startPoint, label: "Start point")
        try await runOperation(
            repo: repo,
            arguments: ["-C", repo.rootPath, "branch", branchName, startPoint],
            commandName: "git branch"
        )
    }

    func createTrackingBranch(repo: GitRepo, localName: String, remoteShortName: String) async throws {
        let branchName = try normalized(localName, label: "Branch name")
        let remoteShortName = try normalized(remoteShortName, label: "Remote branch")
        try await runOperation(
            repo: repo,
            arguments: ["-C", repo.rootPath, "switch", "-c", branchName, "--track", remoteShortName],
            commandName: "git switch --track"
        )
    }

    func renameBranch(repo: GitRepo, oldName: String, newName: String) async throws {
        let oldName = try normalized(oldName, label: "Current branch name")
        let newName = try normalized(newName, label: "New branch name")
        try await runOperation(
            repo: repo,
            arguments: ["-C", repo.rootPath, "branch", "-m", oldName, newName],
            commandName: "git branch -m"
        )
    }

    func deleteBranch(repo: GitRepo, name: String, force: Bool) async throws {
        let branchName = try normalized(name, label: "Branch name")
        try await runOperation(
            repo: repo,
            arguments: ["-C", repo.rootPath, "branch", force ? "-D" : "-d", branchName],
            commandName: force ? "git branch -D" : "git branch -d"
        )
    }

    func createTag(repo: GitRepo, name: String, target: String) async throws {
        let tagName = try normalized(name, label: "Tag name")
        let target = try normalized(target, label: "Target")
        try await runOperation(
            repo: repo,
            arguments: ["-C", repo.rootPath, "tag", tagName, target],
            commandName: "git tag"
        )
    }

    func deleteTag(repo: GitRepo, name: String) async throws {
        let tagName = try normalized(name, label: "Tag name")
        try await runOperation(
            repo: repo,
            arguments: ["-C", repo.rootPath, "tag", "-d", tagName],
            commandName: "git tag -d"
        )
    }

    func fetch(repo: GitRepo, remoteName: String) async throws {
        let remoteName = try normalized(remoteName, label: "Remote name")
        try await runOperation(
            repo: repo,
            arguments: ["-C", repo.rootPath, "fetch", remoteName],
            commandName: "git fetch"
        )
    }

    func prune(repo: GitRepo, remoteName: String) async throws {
        let remoteName = try normalized(remoteName, label: "Remote name")
        try await runOperation(
            repo: repo,
            arguments: ["-C", repo.rootPath, "remote", "prune", remoteName],
            commandName: "git remote prune"
        )
    }

    private func normalized(_ value: String, label: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitReferenceOperationError.emptyName(label) }
        return trimmed
    }

    private func runOperation(
        repo: GitRepo,
        arguments: [String],
        commandName: String,
        timeout: TimeInterval = 180
    ) async throws {
        guard runner.isAvailable else { throw GitReferenceOperationError.gitUnavailable }
        try await Task.detached(priority: .userInitiated) {
            try validateReferenceRepositoryOperationState(repo: repo, runner: runner)
            _ = try runReferenceGitText(arguments, runner: runner, timeout: timeout, commandName: commandName)
        }.value
    }
}

private func validateReferenceRepositoryOperationState(repo: GitRepo, runner: GitCommandRunner) throws {
    let directories = referenceRepositoryStateDirectories(repo: repo, runner: runner)
    let fileManager = FileManager.default

    if directories.contains(where: { directory in
        fileManager.fileExists(atPath: directory.appendingPathComponent("MERGE_HEAD").path)
    }) {
        throw GitReferenceOperationError.mergeInProgress
    }

    if directories.contains(where: { directory in
        fileManager.fileExists(atPath: directory.appendingPathComponent("rebase-apply").path)
            || fileManager.fileExists(atPath: directory.appendingPathComponent("rebase-merge").path)
    }) {
        throw GitReferenceOperationError.rebaseInProgress
    }
}

private func referenceRepositoryStateDirectories(repo: GitRepo, runner: GitCommandRunner) -> [URL] {
    let explicit = [repo.gitDirPath, repo.commonDirPath]
        .compactMap { $0 }
        .map { URL(fileURLWithPath: $0).standardizedFileURL }
    let discovered = ["--git-dir", "--git-common-dir"].compactMap {
        referenceGitDirectory(repo: repo, runner: runner, argument: $0)
    }
    var seen = Set<String>()
    return (explicit + discovered).filter { url in
        let path = url.path
        guard !seen.contains(path) else { return false }
        seen.insert(path)
        return true
    }
}

private func referenceGitDirectory(repo: GitRepo, runner: GitCommandRunner, argument: String) -> URL? {
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

private func runReferenceGitText(
    _ arguments: [String],
    runner: GitCommandRunner,
    timeout: TimeInterval,
    commandName: String
) throws -> String {
    let result = runner.run(arguments, timeout: timeout)
    guard result.succeeded else {
        if result.cancelled { throw CancellationError() }
        let entry = GitOperationLog.recordCommandFailure(commandName: commandName, result: result)
        if result.timedOut {
            throw GitReferenceOperationError.gitTimedOut(commandName, logEntryID: entry.id)
        }
        throw GitReferenceOperationError.gitFailed(summary: entry.summary, logEntryID: entry.id)
    }
    return result.stdout
}
