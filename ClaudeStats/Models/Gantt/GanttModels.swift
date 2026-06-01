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

    var totalDuration: TimeInterval {
        projects.reduce(0) { $0 + $1.totalDuration }
    }

    var segmentCount: Int {
        projects.reduce(0) { $0 + $1.segments.count }
    }

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
            sourceSessionCount: sourceSessionCount
        )
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

    var duration: TimeInterval {
        interval.duration
    }
}
