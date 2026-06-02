import Foundation

enum GanttTimelineBuilder {
    static let defaultMergeGap: TimeInterval = 10 * 60

    static func build(
        sessions: [Session],
        period: GanttPeriod,
        activityMode: GanttActivityMode,
        focusIntervals: [DateInterval] = [],
        focusAppIntervals: [AppFocusInterval] = [],
        usageLimitReports: [UsageLimitReport] = [],
        externalMetrics: GanttExternalMetrics = .zero,
        mergeGap: TimeInterval = Self.defaultMergeGap,
        projectIDFilter: String? = nil
    ) -> GanttTimelineSnapshot {
        var projects: [String: MutableProject] = [:]
        var countedSessionIDs = Set<String>()

        for session in sessions {
            guard let stats = session.stats else { continue }
            let identity = projectIdentity(for: session)
            if let projectIDFilter, identity.id != projectIDFilter {
                continue
            }

            let intervals = stats.activityIntervals.compactMap {
                ActivityAnalyzer.clip($0, to: period.dataRange)
            }
            guard !intervals.isEmpty else { continue }
            countedSessionIDs.insert(session.id)
            let profile = SessionUsageProfile(session: session, activeIntervals: intervals)

            var project = projects[identity.id] ?? MutableProject(
                id: identity.id,
                displayName: identity.displayName,
                path: identity.path,
                providers: [],
                records: [],
                latestActivity: period.dataRange.start
            )

            project.providers.insert(session.provider)
            project.records.append(contentsOf: intervals.map {
                SourceInterval(interval: $0, profile: profile)
            })
            if let latest = intervals.map(\.end).max(), latest > project.latestActivity {
                project.latestActivity = latest
            }
            projects[identity.id] = project
        }

        let focusItems = focusAppIntervals + focusIntervals.map {
            AppFocusInterval(bundleID: "", interval: $0)
        }
        let clippedFocusItems = focusItems.compactMap { item -> AppFocusInterval? in
            guard let clipped = ActivityAnalyzer.clip(item.interval, to: period.dataRange) else { return nil }
            return AppFocusInterval(bundleID: item.bundleID, interval: clipped)
        }
        let focus = ActivityAnalyzer.union(clippedFocusItems.map(\.interval))

        let rows = projects.values.compactMap { project -> GanttProjectTimeline? in
            let active = ActivityAnalyzer.union(project.records.map(\.interval))
            let visible: [DateInterval]
            switch activityMode {
            case .aiActive:
                visible = merge(active, gap: mergeGap)
            case .assistedFocus:
                visible = merge(ActivityAnalyzer.intersection(active, focus), gap: mergeGap)
            }
            guard !visible.isEmpty else { return nil }

            var segments: [GanttTimelineSegment] = []
            segments.reserveCapacity(visible.count)
            for interval in visible {
                let metrics = aggregateSegmentMetrics(
                    interval: interval,
                    records: project.records,
                    focus: focus
                )
                segments.append(GanttTimelineSegment(
                    id: "\(project.id)|\(interval.start.timeIntervalSinceReferenceDate)|\(interval.end.timeIntervalSinceReferenceDate)",
                    interval: interval,
                    providers: metrics.providers,
                    sessionIDs: metrics.sessionIDs,
                    sessionTitles: metrics.sessionTitles,
                    models: metrics.models,
                    usage: metrics.usage,
                    cost: metrics.cost,
                    messageCount: metrics.messageCount,
                    focusOverlapDuration: metrics.focusOverlapDuration
                ))
            }

            var projectUsage = TokenUsage.zero
            var projectCost = 0.0
            var projectMessageCount = 0
            var projectSessionIDs = Set<String>()
            var projectFocusDuration = 0.0
            var totalVisibleDuration = 0.0
            var latestVisibleActivity = project.latestActivity
            for interval in visible {
                totalVisibleDuration += interval.duration
                if interval.end > latestVisibleActivity {
                    latestVisibleActivity = interval.end
                }
            }
            for segment in segments {
                projectUsage += segment.usage
                projectCost += segment.cost
                projectMessageCount += segment.messageCount
                projectFocusDuration += segment.focusOverlapDuration
                for sessionID in segment.sessionIDs {
                    projectSessionIDs.insert(sessionID)
                }
            }

            return GanttProjectTimeline(
                id: project.id,
                displayName: project.displayName,
                path: project.path,
                providers: project.providers,
                segments: segments,
                totalDuration: totalVisibleDuration,
                latestActivity: latestVisibleActivity,
                sessionCount: projectSessionIDs.count,
                messageCount: projectMessageCount,
                totalUsage: projectUsage,
                totalCost: projectCost,
                focusOverlapDuration: projectFocusDuration
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalDuration != rhs.totalDuration {
                return lhs.totalDuration > rhs.totalDuration
            }
            if lhs.latestActivity != rhs.latestActivity {
                return lhs.latestActivity > rhs.latestActivity
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        var totalDuration = 0.0
        var totalTokens = 0
        var totalCost = 0.0
        var totalMessageCount = 0
        var segmentCount = 0
        for row in rows {
            totalDuration += row.totalDuration
            totalTokens += row.totalUsage.total
            totalCost += row.totalCost
            totalMessageCount += row.messageCount
            segmentCount += row.segments.count
        }
        let inferredSignals = inferredSignals(
            sessions: sessions,
            countedSessionIDs: countedSessionIDs,
            period: period.dataRange
        )
        let load = makeLoadSnapshot(
            projects: rows,
            domain: period.domain,
            focusItems: clippedFocusItems,
            usageLimitReports: usageLimitReports
        )
        let metrics = GanttMetricSummary(
            activeDuration: totalDuration,
            tokens: totalTokens,
            cost: totalCost,
            messageCount: totalMessageCount,
            sessionCount: countedSessionIDs.count,
            segmentCount: segmentCount,
            commitCount: externalMetrics.commitCount,
            failureSignals: externalMetrics.failureSignals + inferredSignals.failureSignals,
            retrySignals: externalMetrics.retrySignals + inferredSignals.retrySignals,
            contextSwitches: load.summary.contextSwitches
        )

        return GanttTimelineSnapshot(
            range: period.range,
            activityMode: activityMode,
            domain: period.domain,
            dataRange: period.dataRange,
            projects: rows,
            sourceSessionCount: sessions.count,
            totalDuration: totalDuration,
            segmentCount: segmentCount,
            metrics: metrics,
            load: load,
            commitMarkers: externalMetrics.commitMarkers,
            baselineComparison: nil,
            renderRevisionID: GanttTimelineSnapshot.renderRevisionID(
                range: period.range,
                activityMode: activityMode,
                domain: period.domain,
                dataRange: period.dataRange,
                projects: rows,
                sourceSessionCount: sessions.count
            )
        )
    }

    static func baselineComparison(
        current: GanttTimelineSnapshot,
        baseline: GanttTimelineSnapshot
    ) -> GanttBaselineComparison {
        GanttBaselineComparison(
            current: current.metrics,
            baseline: baseline.metrics,
            baselineDomain: baseline.domain
        )
    }

    static func gitExternalMetrics(
        sessions: [Session],
        during interval: DateInterval,
        projectIDFilter: String? = nil
    ) -> GanttExternalMetrics {
        let projectCwds = sessions.compactMap { session -> ProjectCwdScope? in
            let identity = projectIdentity(for: session)
            if let projectIDFilter, identity.id != projectIDFilter {
                return nil
            }
            guard let stats = session.stats,
                  stats.activityIntervals.contains(where: { ActivityAnalyzer.clip($0, to: interval) != nil }) else {
                return nil
            }
            guard let cwd = normalizedPath(session.cwd) else { return nil }
            return ProjectCwdScope(projectID: identity.id, cwd: cwd)
        }
        guard !projectCwds.isEmpty else { return .zero }
        let git = GitAnalyzer()
        guard git.isAvailable else { return .zero }
        let repoScopes = repoScopes(for: projectCwds, git: git)
        guard !repoScopes.isEmpty else { return .zero }
        let email = git.currentUserEmail()
        var commitsByRepoID: [String: [GitCommit]] = [:]
        var countedRepoIDs = Set<String>()
        var commitCount = 0
        let markers = repoScopes.flatMap { scope in
            let commits: [GitCommit]
            if let cached = commitsByRepoID[scope.repo.id] {
                commits = cached
            } else {
                commits = git.commits(in: scope.repo, during: interval, authorEmail: email)
                commitsByRepoID[scope.repo.id] = commits
            }
            if countedRepoIDs.insert(scope.repo.id).inserted {
                commitCount += commits.count
            }
            return commits.map { commit in
                GanttCommitMarker(
                    id: commit.id,
                    projectID: scope.projectID,
                    date: commit.date,
                    repoName: scope.repo.displayName,
                    shortHash: commit.shortHash,
                    subject: commit.subject
                )
            }
        }
        .sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id < rhs.id
        }
        return GanttExternalMetrics(
            commitCount: commitCount,
            failureSignals: 0,
            retrySignals: 0,
            commitMarkers: Array(markers.prefix(48))
        )
    }

    private static func repoScopes(for projectCwds: [ProjectCwdScope], git: GitAnalyzer) -> [ProjectRepoScope] {
        var seenScopes = Set<String>()
        var scopes: [ProjectRepoScope] = []
        for projectCwd in projectCwds.sorted(by: { lhs, rhs in
            if lhs.projectID != rhs.projectID { return lhs.projectID < rhs.projectID }
            return lhs.cwd < rhs.cwd
        }) {
            guard FileManager.default.fileExists(atPath: projectCwd.cwd),
                  let repo = git.repo(forCwd: projectCwd.cwd) else { continue }
            let key = "\(projectCwd.projectID)\u{1f}\(repo.id)"
            guard seenScopes.insert(key).inserted else { continue }
            scopes.append(ProjectRepoScope(projectID: projectCwd.projectID, repo: repo))
        }
        return scopes
    }

    static func loadSnapshot(
        replacingUsageLimitReports reports: [UsageLimitReport],
        in load: GanttLoadSnapshot,
        domain: DateInterval
    ) -> GanttLoadSnapshot {
        var groups = load.groups.filter { $0.kind != .usageLimit }
        let usageLimit = makeUsageLimitLoadGroup(reports: reports, domain: domain)
        if !usageLimit.lanes.isEmpty {
            groups.append(usageLimit)
        }
        let topLane = groups
            .flatMap(\.lanes)
            .max { lhs, rhs in
                if lhs.totalDuration != rhs.totalDuration { return lhs.totalDuration < rhs.totalDuration }
                return lhs.tokens < rhs.tokens
            }
        let summary = GanttLoadSummary(
            focusBlocks: load.summary.focusBlocks,
            contextSwitches: load.summary.contextSwitches,
            topLoadTitle: topLane?.title,
            topLoadDuration: topLane?.totalDuration ?? 0,
            highestTokenWindow: load.summary.highestTokenWindow,
            highestTokenWindowTokens: load.summary.highestTokenWindowTokens,
            focusScore: load.summary.focusScore
        )
        return GanttLoadSnapshot(groups: groups, summary: summary)
    }

    static func merge(_ intervals: [DateInterval], gap: TimeInterval) -> [DateInterval] {
        let sorted = intervals
            .filter { $0.duration > 0 }
            .sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }

        var out: [DateInterval] = []
        for interval in sorted.dropFirst() {
            if interval.start.timeIntervalSince(current.end) <= gap {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                out.append(current)
                current = interval
            }
        }
        out.append(current)
        return out
    }

    static func projectIdentity(for session: Session) -> (id: String, displayName: String, path: String?) {
        if let cwd = normalizedPath(session.cwd) {
            let name = (cwd as NSString).lastPathComponent
            return (cwd, name.isEmpty ? session.projectDisplayName : name, cwd)
        }
        return ("\(session.provider.rawValue):\(session.projectDirectoryName)", session.projectDisplayName, nil)
    }

    static func normalizedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    private static func aggregateSegmentMetrics(
        interval: DateInterval,
        records: [SourceInterval],
        focus: [DateInterval]
    ) -> SegmentMetrics {
        var providers = Set<ProviderKind>()
        var sessionIDs = Set<String>()
        var sessionTitlesByID: [String: String] = [:]
        var usage = TokenUsage.zero
        var cost = 0.0
        var messageCount = 0
        var modelsByID: [String: (usage: TokenUsage, cost: Double, messages: Int)] = [:]

        for record in records {
            guard let overlap = ActivityAnalyzer.clip(record.interval, to: interval) else { continue }
            let fraction = record.profile.fraction(for: overlap.duration)
            guard fraction > 0 else { continue }
            providers.insert(record.profile.provider)
            sessionIDs.insert(record.profile.sessionID)
            sessionTitlesByID[record.profile.sessionID] = record.profile.title
            usage += scaled(record.profile.totalUsage, by: fraction)
            cost += record.profile.totalCost * fraction
            messageCount += roundedInt(Double(record.profile.messageCount) * fraction)

            for model in record.profile.models {
                let scaledUsage = scaled(model.usage, by: fraction)
                let scaledCost = model.cost * fraction
                let scaledMessages = roundedInt(Double(model.messageCount) * fraction)
                var acc = modelsByID[model.model] ?? (.zero, 0, 0)
                acc.usage += scaledUsage
                acc.cost += scaledCost
                acc.messages += scaledMessages
                modelsByID[model.model] = acc
            }
        }

        let focusOverlapDuration = ActivityAnalyzer.intersection([interval], focus)
            .reduce(0) { $0 + $1.duration }
        let titles = sessionIDs.sorted().compactMap { sessionTitlesByID[$0] }
        let models = modelsByID
            .map { model, value in
                GanttModelMetric(
                    model: model,
                    usage: value.usage,
                    cost: value.cost,
                    messageCount: value.messages
                )
            }
            .sorted {
                if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
                return $0.model.localizedStandardCompare($1.model) == .orderedAscending
            }

        return SegmentMetrics(
            providers: providers,
            sessionIDs: sessionIDs,
            sessionTitles: Array(titles.prefix(4)),
            models: models,
            usage: usage,
            cost: cost,
            messageCount: messageCount,
            focusOverlapDuration: focusOverlapDuration
        )
    }

    private static func makeLoadSnapshot(
        projects: [GanttProjectTimeline],
        domain: DateInterval,
        focusItems: [AppFocusInterval],
        usageLimitReports: [UsageLimitReport]
    ) -> GanttLoadSnapshot {
        let provider = makeProviderLoadGroup(projects: projects)
        let model = makeModelLoadGroup(projects: projects)
        let project = makeProjectLoadGroup(projects: projects)
        let focus = makeFocusLoadGroup(focusItems: focusItems, domain: domain)
        let usageLimit = makeUsageLimitLoadGroup(reports: usageLimitReports, domain: domain)
        let groups = [provider, model, project, focus, usageLimit].filter { !$0.lanes.isEmpty }
        let providerSwitches = contextSwitches(projects: projects)
        let topLane = groups
            .flatMap(\.lanes)
            .max { lhs, rhs in
                if lhs.totalDuration != rhs.totalDuration { return lhs.totalDuration < rhs.totalDuration }
                return lhs.tokens < rhs.tokens
            }
        let highestWindow = highestTokenWindow(projects: projects)
        let totalDuration = projects.reduce(0) { $0 + $1.totalDuration }
        let deepDuration = projects
            .flatMap(\.segments)
            .filter { $0.duration >= 20 * 60 }
            .reduce(0) { $0 + $1.duration }
        let focusScore = totalDuration > 0
            ? max(0, min(100, (deepDuration / totalDuration) * 100 - Double(providerSwitches) * 1.5))
            : 0
        let summary = GanttLoadSummary(
            focusBlocks: projects.flatMap(\.segments).filter { $0.duration >= 20 * 60 }.count,
            contextSwitches: providerSwitches,
            topLoadTitle: topLane?.title,
            topLoadDuration: topLane?.totalDuration ?? 0,
            highestTokenWindow: highestWindow.interval,
            highestTokenWindowTokens: highestWindow.tokens,
            focusScore: focusScore
        )
        return GanttLoadSnapshot(groups: groups, summary: summary)
    }

    private static func makeProviderLoadGroup(projects: [GanttProjectTimeline]) -> GanttLoadGroup {
        var lanes: [ProviderKind: [GanttLoadSegment]] = [:]
        for project in projects {
            for segment in project.segments {
                let providers = segment.providerList.isEmpty ? project.providerList : segment.providerList
                let divisor = max(1, providers.count)
                for provider in providers {
                    lanes[provider, default: []].append(GanttLoadSegment(
                        id: "\(provider.rawValue)|\(segment.id)",
                        interval: segment.interval,
                        tokens: segment.usage.total / divisor,
                        cost: segment.cost / Double(divisor),
                        intensity: min(1, max(0.15, segment.duration / 3_600))
                    ))
                }
            }
        }
        return GanttLoadGroup(kind: .provider, lanes: lanes.map { provider, segments in
            makeLane(
                id: provider.rawValue,
                title: provider.displayName,
                subtitle: nil,
                segments: segments
            )
        }.sorted(by: laneSort))
    }

    private static func makeModelLoadGroup(projects: [GanttProjectTimeline]) -> GanttLoadGroup {
        var lanes: [String: [GanttLoadSegment]] = [:]
        for project in projects {
            for segment in project.segments {
                for model in segment.models where model.tokens > 0 {
                    lanes[model.model, default: []].append(GanttLoadSegment(
                        id: "\(model.model)|\(segment.id)",
                        interval: segment.interval,
                        tokens: model.tokens,
                        cost: model.cost,
                        intensity: min(1, max(0.15, Double(model.tokens) / 120_000))
                    ))
                }
            }
        }
        return GanttLoadGroup(kind: .model, lanes: lanes.map { model, segments in
            makeLane(id: model, title: shortModelName(model), subtitle: model, segments: segments)
        }.sorted(by: laneSort))
    }

    private static func makeProjectLoadGroup(projects: [GanttProjectTimeline]) -> GanttLoadGroup {
        GanttLoadGroup(kind: .project, lanes: projects.map { project in
            makeLane(
                id: project.id,
                title: project.displayName,
                subtitle: project.path,
                segments: project.segments.map {
                    GanttLoadSegment(
                        id: $0.id,
                        interval: $0.interval,
                        tokens: $0.usage.total,
                        cost: $0.cost,
                        intensity: min(1, max(0.15, $0.duration / 3_600))
                    )
                }
            )
        }.sorted(by: laneSort))
    }

    private static func makeFocusLoadGroup(
        focusItems: [AppFocusInterval],
        domain: DateInterval
    ) -> GanttLoadGroup {
        var lanes: [String: [GanttLoadSegment]] = [:]
        for item in focusItems {
            guard let clipped = ActivityAnalyzer.clip(item.interval, to: domain) else { continue }
            let key = item.bundleID.isEmpty ? "focus" : item.bundleID
            lanes[key, default: []].append(GanttLoadSegment(
                id: "\(key)|\(clipped.start.timeIntervalSinceReferenceDate)",
                interval: clipped,
                tokens: 0,
                cost: 0,
                intensity: min(1, max(0.2, clipped.duration / 3_600))
            ))
        }
        return GanttLoadGroup(kind: .focus, lanes: lanes.map { bundleID, segments in
            makeLane(
                id: bundleID,
                title: bundleID.isEmpty ? String(localized: "Focused app") : bundleID,
                subtitle: String(localized: "Foreground coding surface or terminal"),
                segments: segments
            )
        }.sorted(by: laneSort))
    }

    private static func makeUsageLimitLoadGroup(
        reports: [UsageLimitReport],
        domain: DateInterval
    ) -> GanttLoadGroup {
        var lanes: [GanttLoadLane] = []
        for report in reports {
            guard let snapshot = report.snapshot else { continue }
            for window in snapshot.windows {
                guard let resetAt = window.resetAt,
                      let minutes = window.windowMinutes else { continue }
                let start = resetAt.addingTimeInterval(TimeInterval(-minutes * 60))
                guard let clipped = ActivityAnalyzer.clip(DateInterval(start: start, end: resetAt), to: domain) else { continue }
                let title = "\(report.provider.displayName) \(window.label)"
                lanes.append(makeLane(
                    id: "\(report.provider.rawValue)|\(window.id)",
                    title: title,
                    subtitle: String(localized: "Usage limit window"),
                    segments: [
                        GanttLoadSegment(
                            id: "\(report.provider.rawValue)|\(window.id)|\(resetAt.timeIntervalSinceReferenceDate)",
                            interval: clipped,
                            tokens: 0,
                            cost: 0,
                            intensity: window.clampedUsedPercent / 100
                        ),
                    ]
                ))
            }
        }
        return GanttLoadGroup(kind: .usageLimit, lanes: lanes.sorted(by: laneSort))
    }

    private static func makeLane(
        id: String,
        title: String,
        subtitle: String?,
        segments: [GanttLoadSegment]
    ) -> GanttLoadLane {
        let merged = mergeLoadSegments(segments)
        let totalDuration = ActivityAnalyzer.union(merged.map(\.interval)).reduce(0) { $0 + $1.duration }
        let tokens = merged.reduce(0) { $0 + $1.tokens }
        let cost = merged.reduce(0) { $0 + $1.cost }
        let intensity = merged.map(\.intensity).max() ?? 0
        return GanttLoadLane(
            id: id,
            title: title,
            subtitle: subtitle,
            segments: merged,
            totalDuration: totalDuration,
            tokens: tokens,
            cost: cost,
            intensity: intensity
        )
    }

    private static func mergeLoadSegments(_ segments: [GanttLoadSegment]) -> [GanttLoadSegment] {
        let sorted = segments.sorted { $0.interval.start < $1.interval.start }
        var out: [GanttLoadSegment] = []
        for segment in sorted {
            if let last = out.last, segment.interval.start <= last.interval.end.addingTimeInterval(defaultMergeGap) {
                let merged = GanttLoadSegment(
                    id: "\(last.id)+\(segment.id)",
                    interval: DateInterval(start: last.interval.start, end: max(last.interval.end, segment.interval.end)),
                    tokens: last.tokens + segment.tokens,
                    cost: last.cost + segment.cost,
                    intensity: max(last.intensity, segment.intensity)
                )
                out[out.count - 1] = merged
            } else {
                out.append(segment)
            }
        }
        return out
    }

    private static func laneSort(lhs: GanttLoadLane, rhs: GanttLoadLane) -> Bool {
        if lhs.totalDuration != rhs.totalDuration { return lhs.totalDuration > rhs.totalDuration }
        if lhs.tokens != rhs.tokens { return lhs.tokens > rhs.tokens }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func contextSwitches(projects: [GanttProjectTimeline]) -> Int {
        let events = projects.flatMap { project in
            project.segments.map { segment in
                (
                    start: segment.interval.start,
                    end: segment.interval.end,
                    key: "\(segment.providerList.first?.rawValue ?? "unknown")|\(project.id)"
                )
            }
        }
        .sorted { $0.start < $1.start }
        guard events.count > 1 else { return 0 }

        var switches = 0
        var previous = events[0]
        for event in events.dropFirst() {
            if event.key != previous.key,
               event.start.timeIntervalSince(previous.end) <= 30 * 60 {
                switches += 1
            }
            previous = event
        }
        return switches
    }

    private static func highestTokenWindow(projects: [GanttProjectTimeline], calendar: Calendar = .current) -> (interval: DateInterval?, tokens: Int) {
        var byHour: [Date: Int] = [:]
        for segment in projects.flatMap(\.segments) where segment.usage.total > 0 {
            let hour = calendar.dateInterval(of: .hour, for: segment.interval.start)?.start ?? segment.interval.start
            byHour[hour, default: 0] += segment.usage.total
        }
        guard let winner = byHour.max(by: { $0.value < $1.value }) else {
            return (nil, 0)
        }
        let end = calendar.date(byAdding: .hour, value: 1, to: winner.key) ?? winner.key.addingTimeInterval(3_600)
        return (DateInterval(start: winner.key, end: end), winner.value)
    }

    private static func inferredSignals(
        sessions: [Session],
        countedSessionIDs: Set<String>,
        period: DateInterval
    ) -> (failureSignals: Int, retrySignals: Int) {
        let failureWords = ["fail", "failed", "error", "crash", "exception", "broken", "bug", "fix"]
        let retryWords = ["retry", "rerun", "again", "attempt", "re-run", "rebuild"]
        var failures = 0
        var retries = 0
        for session in sessions where countedSessionIDs.contains(session.id) {
            let activity = session.stats?.lastActivity ?? session.lastModified
            guard period.contains(activity) else { continue }
            let text = [
                session.stats?.title ?? "",
                session.projectDisplayName,
                session.externalID,
            ]
            .joined(separator: " ")
            .lowercased()
            if failureWords.contains(where: { text.contains($0) }) { failures += 1 }
            if retryWords.contains(where: { text.contains($0) }) { retries += 1 }
        }
        return (failures, retries)
    }

    private static func scaled(_ usage: TokenUsage, by fraction: Double) -> TokenUsage {
        TokenUsage(
            inputTokens: roundedInt(Double(usage.inputTokens) * fraction),
            outputTokens: roundedInt(Double(usage.outputTokens) * fraction),
            cacheReadTokens: roundedInt(Double(usage.cacheReadTokens) * fraction),
            cacheCreation5mTokens: roundedInt(Double(usage.cacheCreation5mTokens) * fraction),
            cacheCreation1hTokens: roundedInt(Double(usage.cacheCreation1hTokens) * fraction)
        )
    }

    private static func roundedInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return max(0, Int(value.rounded()))
    }

    private static func shortModelName(_ model: String) -> String {
        let trimmed = model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "gpt-", with: "")
            .replacingOccurrences(of: "codex-", with: "")
        return trimmed.isEmpty ? model : trimmed
    }

