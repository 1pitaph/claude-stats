import Foundation
import Testing
@testable import ClaudeStats

@Suite("GitReferenceOperationService")
struct GitReferenceOperationServiceTests {
    @Test("local branch create rename delete and force delete", .enabled(if: GitCommandRunner().isAvailable))
    func branchOperations() async throws {
        let dir = try makeRepo(prefix: "git-ref-branch")
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedInitialCommit(in: dir)

        let repo = GitRepo(rootPath: dir.path)
        let service = GitReferenceOperationService()

        try await service.createBranch(repo: repo, name: "topic", startPoint: "HEAD")
        try await service.renameBranch(repo: repo, oldName: "topic", newName: "topic-renamed")
        #expect(try branches(in: dir).contains("topic-renamed"))
        try await service.deleteBranch(repo: repo, name: "topic-renamed", force: false)
        #expect(try branches(in: dir).contains("topic-renamed") == false)

        try await service.createBranch(repo: repo, name: "unmerged", startPoint: "HEAD")
        try await service.checkoutLocalBranch(repo: repo, name: "unmerged")
        try write("feature\n", to: "feature.txt", in: dir)
        try git(["add", "feature.txt"], in: dir)
        try git(["commit", "-q", "-m", "Feature"], in: dir)
        try await service.checkoutLocalBranch(repo: repo, name: "main")

        do {
            try await service.deleteBranch(repo: repo, name: "unmerged", force: false)
            Issue.record("Expected safe branch delete to fail for an unmerged branch")
        } catch {
            #expect(error is GitReferenceOperationError)
        }

        try await service.deleteBranch(repo: repo, name: "unmerged", force: true)
        #expect(try branches(in: dir).contains("unmerged") == false)
    }

    @Test("tag create delete and detached checkout", .enabled(if: GitCommandRunner().isAvailable))
    func tagOperations() async throws {
        let dir = try makeRepo(prefix: "git-ref-tag")
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedInitialCommit(in: dir)

        let repo = GitRepo(rootPath: dir.path)
        let service = GitReferenceOperationService()

        try await service.createTag(repo: repo, name: "v-test", target: "HEAD")
        #expect(try tags(in: dir).contains("v-test"))
        try await service.checkoutDetached(repo: repo, target: "v-test")
        let branch = try git(["rev-parse", "--abbrev-ref", "HEAD"], in: dir).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(branch == "HEAD")
        try await service.deleteTag(repo: repo, name: "v-test")
        #expect(try tags(in: dir).contains("v-test") == false)
    }

    @Test("dirty checkout failure keeps working tree changes", .enabled(if: GitCommandRunner().isAvailable))
    func dirtyCheckoutFailureDoesNotLoseChanges() async throws {
        let dir = try makeRepo(prefix: "git-ref-dirty")
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedInitialCommit(in: dir)

        try git(["switch", "-c", "other"], in: dir)
        try write("other\n", to: "file.txt", in: dir)
        try git(["commit", "-am", "Other change"], in: dir)
        try git(["switch", "main"], in: dir)
        try write("dirty\n", to: "file.txt", in: dir)

        do {
            try await GitReferenceOperationService().checkoutLocalBranch(repo: GitRepo(rootPath: dir.path), name: "other")
            Issue.record("Expected checkout to fail because dirty file would be overwritten")
        } catch {
            #expect(error is GitReferenceOperationError)
        }

        let contents = try String(contentsOf: dir.appendingPathComponent("file.txt"), encoding: .utf8)
        let status = try git(["status", "--short"], in: dir)
        #expect(contents == "dirty\n")
        #expect(status.contains(" M file.txt"))
    }

    @Test("remote fetch and prune update remote tracking refs", .enabled(if: GitCommandRunner().isAvailable))
    func remoteFetchAndPrune() async throws {
        let root = try emptyDirectory(prefix: "git-ref-remote")
        defer { try? FileManager.default.removeItem(at: root) }

        let remote = root.appendingPathComponent("remote.git")
        let producer = root.appendingPathComponent("producer")
        let consumer = root.appendingPathComponent("consumer")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: producer, withIntermediateDirectories: true)
        try git(["init", "--bare"], in: remote)
        try git(["init", "-q", "-b", "main"], in: producer)
        try configure(producer)
        try git(["remote", "add", "origin", remote.path], in: producer)
        try write("one\n", to: "file.txt", in: producer)
        try git(["add", "file.txt"], in: producer)
        try git(["commit", "-q", "-m", "Initial"], in: producer)
        try git(["push", "-u", "origin", "main"], in: producer)
        try git(["symbolic-ref", "HEAD", "refs/heads/main"], in: remote)
        try git(["switch", "-c", "remote-topic"], in: producer)
        try write("topic\n", to: "topic.txt", in: producer)
        try git(["add", "topic.txt"], in: producer)
        try git(["commit", "-q", "-m", "Remote topic"], in: producer)
        try git(["push", "-u", "origin", "remote-topic"], in: producer)
        try git(["clone", remote.path, consumer.path], in: root)

