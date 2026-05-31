import CryptoKit
import Foundation

enum GitSummarySnapshotBuilderError: Error, LocalizedError, Sendable {
    case gitFailed(String)
    case emptyDiff

    var errorDescription: String? {
        switch self {
        case .gitFailed(let message): message
        case .emptyDiff: "There is no diff to summarize."
        }
    }
}

struct GitSummarySnapshotBuilder: Sendable {
    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    func snapshot(for target: GitSummaryTarget, repo: GitRepo) async throws -> GitSummarySnapshot {
        try await Task.detached(priority: .utility) {
            try buildSnapshot(for: target, repo: repo)
        }.value
    }

    private func buildSnapshot(for target: GitSummaryTarget, repo: GitRepo) throws -> GitSummarySnapshot {
        switch target {
        case .commit(let hash, let subject):
            let diff = try runGit(["-C", repo.rootPath, "show", "--format=", "--no-color", "--find-renames", "--find-copies", hash], timeout: 45)
            let numstat = try runGit(["-C", repo.rootPath, "show", "--numstat", "--format=", "--no-color", "--find-renames", "--find-copies", hash], timeout: 30)
            let metadata = try? runGit(["-C", repo.rootPath, "show", "--no-patch", "--pretty=format:%s%x1f%b", hash], timeout: 15)
            let parsedMetadata = parseCommitMetadata(metadata ?? "")
            let files = Self.fileChanges(diffText: diff, numstat: numstat, workingTree: nil)
            guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty else {
                throw GitSummarySnapshotBuilderError.emptyDiff
            }
            let body = parsedMetadata.body
            let targetSubject = subject ?? parsedMetadata.subject
            let hashInput = Self.hashInput(diff: diff, files: files, snippets: [])
            return GitSummarySnapshot(
                repo: repo,
                target: target,
                targetSubject: targetSubject,
                body: body,
                diffText: diff,
                files: files,
                untrackedSnippets: [],
                diffHash: Self.sha256(hashInput)
            )

        case .workingTree:
            let diff = try runGit(["-C", repo.rootPath, "diff", "HEAD", "--no-color", "--find-renames", "--find-copies"], timeout: 45)
            let numstat = (try? runGit(["-C", repo.rootPath, "diff", "--numstat", "HEAD", "--no-color"], timeout: 30)) ?? ""
            let status = (try? runGit(["-C", repo.rootPath, "status", "--porcelain=v1", "-z"], timeout: 15)) ?? ""
            let workingTree = GitAnalyzer.parseWorkingTreeStatusZ(status)
            let snippets = Self.untrackedSnippets(repo: repo, changes: workingTree.changes)
            let files = Self.fileChanges(diffText: diff, numstat: numstat, workingTree: workingTree, snippets: snippets)
            guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !snippets.isEmpty || !files.isEmpty else {
                throw GitSummarySnapshotBuilderError.emptyDiff
            }
            let hashInput = Self.hashInput(diff: diff, files: files, snippets: snippets)
            return GitSummarySnapshot(
                repo: repo,
                target: target,
                targetSubject: nil,
                body: nil,
                diffText: diff,
                files: files,
                untrackedSnippets: snippets,
                diffHash: Self.sha256(hashInput)
            )
        }
    }

    private func runGit(_ arguments: [String], timeout: TimeInterval) throws -> String {
        let result = runner.run(arguments, timeout: timeout)
        guard result.succeeded else {
            if result.timedOut {
                throw GitSummarySnapshotBuilderError.gitFailed("Git command timed out.")
            }
            if result.cancelled {
                throw CancellationError()
            }
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitSummarySnapshotBuilderError.gitFailed(detail.isEmpty ? "Git command failed." : detail)
        }
        return result.stdout
    }

    private func parseCommitMetadata(_ raw: String) -> (subject: String?, body: String?) {
        let parts = raw.components(separatedBy: "\u{1f}")
        let subject = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let body = parts.dropFirst().joined(separator: "\u{1f}").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return (subject, body)
    }

