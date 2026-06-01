import Foundation
import Observation

@MainActor
@Observable
final class GanttViewModel {
    var selectedDate: Date = Calendar.current.startOfDay(for: .now) {
        didSet { if selectedDate != oldValue { reloadToken &+= 1 } }
    }

    var range: GanttRange = .day {
        didSet { if range != oldValue { reloadToken &+= 1 } }
    }

    var activityMode: GanttActivityMode = .aiActive {
        didSet { if activityMode != oldValue { reloadToken &+= 1 } }
    }

    private(set) var permissionState: ActivityPermissionState = .ok
    private(set) var snapshot: GanttTimelineSnapshot
    private(set) var isLoading = false
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
        let period = GanttRange.day.period(containing: Calendar.current.startOfDay(for: .now))
        self.snapshot = .empty(period: period, activityMode: .aiActive)
    }

    var canStepForward: Bool {
        let nextDate = range.stepping(selectedDate, by: 1, calendar: calendar)
        return range.period(containing: nextDate, calendar: calendar).domain.start <= Date.now
    }

    var period: GanttPeriod {
        range.period(containing: selectedDate, calendar: calendar)
    }

    var periodLabel: String {
        let period = period
        switch range {
        case .day:
            return Format.day(period.domain.start)
        case .week:
            let end = period.domain.end.addingTimeInterval(-1)
            return "\(Format.day(period.domain.start)) - \(Format.day(end))"
        case .month:
            return period.domain.start.formatted(.dateTime.month(.wide).year())
        }
    }

    func stepPeriod(_ delta: Int) {
        let next = range.stepping(selectedDate, by: delta, calendar: calendar)
        selectedDate = min(next, Date.now)
    }

    func bumpReload() {
        reloadToken &+= 1
    }

    private enum Outcome: Sendable {
        case failure(ScreenTimeService.Failure)
        case snapshot(GanttTimelineSnapshot)
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

        let requestedPeriod = period
        let requestedMode = activityMode
        let focusIntervalLoader = self.focusIntervalLoader
        let focusBundleIDs = codingSurfaceBundleIDs.union(cliHostBundleIDs)

        let outcome = await Task.detached(priority: .userInitiated) { () -> Outcome in
            switch requestedMode {
            case .aiActive:
                return .snapshot(GanttTimelineBuilder.build(
                    sessions: sessions,
                    period: requestedPeriod,
                    activityMode: requestedMode
                ))
            case .assistedFocus:
                switch await focusIntervalLoader(requestedPeriod.dataRange, focusBundleIDs) {
                case .failure(let failure):
                    return .failure(failure)
                case .success(let focus):
                    return .snapshot(GanttTimelineBuilder.build(
                        sessions: sessions,
                        period: requestedPeriod,
                        activityMode: requestedMode,
                        focusIntervals: focus.map(\.interval)
                    ))
                }
            }
        }.value

        guard reloadID == activeReloadID, !Task.isCancelled else { return }

        switch outcome {
        case .failure(.noFullDiskAccess):
            permissionState = .needsFullDiskAccess
            snapshot = .empty(period: requestedPeriod, activityMode: requestedMode, sourceSessionCount: sessions.count)
        case .failure(.queryFailed(let message)):
            Log.app.error("Gantt Screen Time query failed: \(message, privacy: .public)")
            permissionState = .ok
            snapshot = .empty(period: requestedPeriod, activityMode: requestedMode, sourceSessionCount: sessions.count)
        case .snapshot(let nextSnapshot):
            permissionState = .ok
            snapshot = nextSnapshot
        }
    }

    func refreshPermissionState() {
        guard activityMode == .assistedFocus else {
            permissionState = .ok
            return
        }
        permissionState = ScreenTimeService.canRead() ? .ok : .needsFullDiskAccess
    }
}
