import Foundation
import Observation

/// Per-period summary of the user's AI coding activity. All numbers are derived
/// from already-parsed sessions; `reload(...)` populates this off-main so view
/// bodies only read precomputed values.
struct DashboardStats: Sendable, Hashable {
    var sessions: Int
    var messages: Int
    var totalTokens: Int
    var totalCost: Double
    var activeDays: Int
    /// Consecutive days, counting back from today (or yesterday if today is
    /// empty), where there was any session activity.
    var currentStreak: Int
    /// Longest run of consecutive active days across all of history.
    var longestStreak: Int
    /// Hour-of-day (0…23) with the most token spend; `nil` when there is no
    /// activity at all.
    var peakHour: Int?
    /// Provider-qualified model id with the most tokens spent across `period`.
    var favoriteModel: DashboardModelKey?

    static let empty = DashboardStats(
        sessions: 0,
        messages: 0,
        totalTokens: 0,
        totalCost: 0,
        activeDays: 0,
        currentStreak: 0,
        longestStreak: 0,
        peakHour: nil,
        favoriteModel: nil
    )
}

/// Dashboard-specific model identity. The Dashboard aggregates all providers,
/// so the provider must travel with the model id to avoid merging unrelated
/// models that happen to share the same raw string.
struct DashboardModelKey: Sendable, Hashable, Identifiable {
    let provider: ProviderKind
    let model: String

    var id: String { "\(provider.rawValue)|\(model)" }

    init(provider: ProviderKind, model: String) {
        self.provider = provider
        self.model = model
    }

    init?(id: String) {
        let parts = id.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let provider = ProviderKind(rawValue: String(parts[0])) else {
            return nil
        }
        self.provider = provider
        self.model = String(parts[1])
    }
}

struct DashboardModelUsage: Sendable, Hashable, Identifiable {
    let key: DashboardModelKey
    let messageCount: Int
    let usage: TokenUsage
    let costEstimate: CostEstimate

    var id: String { key.id }
    var estimatedCost: Double { costEstimate.standardAPI }

    func estimatedCost(for mode: CostEstimationMode) -> Double {
        costEstimate.value(for: mode)
    }
}

/// Drives the Dashboard page: 8 stat cards keyed by `period`, a fixed
/// 3-month all-provider heatmap, and an all-provider model breakdown for the
/// Models tab. GitHub state lives in `GitHubViewModel` and is rendered from the
/// Git page.
///
/// `reload(sessions:)` runs the full aggregation off-main in a single
/// `Task.detached`, so view bodies stay cheap and SwiftUI's update cycle
/// receives one batched assignment.
@MainActor
@Observable
final class DashboardViewModel {
    enum Section: String, CaseIterable, Identifiable, Sendable {
        case overview, models
        var id: String { rawValue }
    }

    var section: Section = .overview
    var period: StatsPeriod = .last30Days {
        didSet { if period != oldValue { reloadToken &+= 1 } }
    }

    private(set) var stats: DashboardStats = .empty
    private(set) var heatmapCells: [HeatmapCell] = []
    /// Count of cells in the 3-month heatmap with positive activity. Mirrors
    /// `heatmapCells.filter { $0.value > 0 }.count` but computed off-main
    /// during `reload(sessions:)` so the view body doesn't walk the array.
    private(set) var heatmapActiveDays: Int = 0
    private(set) var modelBreakdown: [DashboardModelUsage] = []
    /// Per-model daily series for the Models tab's stacked bar chart. Daily
    /// granularity for every dashboard period (we never select `.today` here).
    private(set) var modelTrend: TrendSeries = TrendSeries(granularity: .day, models: [], buckets: [])
    private(set) var isLoading = false
    private(set) var reloadToken: UInt64 = 0

    private let calendar = Calendar.current
    @ObservationIgnored private var currentReloadGeneration: UInt64 = 0

    /// Number of trailing days the heatmap spans (rolling, ends today).
    static let heatmapDayCount = 90

    init(pricing _: ModelPricing = .fallback) {}

    func bumpReload() { reloadToken &+= 1 }

