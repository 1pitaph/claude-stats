import Foundation

struct ChatContextBuilder: Sendable {
    private let analyzer: GitAnalyzer
    private let resolver: GitWorkspaceSourceResolver

    init(
        analyzer: GitAnalyzer = GitAnalyzer(),
        resolver: GitWorkspaceSourceResolver = GitWorkspaceSourceResolver()
    ) {
        self.analyzer = analyzer
        self.resolver = resolver
    }

    func projectOptions(
        sessions: [Session],
        sourceIDs: Set<GitWorkspaceSourceID>
    ) async -> [ChatProjectOption] {
        let analyzer = analyzer
        let resolver = resolver
        return await Task.detached(priority: .utility) {
            let cwds = resolver.cwds(sessions: sessions, enabledSources: sourceIDs)
            return analyzer.repos(forCwds: cwds).map {
                ChatProjectOption(
                    rootPath: $0.rootPath,
                    displayName: $0.displayName,
                    branchName: $0.currentBranch
                )
            }
        }.value
    }

    func snapshot(for rootPath: String) async -> ChatContextSnapshot? {
        let analyzer = analyzer
        return await Task.detached(priority: .utility) {
            guard let repo = analyzer.repo(forCwd: rootPath) else { return nil }
            let workingTree = analyzer.workingTreeSummary(for: repo)
            let commits = analyzer.recentCommits(in: repo, limit: 5).map {
                ChatContextCommit(hash: $0.hash, subject: $0.subject, author: $0.author, date: $0.date)
            }
            return ChatContextSnapshot(
                capturedAt: Date(),
                repoName: repo.displayName,
                repoRootPath: repo.rootPath,
                branchName: repo.currentBranch,
                isDirty: workingTree.isDirty,
                dirtyFileCount: workingTree.fileCount,
                stagedFileCount: workingTree.stagedCount,
                unstagedFileCount: workingTree.unstagedCount,
                changedPaths: workingTree.changes.prefix(12).map(\.displayPath),
                recentCommits: commits
            )
        }.value
    }

    static func systemPrompt(context: ChatContextSnapshot?) -> String {
        var lines = [
            "You are the local LLM chat inside Claude Stats.",
            "Answer helpfully and be explicit when you are making an inference.",
            "Project context is read-only metadata. You cannot execute commands, inspect file contents, change branches, or edit files from this chat.",
        ]

        if let context {
            lines.append("")
            lines.append("Read-only project context:")
            lines.append("- Repository: \(context.repoName)")
            lines.append("- Path: \(context.repoRootPath)")
            lines.append("- Branch: \(context.branchLabel)")
            lines.append("- Working tree: \(context.dirtyLabel), staged \(context.stagedFileCount), unstaged \(context.unstagedFileCount)")
            if !context.changedPaths.isEmpty {
                lines.append("- Changed paths:")
                lines.append(contentsOf: context.changedPaths.map { "  - \($0)" })
            }
            if !context.recentCommits.isEmpty {
                lines.append("- Recent commits:")
                lines.append(contentsOf: context.recentCommits.map { "  - \($0.shortHash) \($0.subject)" })
            }
        } else {
            lines.append("")
            lines.append("No project context is selected for this message.")
        }

        return lines.joined(separator: "\n")
    }
}