        let repo = GitRepo(rootPath: consumer.path)
        let service = GitReferenceOperationService()
        var snapshot = GitReferenceService().snapshot(for: repo, reflogLimit: 20)
        #expect(snapshot.remoteGroups["origin"]?.contains { $0.shortName == "origin/remote-topic" } == true)

        try git(["push", "origin", "--delete", "remote-topic"], in: producer)
        try await service.prune(repo: repo, remoteName: "origin")
        snapshot = GitReferenceService().snapshot(for: repo, reflogLimit: 20)
        #expect(snapshot.remoteGroups["origin"]?.contains { $0.shortName == "origin/remote-topic" } != true)

        try git(["switch", "main"], in: producer)
        try git(["switch", "-c", "remote-new"], in: producer)
        try write("new\n", to: "new.txt", in: producer)
        try git(["add", "new.txt"], in: producer)
        try git(["commit", "-q", "-m", "Remote new"], in: producer)
        try git(["push", "-u", "origin", "remote-new"], in: producer)
        try await service.fetch(repo: repo, remoteName: "origin")
        snapshot = GitReferenceService().snapshot(for: repo, reflogLimit: 20)
        #expect(snapshot.remoteGroups["origin"]?.contains { $0.shortName == "origin/remote-new" } == true)
    }

    @Test("remote branch creates local tracking branch", .enabled(if: GitCommandRunner().isAvailable))
    func createLocalTrackingBranch() async throws {
        let root = try emptyDirectory(prefix: "git-ref-track")
        defer { try? FileManager.default.removeItem(at: root) }

        let remote = root.appendingPathComponent("remote.git")
        let producer = root.appendingPathComponent("producer")
        let consumer = root.appendingPathComponent("consumer")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: producer, withIntermediateDirectories: true)
        try git(["init", "--bare"], in: remote)
        try git(["init", "-q", "-b", "main"], in: producer)
        try configure(producer)
        try git(["remote", "add", "origin", remote.path], in: producer)
        try write("one\n", to: "file.txt", in: producer)
        try git(["add", "file.txt"], in: producer)
        try git(["commit", "-q", "-m", "Initial"], in: producer)
        try git(["push", "-u", "origin", "main"], in: producer)
        try git(["symbolic-ref", "HEAD", "refs/heads/main"], in: remote)
        try git(["switch", "-c", "feature/remote"], in: producer)
        try write("feature\n", to: "feature.txt", in: producer)
        try git(["add", "feature.txt"], in: producer)
        try git(["commit", "-q", "-m", "Feature"], in: producer)
        try git(["push", "-u", "origin", "feature/remote"], in: producer)
        try git(["clone", remote.path, consumer.path], in: root)

        try await GitReferenceOperationService().createTrackingBranch(
            repo: GitRepo(rootPath: consumer.path),
            localName: "feature/local",
            remoteShortName: "origin/feature/remote"
        )

        let current = try git(["branch", "--show-current"], in: consumer).trimmingCharacters(in: .whitespacesAndNewlines)
        let upstream = try git(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], in: consumer)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(current == "feature/local")
        #expect(upstream == "origin/feature/remote")
    }
}

private func makeRepo(prefix: String) throws -> URL {
    let dir = try emptyDirectory(prefix: prefix)
    try git(["init", "-q", "-b", "main"], in: dir)
    try configure(dir)
    return dir
}

private func emptyDirectory(prefix: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func seedInitialCommit(in dir: URL) throws {
    try write("one\n", to: "file.txt", in: dir)
    try git(["add", "file.txt"], in: dir)
    try git(["commit", "-q", "-m", "Initial"], in: dir)
}

private func configure(_ dir: URL) throws {
    try git(["config", "user.email", "me@example.com"], in: dir)
    try git(["config", "user.name", "Me"], in: dir)
    try git(["config", "commit.gpgsign", "false"], in: dir)
}

private func branches(in dir: URL) throws -> [String] {
    try git(["branch", "--format=%(refname:short)"], in: dir)
        .split(separator: "\n")
        .map(String.init)
}

private func tags(in dir: URL) throws -> [String] {
    try git(["tag", "--list"], in: dir)
        .split(separator: "\n")
        .map(String.init)
}

private func write(_ text: String, to path: String, in dir: URL) throws {
    try text.write(to: dir.appendingPathComponent(path), atomically: true, encoding: .utf8)
}

@discardableResult
private func git(_ args: [String], in dir: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: GitAnalyzer.gitPath)
    process.arguments = ["-C", dir.path] + args
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    let stdout = out.fileHandleForReading.readDataToEndOfFile()
    let stderr = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(data: combinedOutput(stderr, stdout), encoding: .utf8) ?? "git failed"
        throw GitReferenceOperationTestError.gitFailed(args.joined(separator: " "), message)
    }
    return String(data: stdout, encoding: .utf8) ?? ""
}

private func combinedOutput(_ lhs: Data, _ rhs: Data) -> Data {
    var data = lhs
    data.append(rhs)
    return data
}

private enum GitReferenceOperationTestError: Error, CustomStringConvertible {
    case gitFailed(String, String)

    var description: String {
        switch self {
        case .gitFailed(let command, let output):
            return "\(command) failed: \(output)"
        }
    }
}
