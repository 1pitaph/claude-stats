import Foundation
import Observation

@MainActor
@Observable
final class GanttProjectDetailViewModel {
    var activityMode: GanttActivityMode

    private(set) var period: GanttPeriod
    private(set) var permissionState: ActivityPermissionState = .ok
    private(set) var focusDataState: GanttFocusDataState = .available
    private(set) var snapshot: GanttTimelineSnapshot
    private(set) var isLoading = false
    private(set) var isEnriching = false
    private(set) var reloadToken: UInt64 = 0

    @ObservationIgnored
    private var activeReloadID: UInt64 = 0
    @ObservationIgnored
    private var enrichmentTask: Task<Void, Never>?
    @ObservationIgnored
    private var currentUsageLimitReports: [UsageLimitReport] = []
    @ObservationIgnored
    private var currentUsageLimitForecasts: [UsageLimitForecast] = []
    @ObservationIgnored
    private let focusIntervalLoader: @Sendable (DateInterval, Set<String>) async -> Result<[AppFocusInterval], ScreenTimeService.Failure>
    @ObservationIgnored
    private let gitMetricsLoader: any GanttGitMetricsLoading

    init(
        initialMode: GanttActivityMode,
        focusIntervalLoader: @escaping @Sendable (DateInterval, Set<String>) async -> Result<[AppFocusInterval], ScreenTimeService.Failure> = { range, bundleIDs in
            ScreenTimeService().focusIntervals(in: range, bundleIDs: bundleIDs)
        },
        gitMetricsLoader: any GanttGitMetricsLoading = GanttGitMetricsLoader()
    ) {
        self.activityMode = initialMode
        self.focusIntervalLoader = focusIntervalLoader
        self.gitMetricsLoader = gitMetricsLoader
        let period = GanttPeriod.recentSevenDays()
        self.period = period
        self.snapshot = .empty(period: period, activityMode: initialMode)
    }

    func bumpReload() {
        reloadToken &+= 1
    }

    private struct SnapshotPayload: Sendable {
        let snapshot: GanttTimelineSnapshot
        let focusDataState: GanttFocusDataState
        let currentFocusAppIntervals: [AppFocusInterval]
    }

    private enum Outcome: Sendable {
        case failure(ScreenTimeService.Failure)
        case snapshot(SnapshotPayload)
    }

    func reload(
        projectID: String,
        sessions: [Session],
        usageLimitReports: [UsageLimitReport] = [],
        usageLimitForecasts: [UsageLimitForecast] = [],
        codingSurfaceBundleIDs: Set<String>,
        cliHostBundleIDs: Set<String>
    ) async {
        activeReloadID &+= 1
        let reloadID = activeReloadID
        enrichmentTask?.cancel()
        isEnriching = false
        currentUsageLimitReports = usageLimitReports
        currentUsageLimitForecasts = usageLimitForecasts
        isLoading = true
        defer {
            if reloadID == activeReloadID {
                isLoading = false
            }
        }

        let requestedPeriod = GanttPeriod.recentSevenDays()
        period = requestedPeriod
        let requestedBaselinePeriod = baselinePeriod(before: requestedPeriod)
        let requestedMode = activityMode
        let focusIntervalLoader = self.focusIntervalLoader
        let focusBundleIDs = codingSurfaceBundleIDs.union(cliHostBundleIDs)
        let projectSessions = Self.sessions(sessions, matching: projectID)

        let outcome = await Self.coreOutcome(
            sessions: projectSessions,
            period: requestedPeriod,
            activityMode: requestedMode,
            focusBundleIDs: focusBundleIDs,
            focusIntervalLoader: focusIntervalLoader,
            usageLimitReports: usageLimitReports
        )

        guard reloadID == activeReloadID, !Task.isCancelled else { return }

        switch outcome {
        case .failure(.noFullDiskAccess):
            permissionState = .needsFullDiskAccess
            focusDataState = .available
            snapshot = .empty(period: requestedPeriod, activityMode: requestedMode, sourceSessionCount: projectSessions.count)
        case .failure(.queryFailed(let message)):
            Log.app.error("Gantt project Screen Time query failed: \(message, privacy: .public)")
            permissionState = .ok
            focusDataState = .queryFailed
            snapshot = .empty(period: requestedPeriod, activityMode: requestedMode, sourceSessionCount: projectSessions.count)
        case .snapshot(let payload):
            permissionState = .ok
            focusDataState = payload.focusDataState
            snapshot = snapshotWithUsageAnnotations(payload.snapshot)
            startEnrichment(
                reloadID: reloadID,
                sessions: projectSessions,
                period: requestedPeriod,
                baselinePeriod: requestedBaselinePeriod,
                activityMode: requestedMode,
                focusBundleIDs: focusBundleIDs,
                currentFocusAppIntervals: payload.currentFocusAppIntervals
            )
        }
    }

