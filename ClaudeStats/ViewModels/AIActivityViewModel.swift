import Foundation
import Observation

/// Range the AI activity view is scoped to.
enum ActivityRange: String, CaseIterable, Identifiable, Sendable {
    case day, last7Days, last30Days
    var id: String { rawValue }
    var shortLabel: String {
        switch self {
        case .day: "Day"
        case .last7Days: "7D"
        case .last30Days: "30D"
        }
    }
    var mainWindowLabel: String {
        switch self {
        case .day: "Day"
        case .last7Days: "Weekly"
        case .last30Days: "Monthly"
        }
    }
    /// Number of days the trend modes span (1 for `.day`, unused there).
    var dayCount: Int {
        switch self {
        case .day: 1
        case .last7Days: 7
        case .last30Days: 30
        }
    }
    var isTrend: Bool { self != .day }
}

enum ActivityPermissionState: Sendable, Equatable {
    case unknown
    case ok
    case needsFullDiskAccess
}

@MainActor
@Observable
final class AIActivityViewModel {
    var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    var range: ActivityRange = .day {
        didSet { if range != oldValue { reloadToken &+= 1 } }
    }
    private(set) var permissionState: ActivityPermissionState = .unknown
    private(set) var dayActivity: DayActivity?
    private(set) var trend: [DayActivity] = []
    private(set) var isLoading = false

    /// Bumps whenever something the view should re-fetch for changes; the view
    /// drives `.task(id:)` off it.
    private(set) var reloadToken: UInt64 = 0

    @ObservationIgnored
    private var activeReloadID: UInt64 = 0
    @ObservationIgnored
    private let focusIntervalLoader: @Sendable (DateInterval, Set<String>) async -> Result<[AppFocusInterval], ScreenTimeService.Failure>
    private let calendar = Calendar.current

    init(
        focusIntervalLoader: @escaping @Sendable (DateInterval, Set<String>) async -> Result<[AppFocusInterval], ScreenTimeService.Failure> = { range, bundleIDs in
            ScreenTimeService().focusIntervals(in: range, bundleIDs: bundleIDs)
        }
    ) {
        self.focusIntervalLoader = focusIntervalLoader
    }

    var today: Date { calendar.startOfDay(for: .now) }
    var canStepForward: Bool { selectedDay < today }

    func stepDay(_ delta: Int) {
        guard let d = calendar.date(byAdding: .day, value: delta, to: selectedDay) else { return }
        let clamped = min(d, today)
        if clamped != selectedDay { selectedDay = clamped; reloadToken &+= 1 }
    }

    func bumpReload() { reloadToken &+= 1 }

    /// Date span we need focus data for, given the current range.
    private func queryRange() -> DateInterval {
        switch range {
        case .day:
            return ActivityAnalyzer.dayBounds(for: selectedDay, calendar: calendar)
        case .last7Days, .last30Days:
            let end = ActivityAnalyzer.dayBounds(for: today, calendar: calendar).end
            let firstDay = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: today) ?? today
            let start = calendar.startOfDay(for: firstDay)
            return DateInterval(start: start, end: end)
        }
    }

    private func trendDays() -> [Date] {
        (0..<range.dayCount).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    private enum Outcome: Sendable {
        case failure(ScreenTimeService.Failure)
        case day(DayActivity)
        case trend([DayActivity])
    }

    func reload(
        sessions: [Session],
        codingSurfaceBundleIDs: Set<String>,
        cliHostBundleIDs: Set<String>
    ) async {
        activeReloadID &+= 1
        let reloadID = activeReloadID
        isLoading = true
        defer {
            if reloadID == activeReloadID {
                isLoading = false
            }
        }

        let range = queryRange()
        let mode = self.range
        let day = selectedDay
        let cal = calendar
        let days = trendDays()
        let bundleIDs = codingSurfaceBundleIDs.union(cliHostBundleIDs)
        let focusIntervalLoader = self.focusIntervalLoader

        let outcome = await Task.detached(priority: .userInitiated) { () -> Outcome in
            switch await focusIntervalLoader(range, bundleIDs) {
            case .failure(let f):
                return .failure(f)
            case .success(let focus):
                let codingSurfaceFocus = focus.filter { codingSurfaceBundleIDs.contains($0.bundleID) }
                let cliHostFocus = focus.filter { cliHostBundleIDs.contains($0.bundleID) }
                switch mode {
                case .day:
                    return .day(
                        ActivityAnalyzer.dayActivity(
                            day: day,
                            codingSurfaceFocus: codingSurfaceFocus,
                            cliHostFocus: cliHostFocus,
                            sessions: sessions,
                            calendar: cal
                        )
                    )
                case .last7Days, .last30Days:
                    return .trend(
                        ActivityAnalyzer.trend(
                            days: days,
                            codingSurfaceFocus: codingSurfaceFocus,
                            cliHostFocus: cliHostFocus,
                            sessions: sessions,
                            calendar: cal
                        )
                    )
                }
            }
        }.value

        guard reloadID == activeReloadID, !Task.isCancelled else { return }

        switch outcome {
        case .failure(.noFullDiskAccess):
            permissionState = .needsFullDiskAccess
            dayActivity = nil
            trend = []
        case .failure(.queryFailed(let message)):
            Log.app.error("Screen Time query failed: \(message, privacy: .public)")
            permissionState = .ok
            dayActivity = .empty(day: ActivityAnalyzer.dayBounds(for: selectedDay, calendar: calendar))
            trend = []
        case .day(let activity):
            permissionState = .ok
            dayActivity = activity
            trend = []
        case .trend(let series):
            permissionState = .ok
            dayActivity = nil
            trend = series
        }
    }

    func refreshPermissionState() {
        if permissionState != .ok {
            permissionState = ScreenTimeService.canRead() ? .ok : .needsFullDiskAccess
        }
    }
}
