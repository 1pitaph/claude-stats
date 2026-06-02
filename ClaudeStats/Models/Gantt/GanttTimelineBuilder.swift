import Foundation

enum GanttTimelineBuilder {
    static let defaultMergeGap: TimeInterval = 10 * 60

    static func build(
        sessions: [Session],
        period: GanttPeriod,
        activityMode: GanttActivityMode,
        focusIntervals: [DateInterval] = [],
        mergeGap: TimeInterval = Self.defaultMergeGap,
        projectIDFilter: String? = nil
    ) -> GanttTimelineSnapshot {
        var projects: [String: MutableProject] = [:]

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

            var project = projects[identity.id] ?? MutableProject(
                id: identity.id,
                displayName: identity.displayName,
                path: identity.path,
                providers: [],
                intervals: [],
                latestActivity: period.dataRange.start
            )

            project.providers.insert(session.provider)
            project.intervals.append(contentsOf: intervals)
            if let latest = intervals.map(\.end).max(), latest > project.latestActivity {
                project.latestActivity = latest
            }
            projects[identity.id] = project
        }

        let focus = ActivityAnalyzer.union(focusIntervals.compactMap {
            ActivityAnalyzer.clip($0, to: period.dataRange)
        })

        let rows = projects.values.compactMap { project -> GanttProjectTimeline? in
            let active = ActivityAnalyzer.union(project.intervals)
            let visible: [DateInterval]
            switch activityMode {
            case .aiActive:
                visible = merge(active, gap: mergeGap)
            case .assistedFocus:
                visible = merge(ActivityAnalyzer.intersection(active, focus), gap: mergeGap)
            }
            guard !visible.isEmpty else { return nil }

            let segments = visible.map { interval in
                GanttTimelineSegment(
                    id: "\(project.id)|\(interval.start.timeIntervalSinceReferenceDate)|\(interval.end.timeIntervalSinceReferenceDate)",
                    interval: interval
                )
            }
            return GanttProjectTimeline(
                id: project.id,
                displayName: project.displayName,
                path: project.path,
                providers: project.providers,
                segments: segments,
                totalDuration: visible.reduce(0) { $0 + $1.duration },
                latestActivity: visible.map(\.end).max() ?? project.latestActivity
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

        let totalDuration = rows.reduce(0) { $0 + $1.totalDuration }
        let segmentCount = rows.reduce(0) { $0 + $1.segments.count }

        return GanttTimelineSnapshot(
            range: period.range,
            activityMode: activityMode,
            domain: period.domain,
            dataRange: period.dataRange,
            projects: rows,
            sourceSessionCount: sessions.count,
            totalDuration: totalDuration,
            segmentCount: segmentCount,
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

    private static func projectIdentity(for session: Session) -> (id: String, displayName: String, path: String?) {
        if let cwd = normalizedPath(session.cwd) {
            let name = (cwd as NSString).lastPathComponent
            return (cwd, name.isEmpty ? session.projectDisplayName : name, cwd)
        }
        return ("\(session.provider.rawValue):\(session.projectDirectoryName)", session.projectDisplayName, nil)
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    private struct MutableProject {
        let id: String
        let displayName: String
        let path: String?
        var providers: Set<ProviderKind>
        var intervals: [DateInterval]
        var latestActivity: Date
    }
}
