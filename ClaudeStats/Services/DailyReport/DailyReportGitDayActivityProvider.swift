import Foundation

protocol DailyReportGitDayActivityProviding: Sendable {
    func snapshot(
        for project: DailyReportProjectDaySummary,
        day: Date,
        calendar: Calendar
    ) async -> DailyReportGitDaySnapshot
}

struct DailyReportGitDayActivityProvider: DailyReportGitDayActivityProviding {
    private let git: GitAnalyzer

    init(git: GitAnalyzer = GitAnalyzer()) {
        self.git = git
    }

    func snapshot(
        for project: DailyReportProjectDaySummary,
        day: Date,
        calendar: Calendar
    ) async -> DailyReportGitDaySnapshot {
        let dayStart = calendar.startOfDay(for: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let interval = DateInterval(start: dayStart, end: nextDay)

        guard let path = project.path, !path.isEmpty else {
            return .unavailable(project: project, day: dayStart, interval: interval, availability: .missingProjectPath)
        }

        return await Task.detached(priority: .utility) {
            guard git.isAvailable else {
                return .unavailable(project: project, day: dayStart, interval: interval, availability: .gitUnavailable)
            }

            guard let repo = git.repo(forCwd: path) else {
                return .unavailable(project: project, day: dayStart, interval: interval, availability: .notRepository)
            }

            let authorEmail = git.currentUserEmail()
            let commits = git.commits(in: repo, during: interval, authorEmail: authorEmail)
                .map { commit in
                    Self.dayCommit(from: commit, detail: git.commitDetail(for: commit.hash, in: repo), repo: repo)
                }
                .sorted {
                    if $0.authorDate != $1.authorDate { return $0.authorDate < $1.authorDate }
                    return $0.hash < $1.hash
                }

            return DailyReportGitDaySnapshot(
                projectID: project.id,
                projectName: project.displayName,
                projectPath: path,
                day: dayStart,
                interval: interval,
                repo: repo,
                commits: commits,
                authorEmail: authorEmail,
                availability: .loaded
            )
        }.value
    }

    private static func dayCommit(from commit: GitCommit, detail: CommitDetail?, repo: GitRepo) -> DailyReportGitDayCommit {
        let files = detail?.files ?? []
        let insertions = detail?.totalInsertions ?? commit.insertions
        let deletions = detail?.totalDeletions ?? commit.deletions
        let filesChanged = files.isEmpty ? commit.filesChanged : files.count
        return DailyReportGitDayCommit(
            hash: commit.hash,
            abbreviatedHash: detail?.abbreviatedHash ?? commit.shortHash,
            authorName: detail?.authorName ?? commit.author,
            authorEmail: detail?.authorEmail ?? commit.authorEmail,
            authorDate: detail?.authorDate ?? commit.date,
            commitDate: detail?.commitDate ?? commit.date,
            subject: detail?.subject ?? commit.subject,
            body: detail?.body ?? "",
            files: files,
            insertions: insertions,
            deletions: deletions,
            filesChanged: filesChanged,
            repoID: repo.id
        )
    }
}
