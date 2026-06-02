import Foundation

protocol GanttGitMetricsLoading: Sendable {
    func externalMetrics(
        sessions: [Session],
        during interval: DateInterval,
        projectIDFilter: String?
    ) async -> GanttExternalMetrics
}

extension GanttGitMetricsLoading {
    func externalMetrics(
        sessions: [Session],
        during interval: DateInterval
    ) async -> GanttExternalMetrics {
        await externalMetrics(sessions: sessions, during: interval, projectIDFilter: nil)
    }
}

actor GanttGitMetricsLoader: GanttGitMetricsLoading {
    private let git: GitAnalyzer
    private var cwdRepoCache: [String: GitRepo] = [:]
    private var missingCwds = Set<String>()
    private var userEmailLoaded = false
    private var userEmail: String?
    private var commitCountCache: [CommitCountKey: Int] = [:]

    init(git: GitAnalyzer = GitAnalyzer()) {
        self.git = git
    }

    func externalMetrics(
        sessions: [Session],
        during interval: DateInterval,
        projectIDFilter: String? = nil
    ) async -> GanttExternalMetrics {
        guard !Task.isCancelled, git.isAvailable else { return .zero }
        let cwds = Self.scopedCwds(
            sessions: sessions,
            during: interval,
            projectIDFilter: projectIDFilter
        )
        guard !cwds.isEmpty else { return .zero }

        let repos = resolvedRepos(for: cwds)
        guard !Task.isCancelled, !repos.isEmpty else { return .zero }

        let email = currentUserEmail()
        var commitCount = 0
        for repo in repos {
            guard !Task.isCancelled else { return .zero }
            commitCount += cachedCommitCount(in: repo, during: interval, authorEmail: email)
        }

        return GanttExternalMetrics(
            commitCount: commitCount,
            failureSignals: 0,
            retrySignals: 0
        )
    }

    private static func scopedCwds(
        sessions: [Session],
        during interval: DateInterval,
        projectIDFilter: String?
    ) -> [String] {
        var cwds = Set<String>()
        for session in sessions {
            guard !Task.isCancelled else { return [] }
            if let projectIDFilter,
               GanttTimelineBuilder.projectIdentity(for: session).id != projectIDFilter {
                continue
            }
            guard sessionIntersects(session, interval: interval),
                  let cwd = GanttTimelineBuilder.normalizedPath(session.cwd) else { continue }
            cwds.insert(cwd)
        }
        return cwds.sorted()
    }

    private static func sessionIntersects(_ session: Session, interval: DateInterval) -> Bool {
        guard let stats = session.stats else { return false }
        return stats.activityIntervals.contains { ActivityAnalyzer.clip($0, to: interval) != nil }
    }

    private func resolvedRepos(for cwds: [String]) -> [GitRepo] {
        var seenRepos = Set<String>()
        var repos: [GitRepo] = []

        for cwd in cwds {
            guard !Task.isCancelled else { return [] }
            if let cached = cwdRepoCache[cwd] {
                if seenRepos.insert(cached.rootPath).inserted { repos.append(cached) }
                continue
            }
            if missingCwds.contains(cwd) { continue }
            guard FileManager.default.fileExists(atPath: cwd),
                  let repo = git.repo(forCwd: cwd) else {
                missingCwds.insert(cwd)
                continue
            }
            cwdRepoCache[cwd] = repo
            if seenRepos.insert(repo.rootPath).inserted { repos.append(repo) }
        }

        return repos.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func currentUserEmail() -> String? {
        if userEmailLoaded { return userEmail }
        userEmail = git.currentUserEmail()
        userEmailLoaded = true
        return userEmail
    }

    private func cachedCommitCount(in repo: GitRepo, during interval: DateInterval, authorEmail: String?) -> Int {
        let key = CommitCountKey(repoID: repo.id, interval: interval, authorEmail: authorEmail)
        if let cached = commitCountCache[key] { return cached }
        let count = git.commitCount(in: repo, during: interval, authorEmail: authorEmail)
        commitCountCache[key] = count
        return count
    }

    private struct CommitCountKey: Hashable {
        let repoID: String
        let start: Date
        let end: Date
        let authorEmail: String?

        init(repoID: String, interval: DateInterval, authorEmail: String?) {
            self.repoID = repoID
            self.start = interval.start
            self.end = interval.end
            self.authorEmail = authorEmail
        }
    }
}
