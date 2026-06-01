import Foundation

enum DailyReportSection: String, CaseIterable, Identifiable, Sendable, Hashable {
    case calendar
    case today
    case projects

    var id: String { rawValue }

    init(storedRawValue rawValue: String) {
        self = DailyReportSection(rawValue: rawValue) ?? .calendar
    }

    var title: String {
        switch self {
        case .calendar: "Calendar"
        case .today: "Today"
        case .projects: "Projects"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: AppIcon.Workspace.dailyReport
        case .today: AppIcon.Status.clock
        case .projects: AppIcon.Resource.folder
        }
    }

    var detailTitle: String {
        switch self {
        case .calendar: "Daily Report"
        case .today: "Today"
        case .projects: "Projects"
        }
    }

    var detailDescription: String {
        switch self {
        case .calendar: "AI-active projects across every provider, grouped by day."
        case .today: "A focused summary of today's project activity."
        case .projects: "Current-month project rollups across active days."
        }
    }
}

struct DailyReportDaySummary: Identifiable, Hashable, Sendable {
    let day: Date
    let projects: [DailyReportProjectDaySummary]

    var id: Date { day }
    var projectCount: Int { projects.count }
    var totalActiveDuration: TimeInterval { projects.reduce(0) { $0 + $1.activeDuration } }
    var totalTokens: Int { projects.reduce(0) { $0 + $1.tokens } }
    var totalSessions: Int { projects.reduce(0) { $0 + $1.sessionCount } }
    var totalGitCommitCount: Int { projects.reduce(0) { $0 + $1.gitCommitCount } }
    var isEmpty: Bool { projects.isEmpty }

    static func empty(day: Date) -> DailyReportDaySummary {
        DailyReportDaySummary(day: day, projects: [])
    }
}

struct DailyReportProjectDaySummary: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let path: String?
    let providers: Set<ProviderKind>
    let activeDuration: TimeInterval
    let tokens: Int
    let sessionCount: Int
    let gitCommitCount: Int
    let latestActivity: Date?

    var providerList: [ProviderKind] {
        ProviderKind.allCases.filter { providers.contains($0) }
    }
}

struct DailyReportProjectMonthSummary: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let path: String?
    let providers: Set<ProviderKind>
    let activeDays: Int
    let activeDuration: TimeInterval
    let tokens: Int
    let sessionCount: Int
    let gitCommitCount: Int
    let latestActivity: Date?

    var providerList: [ProviderKind] {
        ProviderKind.allCases.filter { providers.contains($0) }
    }
}

struct DailyReportCalendarDay: Identifiable, Hashable, Sendable {
    let date: Date
    let isInDisplayedMonth: Bool
    let summary: DailyReportDaySummary

    var id: Date { date }
}

struct DailyReportMonthSnapshot: Hashable, Sendable {
    let monthInterval: DateInterval
    let visibleDays: [DailyReportCalendarDay]
    let projects: [DailyReportProjectMonthSummary]
    let sourceSessionCount: Int

    static func empty(month: Date, calendar: Calendar = .current) -> DailyReportMonthSnapshot {
        let interval = DailyReportBuilder.monthInterval(for: month, calendar: calendar)
        let days = DailyReportBuilder.visibleDays(for: interval, summaries: [:], calendar: calendar)
        return DailyReportMonthSnapshot(
            monthInterval: interval,
            visibleDays: days,
            projects: [],
            sourceSessionCount: 0
        )
    }

    func summary(on day: Date, calendar: Calendar = .current) -> DailyReportDaySummary {
        let start = calendar.startOfDay(for: day)
        return visibleDays.first { $0.date == start }?.summary ?? .empty(day: start)
    }
}
