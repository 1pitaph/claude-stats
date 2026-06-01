import Foundation

protocol DailyReportGitActivityProviding: Sendable {
    func commitCounts(
        for projectPaths: [String],
        in interval: DateInterval,
        calendar: Calendar
    ) async -> [String: [Date: Int]]
}

struct DailyReportGitActivityProvider: DailyReportGitActivityProviding {
    func commitCounts(
        for projectPaths: [String],
        in interval: DateInterval,
        calendar: Calendar
    ) async -> [String: [Date: Int]] {
        let git = GitAnalyzer()
        guard git.isAvailable else { return [:] }

        let uniquePaths = Array(Set(projectPaths)).sorted()
        let repoByPath = Dictionary(uniqueKeysWithValues: uniquePaths.compactMap { path -> (String, GitRepo)? in
            guard let repo = git.repo(forCwd: path) else { return nil }
            return (path, repo)
        })
        let reposByRoot = Dictionary(grouping: repoByPath.values, by: \.rootPath).compactMapValues(\.first)
        guard !reposByRoot.isEmpty else { return [:] }

        let authorEmail = git.currentUserEmail()
        let activities = git.activity(for: Array(reposByRoot.values), since: interval.start, authorEmail: authorEmail)
        var countsByRepo: [String: [Date: Int]] = [:]
        for activity in activities {
            for commit in activity.commits where interval.contains(commit.date) {
                let day = calendar.startOfDay(for: commit.date)
                countsByRepo[activity.repo.rootPath, default: [:]][day, default: 0] += 1
            }
        }

        var out: [String: [Date: Int]] = [:]
        for (path, repo) in repoByPath {
            out[path] = countsByRepo[repo.rootPath] ?? [:]
        }
        return out
    }
}

enum DailyReportBuilder {
    static func buildMonth(
        sessions: [Session],
        month: Date,
        gitCommitCounts: [String: [Date: Int]] = [:],
        calendar: Calendar = .current
    ) -> DailyReportMonthSnapshot {
        let monthInterval = monthInterval(for: month, calendar: calendar)
        let visibleInterval = visibleInterval(for: monthInterval, calendar: calendar)
        var days: [Date: [String: MutableProjectDay]] = [:]

        for session in sessions {
            guard let stats = session.stats else { continue }
            let identity = projectIdentity(for: session)
            let latestActivity = stats.lastActivity ?? session.lastModified
            var touchedDays = Set<Date>()

            for interval in stats.activityIntervals {
                guard let clippedToVisible = ActivityAnalyzer.clip(interval, to: visibleInterval) else { continue }
                for day in daysTouched(by: clippedToVisible, calendar: calendar) {
                    let bounds = ActivityAnalyzer.dayBounds(for: day, calendar: calendar)
                    guard let clipped = ActivityAnalyzer.clip(interval, to: bounds) else { continue }
                    mutateProjectDay(
                        days: &days,
                        day: day,
                        identity: identity,
                        session: session,
                        latestActivity: latestActivity
                    ) { projectDay in
                        projectDay.intervals.append(clipped)
                    }
                    touchedDays.insert(day)
                }
            }

            let tokenDays = tokenTotalsByDay(for: session, stats: stats, visibleInterval: visibleInterval, calendar: calendar)
            for (day, tokens) in tokenDays {
                mutateProjectDay(
                    days: &days,
                    day: day,
                    identity: identity,
                    session: session,
                    latestActivity: latestActivity
                ) { projectDay in
                    projectDay.tokens += tokens
                }
                touchedDays.insert(day)
            }

            if touchedDays.isEmpty,
               visibleInterval.contains(latestActivity) {
                let day = calendar.startOfDay(for: latestActivity)
                mutateProjectDay(
                    days: &days,
                    day: day,
                    identity: identity,
                    session: session,
                    latestActivity: latestActivity
                ) { _ in }
            }
        }

        var summariesByDay: [Date: DailyReportDaySummary] = [:]
        for (day, projectDays) in days {
            let projects = projectDays.values
                .map { $0.summary(gitCommitCount: gitCommitCounts[$0.path ?? $0.id]?[day] ?? 0) }
                .filter { $0.activeDuration > 0 || $0.tokens > 0 || $0.sessionCount > 0 }
                .sorted(by: sortProjectDays)
            summariesByDay[day] = DailyReportDaySummary(day: day, projects: projects)
        }

        let projects = monthProjects(from: summariesByDay, monthInterval: monthInterval, calendar: calendar)
        return DailyReportMonthSnapshot(
            monthInterval: monthInterval,
            visibleDays: visibleDays(for: monthInterval, summaries: summariesByDay, calendar: calendar),
            projects: projects,
            sourceSessionCount: sessions.count
        )
    }

