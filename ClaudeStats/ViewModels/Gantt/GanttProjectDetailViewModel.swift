import Foundation
import Observation

@MainActor
@Observable
final class GanttProjectDetailViewModel {
    var activityMode: GanttActivityMode {
        didSet { if activityMode != oldValue { reloadToken &+= 1 } }
    }

    private(set) var period: GanttPeriod
    private(set) var permissionState: ActivityPermissionState = .ok
    private(set) var snapshot: GanttTimelineSnapshot
    private(set) var isLoading = false
    private(set) var reloadToken: UInt64 = 0

    @ObservationIgnored
    private var activeReloadID: UInt64 = 0
    @ObservationIgnored
    private let focusIntervalLoader: @Sendable (DateInterval, Set<String>) async -> Result<[AppFocusInterval], ScreenTimeService.Failure>

    init(
        initialMode: GanttActivityMode,
        focusIntervalLoader: @escaping @Sendable (DateInterval, Set<String>) async -> Result<[AppFocusInterval], ScreenTimeService.Failure> = { range, bundleIDs in
            ScreenTimeService().focusIntervals(in: range, bundleIDs: bundleIDs)
        }
    ) {
        self.activityMode = initialMode
        self.focusIntervalLoader = focusIntervalLoader
        let period = GanttPeriod.recentSevenDays()
        self.period = period
        self.snapshot = .empty(period: period, activityMode: initialMode)
    }

    func bumpReload() {
        reloadToken &+= 1
    }

    private enum Outcome: Sendable {
        case failure(ScreenTimeService.Failure)
        case snapshot(GanttTimelineSnapshot)
    }

    func reload(
        projectID: String,
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

        let requestedPeriod = GanttPeriod.recentSevenDays()
        period = requestedPeriod
        let requestedMode = activityMode
        let focusIntervalLoader = self.focusIntervalLoader
        let focusBundleIDs = codingSurfaceBundleIDs.union(cliHostBundleIDs)

        let outcome = await Task.detached(priority: .userInitiated) { () -> Outcome in
            switch requestedMode {
            case .aiActive:
                return .snapshot(GanttTimelineBuilder.build(
                    sessions: sessions,
                    period: requestedPeriod,
                    activityMode: requestedMode,
                    projectIDFilter: projectID
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
                        focusIntervals: focus.map(\.interval),
                        projectIDFilter: projectID
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
            Log.app.error("Gantt project Screen Time query failed: \(message, privacy: .public)")
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