    func refreshUsageLimitReports(_ reports: [UsageLimitReport]) {
        currentUsageLimitReports = reports
        snapshot = snapshotWithUsageAnnotations(snapshot)
    }

    func refreshUsageLimitForecasts(_ forecasts: [UsageLimitForecast]) {
        currentUsageLimitForecasts = forecasts
        snapshot = snapshot.withUsageLimitForecasts(forecasts)
    }

    private func startEnrichment(
        reloadID: UInt64,
        sessions: [Session],
        period: GanttPeriod,
        baselinePeriod: GanttPeriod,
        activityMode: GanttActivityMode,
        focusBundleIDs: Set<String>,
        currentFocusAppIntervals: [AppFocusInterval]
    ) {
        isEnriching = true
        let focusIntervalLoader = self.focusIntervalLoader
        let gitMetricsLoader = self.gitMetricsLoader
        enrichmentTask = Task {
            let enriched = await Self.enrichedSnapshot(
                sessions: sessions,
                period: period,
                baselinePeriod: baselinePeriod,
                activityMode: activityMode,
                focusBundleIDs: focusBundleIDs,
                currentFocusAppIntervals: currentFocusAppIntervals,
                focusIntervalLoader: focusIntervalLoader,
                gitMetricsLoader: gitMetricsLoader
            )

            guard reloadID == activeReloadID, !Task.isCancelled else { return }
            isEnriching = false
            snapshot = snapshotWithUsageAnnotations(enriched)
        }
    }

    private func snapshotWithUsageAnnotations(_ snapshot: GanttTimelineSnapshot) -> GanttTimelineSnapshot {
        snapshot.withLoad(
            GanttTimelineBuilder.loadSnapshot(
                replacingUsageLimitReports: currentUsageLimitReports,
                in: snapshot.load,
                domain: snapshot.domain
            )
        )
        .withUsageLimitForecasts(currentUsageLimitForecasts)
    }

    nonisolated private static func coreOutcome(
        sessions: [Session],
        period: GanttPeriod,
        activityMode: GanttActivityMode,
        focusBundleIDs: Set<String>,
        focusIntervalLoader: @escaping @Sendable (DateInterval, Set<String>) async -> Result<[AppFocusInterval], ScreenTimeService.Failure>,
        usageLimitReports: [UsageLimitReport]
    ) async -> Outcome {
        switch activityMode {
        case .aiActive:
            let current = await buildSnapshot(
                sessions: sessions,
                period: period,
                activityMode: activityMode,
                focusAppIntervals: [],
                usageLimitReports: usageLimitReports,
                externalMetrics: .zero
            )
            return .snapshot(SnapshotPayload(snapshot: current, focusDataState: .available, currentFocusAppIntervals: []))
        case .assistedFocus:
            let currentFocusResult = await focusIntervalLoader(period.dataRange, focusBundleIDs)
            switch currentFocusResult {
            case .failure(let failure):
                return .failure(failure)
            case .success(let currentFocus):
                let focusDataState: GanttFocusDataState = currentFocus.isEmpty ? .noMatchingFocusData : .available
                let current = await buildSnapshot(
                    sessions: sessions,
                    period: period,
                    activityMode: activityMode,
                    focusAppIntervals: currentFocus,
                    usageLimitReports: usageLimitReports,
                    externalMetrics: .zero
                )
                return .snapshot(SnapshotPayload(
                    snapshot: current,
                    focusDataState: focusDataState,
                    currentFocusAppIntervals: currentFocus
                ))
            }
        }
    }

