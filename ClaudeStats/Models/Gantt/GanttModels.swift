import Foundation

enum GanttRange: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: String(localized: "Day")
        case .week: String(localized: "Week")
        case .month: String(localized: "Month")
        }
    }

    var help: String {
        switch self {
        case .day: String(localized: "Show day range")
        case .week: String(localized: "Show week range")
        case .month: String(localized: "Show month range")
        }
    }

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    func period(containing date: Date, now: Date = .now, calendar: Calendar = .current) -> GanttPeriod {
        let domain: DateInterval
        switch self {
        case .day:
            domain = ActivityAnalyzer.dayBounds(for: date, calendar: calendar)
        case .week:
            domain = calendar.dateInterval(of: .weekOfYear, for: date)
                ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86_400)
        case .month:
            domain = calendar.dateInterval(of: .month, for: date)
                ?? DateInterval(start: calendar.startOfDay(for: date), duration: 30 * 86_400)
        }

        let end = max(domain.start, min(domain.end, now))
        return GanttPeriod(range: self, domain: domain, dataRange: DateInterval(start: domain.start, end: end))
    }

    func stepping(_ date: Date, by value: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: component, value: value, to: date) ?? date
    }
}

enum GanttActivityMode: String, CaseIterable, Identifiable, Sendable {
    case aiActive
    case assistedFocus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .aiActive: String(localized: "AI Active")
        case .assistedFocus: String(localized: "Assisted Focus")
        }
    }

    var help: String {
        switch self {
        case .aiActive:
            String(localized: "Track project AI session activity.")
        case .assistedFocus:
            String(localized: "Only show time when AI was active and an editor or terminal was in front.")
        }
    }
}

enum GanttFocusDataState: Equatable, Sendable {
    case available
    case noMatchingFocusData
    case queryFailed
}

struct GanttPeriod: Equatable, Sendable {
    let range: GanttRange
    let domain: DateInterval
    let dataRange: DateInterval

    static func recentSevenDays(endingAt now: Date = .now, calendar: Calendar = .current) -> GanttPeriod {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today)
            ?? today.addingTimeInterval(-6 * 86_400)
        let end = calendar.date(byAdding: .day, value: 1, to: today)
            ?? today.addingTimeInterval(86_400)
        let domain = DateInterval(start: start, end: end)
        return GanttPeriod(
            range: .week,
            domain: domain,
            dataRange: DateInterval(start: start, end: max(start, min(end, now)))
        )
    }
}

struct GanttTimelineSnapshot: Equatable, Sendable {
    let range: GanttRange
    let activityMode: GanttActivityMode
    let domain: DateInterval
    let dataRange: DateInterval
    let projects: [GanttProjectTimeline]
    let sourceSessionCount: Int
    let totalDuration: TimeInterval
    let segmentCount: Int
    let metrics: GanttMetricSummary
    let load: GanttLoadSnapshot
    let commitMarkers: [GanttCommitMarker]
    let baselineComparison: GanttBaselineComparison?
    let renderRevisionID: String

    var mostActiveProject: GanttProjectTimeline? {
        projects.first
    }

    var isEmpty: Bool {
        projects.isEmpty
    }

    static func empty(period: GanttPeriod, activityMode: GanttActivityMode, sourceSessionCount: Int = 0) -> GanttTimelineSnapshot {
        GanttTimelineSnapshot(
            range: period.range,
            activityMode: activityMode,
            domain: period.domain,
            dataRange: period.dataRange,
            projects: [],
            sourceSessionCount: sourceSessionCount,
            totalDuration: 0,
            segmentCount: 0,
            metrics: .zero,
            load: .empty,
            commitMarkers: [],
            baselineComparison: nil,
            renderRevisionID: renderRevisionID(
                range: period.range,
                activityMode: activityMode,
                domain: period.domain,
                dataRange: period.dataRange,
                projects: [],
                sourceSessionCount: sourceSessionCount
            )
        )
    }

