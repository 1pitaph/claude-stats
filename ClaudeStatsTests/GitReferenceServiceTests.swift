import Foundation
import Testing
@testable import ClaudeStats

@Suite("GitReferenceService")
struct GitReferenceServiceTests {
    private static let fs = "\u{1f}"

    @Test("reference parser marks current branch, skips remote HEAD, tracks upstream counts, and peels annotated tags")
    func parseReferences() throws {
        let f = Self.fs
        let output = [
            ["refs/heads/main", "main", "h-main", "", "origin/main", "refs/remotes/origin/main", ""].joined(separator: f),
            ["refs/heads/feature/topic", "feature/topic", "h-feature", "", "", "", ""].joined(separator: f),
            ["refs/remotes/origin/HEAD", "origin/HEAD", "h-main", "", "", "", ""].joined(separator: f),
            ["refs/remotes/origin/feature/topic", "origin/feature/topic", "h-feature", "", "", "", ""].joined(separator: f),
            ["refs/tags/list/github49", "list/github49", "tag-object", "peeled-commit", "", "", "1780000000"].joined(separator: f),
        ].joined(separator: "\n")

        let refs = GitReferenceService.parseReferences(output, currentBranchName: "main") { branch, upstream in
            branch == "main" && upstream == "origin/main" ? GitReferenceAheadBehind(ahead: 2, behind: 1) : nil
        }

        #expect(refs.count == 4)
        let main = try #require(refs.first { $0.fullName == "refs/heads/main" })
        #expect(main.isCurrent)
        #expect(main.upstreamShortName == "origin/main")
        #expect(main.aheadBehind == GitReferenceAheadBehind(ahead: 2, behind: 1))
        #expect(refs.contains { $0.shortName == "origin/HEAD" } == false)

        let remote = try #require(refs.first { $0.fullName == "refs/remotes/origin/feature/topic" })
        #expect(remote.kind == .remoteBranch)
        #expect(remote.remoteName == "origin")
        #expect(remote.branchName == "feature/topic")

        let tag = try #require(refs.first { $0.fullName == "refs/tags/list/github49" })
        #expect(tag.kind == .tag)
        #expect(tag.targetHash == "peeled-commit")
        #expect(tag.sortTimestamp == 1_780_000_000)
    }

    @Test("remote parser merges fetch and push URLs")
    func parseRemoteInfo() throws {
        let remotes = GitReferenceService.parseRemoteInfo("""
        origin\tgit@example.com:repo.git (fetch)
        origin\tgit@example.com:repo.git (push)
        upstream\thttps://example.com/upstream.git (fetch)
        upstream\tno_push (push)
        """)

        #expect(remotes.map(\.name) == ["origin", "upstream"])
        #expect(remotes.first?.fetchURL == "git@example.com:repo.git")
        #expect(remotes.first?.pushURL == "git@example.com:repo.git")
    }

    @Test("reflog parser keeps duplicate selectors stable and extracts date labels")
    func parseReflogs() throws {
        let f = Self.fs
        let selector = "HEAD@{2026-06-30 10:00:00 +0800}"
        let output = [
            ["abc123", selector, "HEAD@{0}", "checkout: moving from main to feature"].joined(separator: f),
            ["def456", "refs/heads/main@{2026-06-29 09:00:00 +0800}", "main@{1}", "pull --rebase: Fast-forward"].joined(separator: f),
            ["fedcba", selector, "HEAD@{0}", "rebase (finish): returning to refs/heads/main"].joined(separator: f),
        ].joined(separator: "\n")

        let entries = GitReferenceService.parseReflogs(output)

        #expect(entries.count == 3)
        #expect(entries[0].id == selector)
        #expect(entries[0].shortSelector == "HEAD@{0}")
        #expect(entries[0].dateLabel == "2026-06-30 10:00:00 +0800")
        #expect(entries[1].message.contains("pull"))
        #expect(entries[2].id == "\(selector)#1")
    }