    /// Rolling interval the heatmap covers: `[today − (heatmapDayCount − 1), today + 1d)`.
    func heatmapInterval(now: Date = .now) -> DateInterval {
        let cal = calendar
        let endExclusive = cal.dateInterval(of: .day, for: now)?.end ?? now
        let start = cal.date(byAdding: .day, value: -(Self.heatmapDayCount - 1), to: cal.startOfDay(for: now)) ?? now
        return DateInterval(start: start, end: endExclusive)
    }

    /// Recompute the overview off-main. Captures a local `Calendar` so the
    /// detached block stays Sendable under Swift 6 strict concurrency.
    func reload(sessions: [Session]) async {
        currentReloadGeneration &+= 1
        let generation = currentReloadGeneration
        if !isLoading { isLoading = true }
        defer {
            if currentReloadGeneration == generation, isLoading {
                isLoading = false
            }
        }

        let cal = calendar
        let period = period
        let now = Date.now
        let heatmapInterval = heatmapInterval(now: now)

        let task = Task.detached(priority: .userInitiated) { () throws -> ReloadResult in
            try Self.reloadResult(
                sessions: sessions,
                period: period,
                heatmapInterval: heatmapInterval,
                calendar: cal,
                now: now
            )
        }

        do {
            let result = try await withTaskCancellationHandler(operation: {
                try await task.value
            }, onCancel: {
                task.cancel()
            })
            guard currentReloadGeneration == generation else { return }
            apply(result)
        } catch is CancellationError {
            task.cancel()
        } catch {
            Log.store.error("Dashboard reload failed: \(error.localizedDescription)")
        }
    }

    private struct ReloadResult: Sendable {
        let stats: DashboardStats
        let heatmapCells: [HeatmapCell]
        let heatmapActiveDays: Int
        let modelBreakdown: [DashboardModelUsage]
        let modelTrend: TrendSeries
    }

    // MARK: - Pure aggregations (nonisolated, called from Task.detached)

    private func apply(_ result: ReloadResult) {
        if stats != result.stats { stats = result.stats }
        if heatmapCells != result.heatmapCells { heatmapCells = result.heatmapCells }
        if heatmapActiveDays != result.heatmapActiveDays { heatmapActiveDays = result.heatmapActiveDays }
        if modelBreakdown != result.modelBreakdown { modelBreakdown = result.modelBreakdown }
        if modelTrend != result.modelTrend { modelTrend = result.modelTrend }
    }

    nonisolated private static func reloadResult(
        sessions: [Session],
        period: StatsPeriod,
        heatmapInterval: DateInterval,
        calendar cal: Calendar,
        now: Date
    ) throws -> ReloadResult {
        var accumulator = ReloadAccumulator()
        accumulator.reserveCapacity(sessionCount: sessions.count)

        for (index, session) in sessions.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            try accumulator.add(
                session,
                period: period,
                heatmapInterval: heatmapInterval,
                calendar: cal,
                now: now
            )
        }