    static func renderRevisionID(
        range: GanttRange,
        activityMode: GanttActivityMode,
        domain: DateInterval,
        dataRange: DateInterval,
        projects: [GanttProjectTimeline],
        sourceSessionCount: Int
    ) -> String {
        let projectID = projects.map { project in
            let providers = ProviderKind.allCases
                .filter { project.providers.contains($0) }
                .map(\.rawValue)
                .joined(separator: ",")
            let segments = project.segments.map { segment in
                "\(timeID(segment.interval.start))-\(timeID(segment.interval.end))"
            }
            .joined(separator: ",")
            return [
                project.id,
                project.displayName,
                project.path ?? "",
                providers,
                durationID(project.totalDuration),
                timeID(project.latestActivity),
                segments,
                String(project.sessionCount),
                String(project.totalUsage.total),
                String(project.totalCost.bitPattern),
            ]
            .joined(separator: ":")
        }
        .joined(separator: "|")

        return [
            range.rawValue,
            activityMode.rawValue,
            intervalID(domain),
            intervalID(dataRange),
            String(sourceSessionCount),
            projectID,
        ]
        .joined(separator: "#")
    }

    func withBaselineComparison(_ comparison: GanttBaselineComparison?) -> GanttTimelineSnapshot {
        GanttTimelineSnapshot(
            range: range,
            activityMode: activityMode,
            domain: domain,
            dataRange: dataRange,
            projects: projects,
            sourceSessionCount: sourceSessionCount,
            totalDuration: totalDuration,
            segmentCount: segmentCount,
            metrics: metrics,
            load: load,
            commitMarkers: commitMarkers,
            baselineComparison: comparison,
            renderRevisionID: renderRevisionID
        )
    }

    func withLoad(_ load: GanttLoadSnapshot) -> GanttTimelineSnapshot {
        GanttTimelineSnapshot(
            range: range,
            activityMode: activityMode,
            domain: domain,
            dataRange: dataRange,
            projects: projects,
            sourceSessionCount: sourceSessionCount,
            totalDuration: totalDuration,
            segmentCount: segmentCount,
            metrics: metrics,
            load: load,
            commitMarkers: commitMarkers,
            baselineComparison: baselineComparison,
            renderRevisionID: renderRevisionID
        )
    }

    private static func intervalID(_ interval: DateInterval) -> String {
        "\(timeID(interval.start))-\(timeID(interval.end))"
    }

    private static func timeID(_ date: Date) -> String {
        String(Int((date.timeIntervalSinceReferenceDate * 1_000).rounded()))
    }

    private static func durationID(_ duration: TimeInterval) -> String {
        String(Int((duration * 1_000).rounded()))
    }
}

struct GanttProjectTimeline: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let path: String?
    let providers: Set<ProviderKind>
    let segments: [GanttTimelineSegment]
    let totalDuration: TimeInterval
    let latestActivity: Date
    let sessionCount: Int
    let messageCount: Int
    let totalUsage: TokenUsage
    let totalCost: Double
    let focusOverlapDuration: TimeInterval

    var providerList: [ProviderKind] {
        ProviderKind.allCases.filter { providers.contains($0) }
    }

    var reference: GanttProjectReference {
        GanttProjectReference(id: id, displayName: displayName, path: path, providers: providers)
    }
}

struct GanttProjectReference: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let path: String?
    let providers: Set<ProviderKind>

    var providerList: [ProviderKind] {
        ProviderKind.allCases.filter { providers.contains($0) }
    }
}

struct GanttTimelineSegment: Equatable, Identifiable, Sendable {
    let id: String
    let interval: DateInterval
    let providers: Set<ProviderKind>
    let sessionIDs: Set<String>
    let sessionTitles: [String]
    let models: [GanttModelMetric]
    let usage: TokenUsage
    let cost: Double
    let messageCount: Int
    let focusOverlapDuration: TimeInterval

    var duration: TimeInterval {
        interval.duration
    }

    var providerList: [ProviderKind] {
        ProviderKind.allCases.filter { providers.contains($0) }
    }
}

struct GanttModelMetric: Equatable, Identifiable, Sendable {
    let model: String
    let usage: TokenUsage
    let cost: Double
    let messageCount: Int

