import Foundation

protocol DailyReportGitDayDiffProviding: Sendable {
    func excerpts(
        for snapshot: DailyReportGitDaySnapshot,
        perCommitLimit: Int,
        totalLimit: Int
    ) async -> [DailyReportGitDayDiffExcerpt]
}

struct DailyReportGitDayDiffProvider: DailyReportGitDayDiffProviding {
    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    func excerpts(
        for snapshot: DailyReportGitDaySnapshot,
        perCommitLimit: Int = 8_000,
        totalLimit: Int = 30_000
    ) async -> [DailyReportGitDayDiffExcerpt] {
        guard let repo = snapshot.repo, !snapshot.commits.isEmpty else { return [] }
        let runner = runner
        let commits = snapshot.commits

        return await Task.detached(priority: .utility) {
            var remaining = max(0, totalLimit)
            var out: [DailyReportGitDayDiffExcerpt] = []

            for commit in commits where remaining > 0 {
                let result = runner.run([
                    "-C", repo.rootPath,
                    "show",
                    "--format=",
                    "--no-color",
                    "--find-renames",
                    "--find-copies",
                    commit.hash,
                ], timeout: 30)
                guard result.succeeded else { continue }
                let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }

                let limit = min(perCommitLimit, remaining)
                let limited = String(raw.prefix(limit))
                remaining -= limited.count
                out.append(DailyReportGitDayDiffExcerpt(
                    commitHash: commit.hash,
                    text: limited,
                    truncated: limited.count < raw.count
                ))
            }

            return out
        }.value
    }
}
