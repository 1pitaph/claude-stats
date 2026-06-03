import Foundation
import Observation

@MainActor
@Observable
final class GanttViewModel {
    var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    var range: GanttRange = .day
    var activityMode: GanttActivityMode = .aiActive

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
    private let calendar = Calendar.current

    init(
        focusIntervalLoader: @escaping @Sendable (DateInterval, Set<String>) async -> Result<[AppFocusInterval], ScreenTimeService.Failure> = { range, bundleIDs in
            ScreenTimeService().focusIntervals(in: range, bundleIDs: bundleIDs)
        },
        gitMetricsLoader: any GanttGitMetricsLoading = GanttGitMetricsLoader()
    ) {
        self.focusIntervalLoader = focusIntervalLoader
        self.gitMetricsLoader = gitMetricsLoader
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
            return RelativeDayLabel.label(
                for: period.domain.start,
                todayKey: "gantt.daily_date.today",
                yesterdayKey: "gantt.daily_date.yesterday"
            )
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

    func focusDate(_ date: Date) {
        selectedDate = min(max(date, .distantPast), Date.now)
    }

    func focusDateIfPeriodChanges(_ date: Date) {
        let clamped = min(max(date, .distantPast), Date.now)
        let current = period
        let next = range.period(containing: clamped, calendar: calendar)
        guard current.domain != next.domain else { return }
        selectedDate = clamped
    }

    func jumpToToday() {
        selectedDate = calendar.startOfDay(for: .now)
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
        sessions: [Session],
        codingSurfaceBundleIDs: Set<String>,
        cliHostBundleIDs: Set<String>,
        usageLimitReports: [UsageLimitReport] = [],
        usageLimitForecasts: [UsageLimitForecast] = []
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

        let requestedPeriod = period
        let requestedBaselinePeriod = baselinePeriod(before: requestedPeriod)
        let requestedMode = activityMode
        let focusIntervalLoader = self.focusIntervalLoader
        let focusBundleIDs = codingSurfaceBundleIDs.union(cliHostBundleIDs)

        let outcome = await Self.coreOutcome(
            sessions: sessions,
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
            snapshot = .empty(period: requestedPeriod, activityMode: requestedMode, sourceSessionCount: sessions.count)
        case .failure(.queryFailed(let message)):
            Log.app.error("Gantt Screen Time query failed: \(message, privacy: .public)")
            permissionState = .ok
            focusDataState = .queryFailed
            snapshot = .empty(period: requestedPeriod, activityMode: requestedMode, sourceSessionCount: sessions.count)
        case .snapshot(let payload):
            permissionState = .ok
            focusDataState = payload.focusDataState
            snapshot = snapshotWithUsageAnnotations(payload.snapshot)
            startEnrichment(
                reloadID: reloadID,
                sessions: sessions,
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

    private func baselinePeriod(before period: GanttPeriod) -> GanttPeriod {
        let baselineDate = range.stepping(period.domain.start, by: -1, calendar: calendar)
        return range.period(containing: baselineDate, now: period.domain.start, calendar: calendar)
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