        try Task.checkCancellation()
        return try accumulator.result(period: period, calendar: cal, now: now)
    }

    private struct ReloadAccumulator {
        var sessionsInPeriod = 0
        var messageCount = 0
        var modelTotals: [DashboardModelKey: ModelTotal] = [:]
        var periodTimeline: [String: [Date: TokenUsage]] = [:]
        var peakTokensByHour: [Int: Int] = [:]
        var activeDaysInPeriod: Set<Date> = []
        var activeDaysAllTime: Set<Date> = []
        var heatmapTokensByDay: [Date: Int] = [:]

        mutating func reserveCapacity(sessionCount: Int) {
            activeDaysAllTime.reserveCapacity(min(sessionCount, 512))
            activeDaysInPeriod.reserveCapacity(min(sessionCount, 128))
        }

        mutating func add(
            _ session: Session,
            period: StatsPeriod,
            heatmapInterval: DateInterval,
            calendar cal: Calendar,
            now: Date
        ) throws {
            let activityDate = session.stats?.lastActivity ?? session.lastModified
            let activityDay = cal.startOfDay(for: activityDate)
            activeDaysAllTime.insert(activityDay)

            let isInPeriod = period.contains(activityDate, now: now, calendar: cal)
            if isInPeriod {
                sessionsInPeriod += 1
                activeDaysInPeriod.insert(activityDay)
            }

            guard let stats = session.stats else { return }
            if isInPeriod {
                messageCount += stats.messageCount
                for model in stats.models {
                    let key = DashboardModelKey(provider: session.provider, model: model.model)
                    var total = modelTotals[key] ?? ModelTotal()
                    total.messageCount += model.messageCount
                    total.usage += model.usage
                    total.costEstimate += model.costEstimate
                    modelTotals[key] = total
                }
            }

            try addTimeline(
                stats: stats,
                session: session,
                isInPeriod: isInPeriod,
                period: period,
                heatmapInterval: heatmapInterval,
                calendar: cal,
                now: now
            )
        }

        private mutating func addTimeline(
            stats: SessionStats,
            session: Session,
            isInPeriod: Bool,
            period: StatsPeriod,
            heatmapInterval: DateInterval,
            calendar cal: Calendar,
            now: Date
        ) throws {
            if stats.timeline.isEmpty {
                let activityDate = stats.lastActivity ?? session.lastModified
                let bucketStart = cal.dateInterval(of: .hour, for: activityDate)?.start ?? activityDate
                for model in stats.models where model.usage.total > 0 {
                    try Task.checkCancellation()
                    let key = DashboardModelKey(provider: session.provider, model: model.model).id
                    addTimelineBucket(
                        modelID: key,
                        start: bucketStart,
                        usage: model.usage,
                        isInPeriod: isInPeriod,
                        period: period,
                        heatmapInterval: heatmapInterval,
                        calendar: cal,
                        now: now
                    )
                }
            } else {
                for bucket in stats.timeline {
                    try Task.checkCancellation()
                    let key = DashboardModelKey(provider: session.provider, model: bucket.model).id
                    addTimelineBucket(
                        modelID: key,
                        start: bucket.start,
                        usage: bucket.usage,
                        isInPeriod: isInPeriod,
                        period: period,
                        heatmapInterval: heatmapInterval,
                        calendar: cal,
                        now: now
                    )
                }
            }
        }

        private mutating func addTimelineBucket(
            modelID: String,
            start: Date,
            usage: TokenUsage,
            isInPeriod: Bool,
            period: StatsPeriod,
            heatmapInterval: DateInterval,
            calendar cal: Calendar,
            now: Date
        ) {
            let day = cal.startOfDay(for: start)
            if heatmapInterval.contains(day) {
                heatmapTokensByDay[day, default: 0] += usage.total
            }

            guard isInPeriod, period.contains(start, now: now, calendar: cal) else { return }
            periodTimeline[modelID, default: [:]][start, default: .zero] += usage
            let hour = cal.component(.hour, from: start)
            peakTokensByHour[hour, default: 0] += usage.total
        }

        func result(period: StatsPeriod, calendar cal: Calendar, now: Date) throws -> ReloadResult {
            let models = modelBreakdown()
            let timeline = periodTimelineBuckets()
            let totalUsage = models.reduce(.zero) { $0 + $1.usage }
            let totalCost = models.reduce(0) { $0 + $1.estimatedCost }
            let (current, longest) = streaks(calendar: cal, now: now)
            let heatmap = heatmapCells()
            let trend = try DashboardViewModel.trendSeries(
                timeline: timeline,
                models: models,
                period: period,
                now: now,
                calendar: cal
            )

            return ReloadResult(
                stats: DashboardStats(
                    sessions: sessionsInPeriod,
                    messages: messageCount,
                    totalTokens: totalUsage.total,
                    totalCost: totalCost,
                    activeDays: activeDaysInPeriod.count,
                    currentStreak: current,
                    longestStreak: longest,
                    peakHour: peakHour(),
                    favoriteModel: models.first { SessionUsageAggregator.isFavoriteModelName($0.key.model) }?.key
                ),
                heatmapCells: heatmap,
                heatmapActiveDays: heatmap.reduce(0) { $0 + ($1.value > 0 ? 1 : 0) },
                modelBreakdown: models,
                modelTrend: trend
            )
        }

        private func modelBreakdown() -> [DashboardModelUsage] {
            modelTotals
                .map { key, total in
                    DashboardModelUsage(
                        key: key,
                        messageCount: total.messageCount,
                        usage: total.usage,
                        costEstimate: total.costEstimate
                    )
                }
                .sorted { lhs, rhs in
                    lhs.usage.total != rhs.usage.total
                        ? lhs.usage.total > rhs.usage.total
                        : lhs.id < rhs.id
                }
        }

        private func periodTimelineBuckets() -> [ModelBucket] {
            periodTimeline
                .flatMap { model, byStart in
                    byStart.map { ModelBucket(model: model, start: $0.key, usage: $0.value) }
                }
                .sorted { $0.start < $1.start }
        }

        private func heatmapCells() -> [HeatmapCell] {
            heatmapTokensByDay
                .map { HeatmapCell(date: $0.key, value: $0.value) }
                .sorted { $0.date < $1.date }
        }

        /// `(currentStreak, longestStreak)` walking the set of days with any
        /// session activity across all history (streaks are a long-term
        /// motivation signal and don't depend on the selected range).
        private func streaks(calendar cal: Calendar, now: Date) -> (Int, Int) {
            let days = activeDaysAllTime
            guard !days.isEmpty else { return (0, 0) }

            let sorted = days.sorted()
            var longest = 1
            var run = 1
            for i in 1..<sorted.count {
                if let prevPlusOne = cal.date(byAdding: .day, value: 1, to: sorted[i - 1]), prevPlusOne == sorted[i] {
                    run += 1
                    longest = max(longest, run)
                } else {
                    run = 1
                }
            }

            let today = cal.startOfDay(for: now)
            var current = 0
            var cursor = today
            if !days.contains(cursor) {
                cursor = cal.date(byAdding: .day, value: -1, to: today) ?? today
                if !days.contains(cursor) { return (0, longest) }
            }
            while days.contains(cursor) {
                current += 1
                guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            }
            return (current, longest)
        }

        private func peakHour() -> Int? {
            peakTokensByHour.max(by: { $0.value < $1.value })?.key
        }
    }

    private struct ModelTotal {
        var messageCount = 0
        var usage: TokenUsage = .zero
        var costEstimate: CostEstimate = .zero
    }

    nonisolated private static func trendSeries(
        timeline: [ModelBucket],
        models: [DashboardModelUsage],
        period: StatsPeriod,
        now: Date,
        calendar cal: Calendar
    ) throws -> TrendSeries {
        let modelIDs = models.map(\.id)
        let granularity: TrendGranularity = period == .today ? .hour : .day
        guard !modelIDs.isEmpty else {
            return TrendSeries(granularity: granularity, models: [], buckets: [])
        }

        let unit: Calendar.Component = granularity == .hour ? .hour : .day
        let bucketed = timeline.rebucketed(by: unit, calendar: cal)
        var byKey: [String: TokenUsage] = [:]
        for bucket in bucketed {
            try Task.checkCancellation()
            byKey["\(bucket.model)|\(bucket.start.timeIntervalSinceReferenceDate)"] = bucket.usage
        }

        let starts: [Date]
        switch granularity {
        case .hour:
            let dayStart = cal.startOfDay(for: now)
            starts = (0..<24).compactMap { cal.date(byAdding: .hour, value: $0, to: dayStart) }
        case .day:
            guard let lo = bucketed.map(\.start).min(), let hi = bucketed.map(\.start).max() else {
                return TrendSeries(granularity: granularity, models: modelIDs, buckets: [])
            }
            var ds: [Date] = []
            var cur = lo
            while cur <= hi {
                ds.append(cur)
                guard let next = cal.date(byAdding: unit, value: 1, to: cur) else { break }
                cur = next
            }
            starts = ds
        }

        var filled: [ModelBucket] = []
        filled.reserveCapacity(modelIDs.count * starts.count)
        for model in modelIDs {
            for start in starts {
                try Task.checkCancellation()
                let usage = byKey["\(model)|\(start.timeIntervalSinceReferenceDate)"] ?? .zero
                filled.append(ModelBucket(model: model, start: start, usage: usage))
            }
        }
        return TrendSeries(granularity: granularity, models: modelIDs, buckets: filled)
    }
}