    nonisolated private static func enrichedSnapshot(
        sessions: [Session],
        period: GanttPeriod,
        baselinePeriod: GanttPeriod,
        activityMode: GanttActivityMode,
        focusBundleIDs: Set<String>,
        currentFocusAppIntervals: [AppFocusInterval],
        focusIntervalLoader: @escaping @Sendable (DateInterval, Set<String>) async -> Result<[AppFocusInterval], ScreenTimeService.Failure>,
        gitMetricsLoader: any GanttGitMetricsLoading
    ) async -> GanttTimelineSnapshot {
        let currentExternal = await gitMetricsLoader.externalMetrics(sessions: sessions, during: period.dataRange, projectIDFilter: nil)
        let baselineExternal = await gitMetricsLoader.externalMetrics(sessions: sessions, during: baselinePeriod.dataRange, projectIDFilter: nil)
        guard !Task.isCancelled else {
            return .empty(period: period, activityMode: activityMode, sourceSessionCount: sessions.count)
        }

        let baselineFocus: [AppFocusInterval]
        switch activityMode {
        case .aiActive:
            baselineFocus = []
        case .assistedFocus:
            switch await focusIntervalLoader(baselinePeriod.dataRange, focusBundleIDs) {
            case .success(let focus):
                baselineFocus = focus
            case .failure:
                baselineFocus = []
            }
        }

        async let baseline = buildSnapshot(
            sessions: sessions,
            period: baselinePeriod,
            activityMode: activityMode,
            focusAppIntervals: baselineFocus,
            usageLimitReports: [],
            externalMetrics: baselineExternal
        )
        async let current = buildSnapshot(
            sessions: sessions,
            period: period,
            activityMode: activityMode,
            focusAppIntervals: currentFocusAppIntervals,
            usageLimitReports: [],
            externalMetrics: currentExternal
        )
        let built = await (current: current, baseline: baseline)
        return built.current.withBaselineComparison(
            GanttTimelineBuilder.baselineComparison(current: built.current, baseline: built.baseline)
        )
    }

    nonisolated private static func buildSnapshot(
        sessions: [Session],
        period: GanttPeriod,
        activityMode: GanttActivityMode,
        focusAppIntervals: [AppFocusInterval],
        usageLimitReports: [UsageLimitReport],
        externalMetrics: GanttExternalMetrics
    ) async -> GanttTimelineSnapshot {
        let task = Task.detached(priority: .userInitiated) {
            GanttTimelineBuilder.build(
                sessions: sessions,
                period: period,
                activityMode: activityMode,
                focusAppIntervals: focusAppIntervals,
                usageLimitReports: usageLimitReports,
                externalMetrics: externalMetrics
            )
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    nonisolated private static func sessions(_ sessions: [Session], matching projectID: String) -> [Session] {
        sessions.filter { GanttTimelineBuilder.projectIdentity(for: $0).id == projectID }
    }

    private func baselinePeriod(before period: GanttPeriod, calendar: Calendar = .current) -> GanttPeriod {
        let duration = period.domain.duration
        let start = period.domain.start.addingTimeInterval(-duration)
        let domain = DateInterval(start: start, duration: duration)
        return GanttPeriod(range: period.range, domain: domain, dataRange: domain)
    }

    func refreshPermissionState() {
        guard activityMode == .assistedFocus else {
            permissionState = .ok
            focusDataState = .available
            return
        }
        permissionState = ScreenTimeService.canRead() ? .ok : .needsFullDiskAccess
    }
}
