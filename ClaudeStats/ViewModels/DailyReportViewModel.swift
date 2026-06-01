import Foundation
import Observation

@MainActor
@Observable
final class DailyReportViewModel {
    private(set) var displayedMonthStart: Date
    private(set) var selectedDate: Date
    private(set) var snapshot: DailyReportMonthSnapshot
    private(set) var isLoading = false
    private(set) var reloadToken: UInt64 = 0

    @ObservationIgnored private var activeReloadID: UInt64 = 0
    @ObservationIgnored private let gitActivityProvider: any DailyReportGitActivityProviding
    private let calendar: Calendar

    init(
        calendar: Calendar = .current,
        gitActivityProvider: any DailyReportGitActivityProviding = DailyReportGitActivityProvider()
    ) {
        self.calendar = calendar
        self.gitActivityProvider = gitActivityProvider
        let today = calendar.startOfDay(for: .now)
        let monthStart = Self.monthStart(for: today, calendar: calendar)
        selectedDate = today
        displayedMonthStart = monthStart
        snapshot = .empty(month: monthStart, calendar: calendar)
    }

    var monthTitle: String {
        displayedMonthStart.formatted(.dateTime.month(.wide).year())
    }

    var selectedDaySummary: DailyReportDaySummary {
        snapshot.summary(on: selectedDate, calendar: calendar)
    }

    var todaySummary: DailyReportDaySummary {
        snapshot.summary(on: calendar.startOfDay(for: .now), calendar: calendar)
    }

    var canStepForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: displayedMonthStart) else { return false }
        return Self.monthStart(for: next, calendar: calendar) <= Self.monthStart(for: .now, calendar: calendar)
    }

    func stepMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: displayedMonthStart) else { return }
        let monthStart = Self.monthStart(for: next, calendar: calendar)
        displayedMonthStart = monthStart
        if !DailyReportBuilder.monthInterval(for: monthStart, calendar: calendar).contains(selectedDate) {
            selectedDate = monthStart
        }
        reloadToken &+= 1
    }

    func selectDate(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        selectedDate = day
        let monthStart = Self.monthStart(for: day, calendar: calendar)
        if monthStart != displayedMonthStart {
            displayedMonthStart = monthStart
            reloadToken &+= 1
        }
    }

    func showToday() {
        selectDate(.now)
    }

    func reload(sessions: [Session]) async {
        activeReloadID &+= 1
        let reloadID = activeReloadID
        isLoading = true
        defer {
            if reloadID == activeReloadID {
                isLoading = false
            }
        }

        let month = displayedMonthStart
        let calendar = calendar
        let gitActivityProvider = gitActivityProvider
        let result = await Task.detached(priority: .userInitiated) {
            let visibleInterval = DailyReportBuilder.monthInterval(for: month, calendar: calendar)
            let projectPaths = DailyReportBuilder.projectPaths(
                sessions: sessions,
                in: visibleInterval,
                calendar: calendar
            )
            let gitCounts = await gitActivityProvider.commitCounts(
                for: projectPaths,
                in: visibleInterval,
                calendar: calendar
            )
            return DailyReportBuilder.buildMonth(
                sessions: sessions,
                month: month,
                gitCommitCounts: gitCounts,
                calendar: calendar
            )
        }.value

        guard reloadID == activeReloadID, !Task.isCancelled else { return }
        snapshot = result
    }

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}