    var id: String { model }
    var tokens: Int { usage.total }
}

struct GanttMetricSummary: Equatable, Sendable {
    let activeDuration: TimeInterval
    let tokens: Int
    let cost: Double
    let messageCount: Int
    let sessionCount: Int
    let segmentCount: Int
    let commitCount: Int
    let failureSignals: Int
    let retrySignals: Int
    let contextSwitches: Int

    static let zero = GanttMetricSummary(
        activeDuration: 0,
        tokens: 0,
        cost: 0,
        messageCount: 0,
        sessionCount: 0,
        segmentCount: 0,
        commitCount: 0,
        failureSignals: 0,
        retrySignals: 0,
        contextSwitches: 0
    )
}

struct GanttCommitMarker: Equatable, Identifiable, Sendable {
    let id: String
    let projectID: String
    let date: Date
    let repoName: String
    let shortHash: String
    let subject: String
}

struct GanttExternalMetrics: Equatable, Sendable {
    let commitCount: Int
    let failureSignals: Int
    let retrySignals: Int
    let commitMarkers: [GanttCommitMarker]

    init(
        commitCount: Int,
        failureSignals: Int,
        retrySignals: Int,
        commitMarkers: [GanttCommitMarker] = []
    ) {
        self.commitCount = commitCount
        self.failureSignals = failureSignals
        self.retrySignals = retrySignals
        self.commitMarkers = commitMarkers
    }

    static let zero = GanttExternalMetrics(commitCount: 0, failureSignals: 0, retrySignals: 0)
}

struct GanttBaselineComparison: Equatable, Sendable {
    let current: GanttMetricSummary
    let baseline: GanttMetricSummary
    let baselineDomain: DateInterval

    var activeDurationDelta: TimeInterval { current.activeDuration - baseline.activeDuration }
    var tokensDelta: Int { current.tokens - baseline.tokens }
    var costDelta: Double { current.cost - baseline.cost }
    var commitDelta: Int { current.commitCount - baseline.commitCount }
    var failureSignalDelta: Int { current.failureSignals - baseline.failureSignals }
    var retrySignalDelta: Int { current.retrySignals - baseline.retrySignals }
    var contextSwitchDelta: Int { current.contextSwitches - baseline.contextSwitches }
}

enum GanttLoadGroupKind: String, CaseIterable, Identifiable, Sendable {
    case provider
    case model
    case project
    case focus
    case usageLimit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .provider: String(localized: "Providers")
        case .model: String(localized: "Models")
        case .project: String(localized: "Projects")
        case .focus: String(localized: "Focus")
        case .usageLimit: String(localized: "Usage Limits")
        }
    }
}

struct GanttLoadSnapshot: Equatable, Sendable {
    let groups: [GanttLoadGroup]
    let summary: GanttLoadSummary

    static let empty = GanttLoadSnapshot(groups: [], summary: .empty)
}

struct GanttLoadGroup: Equatable, Identifiable, Sendable {
    let kind: GanttLoadGroupKind
    let lanes: [GanttLoadLane]

    var id: GanttLoadGroupKind { kind }
}

struct GanttLoadLane: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let segments: [GanttLoadSegment]
    let totalDuration: TimeInterval
    let tokens: Int
    let cost: Double
    let intensity: Double
}

struct GanttLoadSegment: Equatable, Identifiable, Sendable {
    let id: String
    let interval: DateInterval
    let tokens: Int
    let cost: Double
    let intensity: Double
}

struct GanttLoadSummary: Equatable, Sendable {
    let focusBlocks: Int
    let contextSwitches: Int
    let topLoadTitle: String?
    let topLoadDuration: TimeInterval
    let highestTokenWindow: DateInterval?
    let highestTokenWindowTokens: Int
    let focusScore: Double

    static let empty = GanttLoadSummary(
        focusBlocks: 0,
        contextSwitches: 0,
        topLoadTitle: nil,
        topLoadDuration: 0,
        highestTokenWindow: nil,
        highestTokenWindowTokens: 0,
        focusScore: 0
    )
}