    private struct MutableProject {
        let id: String
        let displayName: String
        let path: String?
        var providers: Set<ProviderKind>
        var records: [SourceInterval]
        var latestActivity: Date
    }

    private struct ProjectCwdScope {
        let projectID: String
        let cwd: String
    }

    private struct ProjectRepoScope {
        let projectID: String
        let repo: GitRepo
    }

    private struct SourceInterval {
        let interval: DateInterval
        let profile: SessionUsageProfile
    }

    private struct SessionUsageProfile {
        let sessionID: String
        let title: String
        let provider: ProviderKind
        let activeDuration: TimeInterval
        let models: [GanttModelMetric]
        let totalUsage: TokenUsage
        let totalCost: Double
        let messageCount: Int

        init(session: Session, activeIntervals: [DateInterval]) {
            let stats = session.stats
            sessionID = session.id
            title = stats?.title ?? session.projectDisplayName
            provider = session.provider
            activeDuration = max(1, ActivityAnalyzer.union(activeIntervals).reduce(0) { $0 + $1.duration })
            models = (stats?.models ?? []).map {
                GanttModelMetric(
                    model: $0.model,
                    usage: $0.usage,
                    cost: $0.estimatedCost,
                    messageCount: $0.messageCount
                )
            }
            totalUsage = stats?.totalUsage ?? .zero
            totalCost = stats?.totalCost ?? 0
            messageCount = stats?.messageCount ?? 0
        }

        func fraction(for duration: TimeInterval) -> Double {
            guard duration > 0, activeDuration > 0 else { return 0 }
            return min(1, max(0, duration / activeDuration))
        }
    }

    private struct SegmentMetrics {
        let providers: Set<ProviderKind>
        let sessionIDs: Set<String>
        let sessionTitles: [String]
        let models: [GanttModelMetric]
        let usage: TokenUsage
        let cost: Double
        let messageCount: Int
        let focusOverlapDuration: TimeInterval
    }
}