    static func fileChanges(
        diffText: String,
        numstat: String,
        workingTree: GitWorkingTreeSummary?,
        snippets: [GitUntrackedSnippet] = []
    ) -> [GitSummaryFileChange] {
        let metadata = diffMetadata(diffText)
        var changes: [GitSummaryFileChange] = []
        var seen = Set<String>()

        for line in numstat.split(separator: "\n", omittingEmptySubsequences: true) {
            let cols = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            let insertions = cols[0] == "-" ? -1 : (Int(cols[0]) ?? 0)
            let deletions = cols[1] == "-" ? -1 : (Int(cols[1]) ?? 0)
            let rawPath = String(cols[2])
            let path = normalizedNumstatPath(rawPath)
            let meta = metadata[path] ?? metadata[rawPath]
            let change = GitSummaryFileChange(
                path: path,
                oldPath: meta?.oldPath,
                status: meta?.status ?? .modified,
                insertions: insertions,
                deletions: deletions,
                isBinary: insertions < 0 || deletions < 0 || meta?.isBinary == true
            )
            changes.append(change)
            seen.insert(change.path)
        }

        if let workingTree {
            for change in workingTree.changes where !seen.contains(change.path) {
                let snippet = snippets.first { $0.path == change.path }
                changes.append(GitSummaryFileChange(
                    path: change.path,
                    oldPath: change.oldPath,
                    status: change.kind.summaryStatus,
                    insertions: snippet?.text.split(separator: "\n").count ?? 0,
                    deletions: 0,
                    isBinary: false
                ))
                seen.insert(change.path)
            }
        }

        for (path, meta) in metadata where !seen.contains(path) {
            changes.append(GitSummaryFileChange(
                path: path,
                oldPath: meta.oldPath,
                status: meta.status,
                insertions: 0,
                deletions: 0,
                isBinary: meta.isBinary
            ))
        }

        return changes.sorted { lhs, rhs in
            if lhs.status.rawValue != rhs.status.rawValue {
                return lhs.status.rawValue < rhs.status.rawValue
            }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    private static func diffMetadata(_ diffText: String) -> [String: (oldPath: String?, status: GitSummaryFileChange.Status, isBinary: Bool)] {
        var output: [String: (oldPath: String?, status: GitSummaryFileChange.Status, isBinary: Bool)] = [:]
        for section in splitDiffSections(diffText) {
            let lines = section.components(separatedBy: "\n")
            guard let first = lines.first, first.hasPrefix("diff --git ") else { continue }
            let paths = parseDiffGitPaths(first)
            var path = paths.new
            var oldPath = paths.old
            var status: GitSummaryFileChange.Status = .modified
            var isBinary = false

            for line in lines {
                if line.hasPrefix("new file mode") { status = .added }
                if line.hasPrefix("deleted file mode") { status = .deleted }
                if line.hasPrefix("copy from ") { status = .copied; oldPath = String(line.dropFirst("copy from ".count)) }
                if line.hasPrefix("copy to ") { path = String(line.dropFirst("copy to ".count)) }
                if line.hasPrefix("rename from ") { status = .renamed; oldPath = String(line.dropFirst("rename from ".count)) }
                if line.hasPrefix("rename to ") { path = String(line.dropFirst("rename to ".count)) }
                if line.contains("Binary files ") || line.hasPrefix("GIT binary patch") { isBinary = true }
            }

            output[path] = (oldPath: oldPath == path ? nil : oldPath, status: status, isBinary: isBinary)
        }
        return output
    }

    static func splitDiffSections(_ diffText: String) -> [String] {
        var sections: [String] = []
        var current: [String] = []
        for line in diffText.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git "), !current.isEmpty {
                sections.append(current.joined(separator: "\n"))
                current = []
            }
            current.append(line)
        }
        if !current.isEmpty {
            sections.append(current.joined(separator: "\n"))
        }
        return sections.filter { $0.hasPrefix("diff --git ") }
    }

    private static func parseDiffGitPaths(_ line: String) -> (old: String, new: String) {
        let parts = line.split(separator: " ")
        guard parts.count >= 4 else { return ("", "") }
        return (stripGitPrefix(String(parts[2])), stripGitPrefix(String(parts[3])))
    }

    private static func stripGitPrefix(_ path: String) -> String {
        var output = path
        if output.hasPrefix("\"") && output.hasSuffix("\""), output.count >= 2 {
            output = String(output.dropFirst().dropLast())
        }
        if output.hasPrefix("a/") || output.hasPrefix("b/") {
            output = String(output.dropFirst(2))
        }
        return output
    }

    private static func normalizedNumstatPath(_ raw: String) -> String {
        if let arrow = raw.range(of: " => ") {
            var tail = String(raw[arrow.upperBound...])
            if let brace = tail.lastIndex(of: "}") {
                tail = String(tail[tail.index(after: brace)...])
            }
            if tail.hasPrefix("/") { tail = String(tail.dropFirst()) }
            return tail.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? raw
        }
        return raw
    }

    private static func untrackedSnippets(repo: GitRepo, changes: [GitWorkingTreeChange]) -> [GitUntrackedSnippet] {
        let root = URL(fileURLWithPath: repo.rootPath).standardizedFileURL
        return changes
            .filter { $0.kind == .untracked }
            .compactMap { change in
                let url = root.appendingPathComponent(change.path).standardizedFileURL
                guard url.path.hasPrefix(root.path + "/") || url.path == root.path else { return nil }
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let type = attrs[.type] as? FileAttributeType,
                      type == .typeRegular
                else { return nil }
                let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
                guard fileSize > 0, fileSize <= 64 * 1024 else { return nil }
                guard let data = try? Data(contentsOf: url), !data.contains(0),
                      let text = String(data: data, encoding: .utf8)
                else { return nil }
                let limited = String(text.prefix(16 * 1024))
                return GitUntrackedSnippet(path: change.path, text: limited, truncated: limited.count < text.count)
            }
    }

    private static func hashInput(diff: String, files: [GitSummaryFileChange], snippets: [GitUntrackedSnippet]) -> String {
        let fileLines = files.map { "\($0.status.rawValue)\t\($0.oldPath ?? "")\t\($0.path)\t\($0.insertions)\t\($0.deletions)\t\($0.isBinary)" }
        let snippetLines = snippets.map { "untracked\t\($0.path)\t\($0.truncated)\n\($0.text)" }
        return ([diff] + fileLines + snippetLines).joined(separator: "\n")
    }

    private static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension GitWorkingTreeChange.Kind {
    var summaryStatus: GitSummaryFileChange.Status {
        switch self {
        case .added: .added
        case .modified: .modified
        case .deleted: .deleted
        case .renamed: .renamed
        case .copied: .copied
        case .untracked: .untracked
        case .conflicted: .conflicted
        case .changed: .changed
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