    static func projectPaths(
        sessions: [Session],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [String] {
        var paths = Set<String>()
        for session in sessions {
            guard let stats = session.stats,
                  let path = normalizedPath(session.cwd) else { continue }
            if stats.activityIntervals.contains(where: { $0.intersects(interval) }) {
                paths.insert(path)
                continue
            }
            let latestActivity = stats.lastActivity ?? session.lastModified
            if interval.contains(latestActivity) {
                paths.insert(path)
                continue
            }
            if stats.timeline.contains(where: { interval.contains(calendar.startOfDay(for: $0.start)) }) {
                paths.insert(path)
            }
        }
        return paths.sorted()
    }

    static func monthInterval(for date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 30 * 86_400)
    }

    static func visibleDays(
        for monthInterval: DateInterval,
        summaries: [Date: DailyReportDaySummary],
        calendar: Calendar = .current
    ) -> [DailyReportCalendarDay] {
        let visible = visibleInterval(for: monthInterval, calendar: calendar)
        var out: [DailyReportCalendarDay] = []
        var cursor = visible.start
        while cursor < visible.end {
            let day = calendar.startOfDay(for: cursor)
            out.append(DailyReportCalendarDay(
                date: day,
                isInDisplayedMonth: monthInterval.contains(day),
                summary: summaries[day] ?? .empty(day: day)
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return out
    }

    private static func visibleInterval(for monthInterval: DateInterval, calendar: Calendar) -> DateInterval {
        let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)?.start ?? monthInterval.start
        let lastInMonth = monthInterval.end.addingTimeInterval(-1)
        let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: lastInMonth)?.start ?? lastInMonth
        let end = calendar.date(byAdding: .day, value: 7, to: lastWeekStart) ?? monthInterval.end
        return DateInterval(start: firstWeekStart, end: end)
    }

    private static func daysTouched(by interval: DateInterval, calendar: Calendar) -> [Date] {
        let first = calendar.startOfDay(for: interval.start)
        let last = calendar.startOfDay(for: interval.end.addingTimeInterval(-0.001))
        var days: [Date] = []
        var cursor = first
        while cursor <= last {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return days
    }

    private static func tokenTotalsByDay(
        for session: Session,
        stats: SessionStats,
        visibleInterval: DateInterval,
        calendar: Calendar
    ) -> [Date: Int] {
        var out: [Date: Int] = [:]
        if stats.timeline.isEmpty {
            let activity = stats.lastActivity ?? session.lastModified
            guard visibleInterval.contains(activity) else { return [:] }
            out[calendar.startOfDay(for: activity), default: 0] += stats.totalUsage.total
        } else {
            for bucket in stats.timeline {
                let day = calendar.startOfDay(for: bucket.start)
                guard visibleInterval.contains(day) else { continue }
                out[day, default: 0] += bucket.usage.total
            }
        }
        return out
    }

    private static func mutateProjectDay(
        days: inout [Date: [String: MutableProjectDay]],
        day: Date,
        identity: ProjectIdentity,
        session: Session,
        latestActivity: Date,
        mutate: (inout MutableProjectDay) -> Void
    ) {
        var projectDay = days[day, default: [:]][identity.id] ?? MutableProjectDay(identity: identity)
        projectDay.providers.insert(session.provider)
        projectDay.sessionIDs.insert(session.id)
        if projectDay.latestActivity == nil || latestActivity > (projectDay.latestActivity ?? .distantPast) {
            projectDay.latestActivity = latestActivity
        }
        mutate(&projectDay)
        days[day, default: [:]][identity.id] = projectDay
    }

    private static func monthProjects(
        from summariesByDay: [Date: DailyReportDaySummary],
        monthInterval: DateInterval,
        calendar _: Calendar
    ) -> [DailyReportProjectMonthSummary] {
        var projects: [String: MutableProjectMonth] = [:]
        for (day, summary) in summariesByDay where monthInterval.contains(day) {
            for project in summary.projects {
                var month = projects[project.id] ?? MutableProjectMonth(project: project)
                month.activeDays.insert(day)
                month.providers.formUnion(project.providers)
                month.activeDuration += project.activeDuration
                month.tokens += project.tokens
                month.sessionCount += project.sessionCount
                month.gitCommitCount += project.gitCommitCount
                if month.latestActivity == nil || (project.latestActivity ?? .distantPast) > (month.latestActivity ?? .distantPast) {
                    month.latestActivity = project.latestActivity
                }
                projects[project.id] = month
            }
        }

        return projects.values
            .map(\.summary)
            .sorted {
                if $0.activeDuration != $1.activeDuration { return $0.activeDuration > $1.activeDuration }
                if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private static func sortProjectDays(_ lhs: DailyReportProjectDaySummary, _ rhs: DailyReportProjectDaySummary) -> Bool {
        if lhs.activeDuration != rhs.activeDuration { return lhs.activeDuration > rhs.activeDuration }
        if lhs.tokens != rhs.tokens { return lhs.tokens > rhs.tokens }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static func projectIdentity(for session: Session) -> ProjectIdentity {
        if let cwd = normalizedPath(session.cwd) {
            let name = (cwd as NSString).lastPathComponent
            return ProjectIdentity(id: cwd, displayName: name.isEmpty ? session.projectDisplayName : name, path: cwd)
        }
        return ProjectIdentity(
            id: "\(session.provider.rawValue):\(session.projectDirectoryName)",
            displayName: session.projectDisplayName,
            path: nil
        )
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    private struct ProjectIdentity: Hashable {
        let id: String
        let displayName: String
        let path: String?
    }

    private struct MutableProjectDay {
        let id: String
        let displayName: String
        let path: String?
        var providers: Set<ProviderKind>
        var intervals: [DateInterval]
        var tokens: Int
        var sessionIDs: Set<String>
        var latestActivity: Date?

        init(identity: ProjectIdentity) {
            id = identity.id
            displayName = identity.displayName
            path = identity.path
            providers = []
            intervals = []
            tokens = 0
            sessionIDs = []
            latestActivity = nil
        }

        func summary(gitCommitCount: Int) -> DailyReportProjectDaySummary {
            DailyReportProjectDaySummary(
                id: id,
                displayName: displayName,
                path: path,
                providers: providers,
                activeDuration: ActivityAnalyzer.totalDuration(ActivityAnalyzer.union(intervals)),
                tokens: tokens,
                sessionCount: sessionIDs.count,
                gitCommitCount: gitCommitCount,
                latestActivity: latestActivity
            )
        }
    }

    private struct MutableProjectMonth {
        let id: String
        let displayName: String
        let path: String?
        var providers: Set<ProviderKind>
        var activeDays: Set<Date>
        var activeDuration: TimeInterval
        var tokens: Int
        var sessionCount: Int
        var gitCommitCount: Int
        var latestActivity: Date?

        init(project: DailyReportProjectDaySummary) {
            id = project.id
            displayName = project.displayName
            path = project.path
            providers = project.providers
            activeDays = []
            activeDuration = 0
            tokens = 0
            sessionCount = 0
            gitCommitCount = 0
            latestActivity = nil
        }

        var summary: DailyReportProjectMonthSummary {
            DailyReportProjectMonthSummary(
                id: id,
                displayName: displayName,
                path: path,
                providers: providers,
                activeDays: activeDays.count,
                activeDuration: activeDuration,
                tokens: tokens,
                sessionCount: sessionCount,
                gitCommitCount: gitCommitCount,
                latestActivity: latestActivity
            )
        }
    }
}
