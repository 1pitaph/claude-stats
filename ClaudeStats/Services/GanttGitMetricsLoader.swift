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
    private var commitActivityCache: [CommitActivityKey: CachedCommitActivity] = [:]

    init(git: GitAnalyzer = GitAnalyzer()) {
        self.git = git
    }

    func externalMetrics(
        sessions: [Session],
        during interval: DateInterval,
        projectIDFilter: String? = nil
    ) async -> GanttExternalMetrics {
        guard !Task.isCancelled, git.isAvailable else { return .zero }
        let projectCwds = Self.scopedCwds(
            sessions: sessions,
            during: interval,
            projectIDFilter: projectIDFilter
        )
        guard !projectCwds.isEmpty else { return .zero }

        let repoScopes = resolvedRepoScopes(for: projectCwds)
        guard !Task.isCancelled, !repoScopes.isEmpty else { return .zero }

        let email = currentUserEmail()
        var commitCount = 0
        var commitMarkers: [GanttCommitMarker] = []
        var countedRepoIDs = Set<String>()
        for scope in repoScopes {
            guard !Task.isCancelled else { return .zero }
            let activity = cachedCommitActivity(in: scope.repo, during: interval, authorEmail: email)
            if countedRepoIDs.insert(scope.repo.id).inserted {
                commitCount += activity.commitCount
            }
            commitMarkers.append(contentsOf: activity.commits.map { commit in
                GanttCommitMarker(
                    id: commit.id,
                    projectID: scope.projectID,
                    date: commit.date,
                    repoName: scope.repo.displayName,
                    shortHash: commit.shortHash,
                    subject: commit.subject
                )
            })
        }

        return GanttExternalMetrics(
            commitCount: commitCount,
            failureSignals: 0,
            retrySignals: 0,
            commitMarkers: Array(commitMarkers.sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id < rhs.id
            }.prefix(48))
        )
    }

    private static func scopedCwds(
        sessions: [Session],
        during interval: DateInterval,
        projectIDFilter: String?
    ) -> [ProjectCwdScope] {
        var scopesByKey: [String: ProjectCwdScope] = [:]
        for session in sessions {
            guard !Task.isCancelled else { return [] }
            let identity = GanttTimelineBuilder.projectIdentity(for: session)
            if let projectIDFilter, identity.id != projectIDFilter {
                continue
            }
            guard sessionIntersects(session, interval: interval),
                  let cwd = GanttTimelineBuilder.normalizedPath(session.cwd) else { continue }
            scopesByKey["\(identity.id)\u{1f}\(cwd)"] = ProjectCwdScope(projectID: identity.id, cwd: cwd)
        }
        return scopesByKey.values.sorted {
            if $0.projectID != $1.projectID { return $0.projectID < $1.projectID }
            return $0.cwd < $1.cwd
        }
    }

    private static func sessionIntersects(_ session: Session, interval: DateInterval) -> Bool {
        guard let stats = session.stats else { return false }
        return stats.activityIntervals.contains { ActivityAnalyzer.clip($0, to: interval) != nil }
    }

    private func resolvedRepoScopes(for projectCwds: [ProjectCwdScope]) -> [ProjectRepoScope] {
        var seenScopes = Set<String>()
        var scopes: [ProjectRepoScope] = []

        for projectCwd in projectCwds {
            guard !Task.isCancelled else { return [] }
            if let cached = cwdRepoCache[projectCwd.cwd] {
                let key = "\(projectCwd.projectID)\u{1f}\(cached.id)"
                if seenScopes.insert(key).inserted {
                    scopes.append(ProjectRepoScope(projectID: projectCwd.projectID, repo: cached))
                }
                continue
            }
            if missingCwds.contains(projectCwd.cwd) { continue }
            guard FileManager.default.fileExists(atPath: projectCwd.cwd),
                  let repo = git.repo(forCwd: projectCwd.cwd) else {
                missingCwds.insert(projectCwd.cwd)
                continue
            }
            cwdRepoCache[projectCwd.cwd] = repo
            let key = "\(projectCwd.projectID)\u{1f}\(repo.id)"
            if seenScopes.insert(key).inserted {
                scopes.append(ProjectRepoScope(projectID: projectCwd.projectID, repo: repo))
            }
        }

        return scopes.sorted {
            if $0.projectID != $1.projectID { return $0.projectID < $1.projectID }
            return $0.repo.displayName.localizedCaseInsensitiveCompare($1.repo.displayName) == .orderedAscending
        }
    }

    private func currentUserEmail() -> String? {
        if userEmailLoaded { return userEmail }
        userEmail = git.currentUserEmail()
        userEmailLoaded = true
        return userEmail
    }

    private func cachedCommitActivity(in repo: GitRepo, during interval: DateInterval, authorEmail: String?) -> CachedCommitActivity {
        let key = CommitActivityKey(repoID: repo.id, interval: interval, authorEmail: authorEmail)
        if let cached = commitActivityCache[key] { return cached }
        let commits = git.commits(in: repo, during: interval, authorEmail: authorEmail)
        let activity = CachedCommitActivity(commits: commits)
        commitActivityCache[key] = activity
        return activity
    }

    private struct CachedCommitActivity: Sendable {
        let commits: [GitCommit]

        var commitCount: Int { commits.count }
    }

    private struct ProjectCwdScope: Sendable {
        let projectID: String
        let cwd: String
    }

    private struct ProjectRepoScope: Sendable {
        let projectID: String
        let repo: GitRepo
    }

    private struct CommitActivityKey: Hashable {
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