    @Test("snapshot reads local branches, remotes, tags and reflogs from a real repo", .enabled(if: GitReferenceService().isAvailable))
    func snapshotReadsRealRepo() throws {
        let dir = try temporaryRepo(prefix: "git-refs-snapshot")
        defer { try? FileManager.default.removeItem(at: dir) }

        try configureRepo(dir)
        try write("one\n", to: "file.txt", in: dir)
        try runGit(["add", "file.txt"], in: dir)
        try runGit(["commit", "-q", "-m", "Initial"], in: dir)
        try runGit(["branch", "feature/list"], in: dir)
        try runGit(["tag", "-a", "list/github49", "-m", "tag"], in: dir)
        try runGit(["remote", "add", "origin", "git@example.com:repo.git"], in: dir)
        let hash = try runGit(["rev-parse", "HEAD"], in: dir).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["update-ref", "refs/remotes/origin/main", hash], in: dir)
        try runGit(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main"], in: dir)

        let snapshot = GitReferenceService().snapshot(for: GitRepo(rootPath: dir.path), reflogLimit: 20)

        #expect(snapshot.currentBranchName == "main")
        #expect(snapshot.localBranches.contains { $0.shortName == "feature/list" })
        #expect(snapshot.remoteGroups["origin"]?.contains { $0.shortName == "origin/main" } == true)
        #expect(snapshot.remoteGroups["origin"]?.contains { $0.shortName == "origin/HEAD" } != true)
        #expect(snapshot.tags.first { $0.shortName == "list/github49" }?.targetHash == hash)
        #expect(snapshot.reflogs.isEmpty == false)
    }

    @Test("snapshot reports detached HEAD", .enabled(if: GitReferenceService().isAvailable))
    func snapshotReportsDetachedHead() throws {
        let dir = try temporaryRepo(prefix: "git-refs-detached")
        defer { try? FileManager.default.removeItem(at: dir) }

        try configureRepo(dir)
        try write("one\n", to: "file.txt", in: dir)
        try runGit(["add", "file.txt"], in: dir)
        try runGit(["commit", "-q", "-m", "Initial"], in: dir)
        let hash = try runGit(["rev-parse", "HEAD"], in: dir).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["checkout", "--detach", "-q", hash], in: dir)

        let snapshot = GitReferenceService().snapshot(for: GitRepo(rootPath: dir.path), reflogLimit: 10)

        #expect(snapshot.isDetachedHead)
        #expect(snapshot.currentBranchName == nil)
        #expect(snapshot.headHash == hash)
    }

    @Test("snapshot sorts tags newest first", .enabled(if: GitReferenceService().isAvailable))
    func snapshotSortsTagsNewestFirst() throws {
        let dir = try temporaryRepo(prefix: "git-refs-tag-order")
        defer { try? FileManager.default.removeItem(at: dir) }

        try configureRepo(dir)
        try write("old\n", to: "file.txt", in: dir)
        try runGit(["add", "file.txt"], in: dir)
        try runGit(["commit", "-q", "-m", "Old"], in: dir, environment: gitDateEnvironment(1_700_000_000))
        try runGit(["tag", "list/github40"], in: dir)

        try write("new\n", to: "file.txt", in: dir)
        try runGit(["commit", "-q", "-am", "New"], in: dir, environment: gitDateEnvironment(1_800_000_000))
        try runGit(["tag", "list/github49"], in: dir)

        let snapshot = GitReferenceService().snapshot(for: GitRepo(rootPath: dir.path), reflogLimit: 10)

        #expect(Array(snapshot.tags.map(\.shortName).prefix(2)) == ["list/github49", "list/github40"])
    }
}

private func temporaryRepo(prefix: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try runGit(["init", "-q", "-b", "main"], in: dir)
    return dir
}

private func configureRepo(_ dir: URL) throws {
    try runGit(["config", "user.email", "me@example.com"], in: dir)
    try runGit(["config", "user.name", "Me"], in: dir)
    try runGit(["config", "commit.gpgsign", "false"], in: dir)
}

private func write(_ text: String, to path: String, in dir: URL) throws {
    try text.write(to: dir.appendingPathComponent(path), atomically: true, encoding: .utf8)
}

@discardableResult
private func runGit(_ args: [String], in dir: URL, environment: [String: String] = [:]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: GitAnalyzer.gitPath)
    process.arguments = ["-C", dir.path] + args
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    let stdout = out.fileHandleForReading.readDataToEndOfFile()
    let stderr = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(data: combined(stderr, stdout), encoding: .utf8) ?? "git failed"
        throw GitReferenceTestError.gitFailed(args.joined(separator: " "), message)
    }
    return String(data: stdout, encoding: .utf8) ?? ""
}

private func gitDateEnvironment(_ timestamp: Int) -> [String: String] {
    let value = "@\(timestamp)"
    return [
        "GIT_AUTHOR_DATE": value,
        "GIT_COMMITTER_DATE": value,
    ]
}

private func combined(_ lhs: Data, _ rhs: Data) -> Data {
    var data = lhs
    data.append(rhs)
    return data
}

private enum GitReferenceTestError: Error, CustomStringConvertible {
    case gitFailed(String, String)

    var description: String {
        switch self {
        case .gitFailed(let command, let output):
            return "\(command) failed: \(output)"
        }
    }
}
