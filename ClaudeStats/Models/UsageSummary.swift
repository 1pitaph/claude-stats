import Foundation

/// Aggregate usage across many sessions, scoped to a ``StatsPeriod``.
struct UsageSummary: Sendable, Hashable {
    let period: StatsPeriod
    let sessionCount: Int
    let models: [ModelUsage]
    let messageCount: Int
    /// Hourly per-model buckets for the sessions counted in this period.
    let timeline: [ModelBucket]

    var totalUsage: TokenUsage { models.reduce(.zero) { $0 + $1.usage } }
    var totalTokens: Int { totalUsage.total }
    var totalCost: Double { totalCost(for: .standardAPI) }

    func totalTokens(includingCacheRead: Bool) -> Int {
        totalUsage.total(includingCacheRead: includingCacheRead)
    }

    func totalCost(for mode: CostEstimationMode) -> Double {
        let effectiveMode: CostEstimationMode = mode == .codexCredits && !totalCostUsesCredits(for: mode) ? .standardAPI : mode
        return models.reduce(0) { $0 + $1.estimatedCost(for: effectiveMode) }
    }

    func totalCostUsesCredits(for mode: CostEstimationMode) -> Bool {
        mode == .codexCredits && !models.isEmpty && models.allSatisfy { $0.estimatedCostUsesCredits(for: mode) }
    }

    static func empty(period: StatsPeriod) -> UsageSummary {
        UsageSummary(period: period, sessionCount: 0, models: [], messageCount: 0, timeline: [])
    }

    /// Build a summary from already-parsed sessions.
    ///
    /// Token totals and timeline buckets are attributed by the billable/timeline
    /// timestamp when available, scoped to the requested interval. Sessions that
    /// carry ``SessionStats/billableMessages`` (Claude transcripts) are deduped
    /// across files by message hash — see ``BillableMessage``.
    static func make(
        period: StatsPeriod,
        sessions: [Session],
        pricing: ModelPricing,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> UsageSummary {
        let interval = period.interval(now: now, calendar: calendar)
        let aggregate = if let interval {
            SessionUsageAggregator.aggregate(sessions: sessions, in: interval, calendar: calendar)
        } else {
            SessionUsageAggregator.aggregate(sessions: sessions, calendar: calendar)
        }
        let inPeriod = sessions.filter { sessionIntersects($0, interval: interval) }
        let messageCount = inPeriod.reduce(0) { $0 + ($1.stats?.messageCount ?? 0) }
        return UsageSummary(
            period: period,
            sessionCount: inPeriod.count,
            models: aggregate.models,
            messageCount: messageCount,
            timeline: aggregate.timeline
        )
    }

    /// Build a summary for one explicit local calendar day while preserving
    /// ``StatsPeriod/today`` so the trend chart remains hourly.
    static func makeDay(
        _ day: Date,
        sessions: [Session],
        pricing: ModelPricing,
        calendar: Calendar = .current
    ) -> UsageSummary {
        let lo = calendar.startOfDay(for: day)
        guard let hiExclusive = calendar.date(byAdding: .day, value: 1, to: lo) else {
            return .empty(period: .today)
        }
        let interval = DateInterval(start: lo, end: hiExclusive)
        let inDay = sessions.filter { sessionIntersects($0, interval: interval) }
        let aggregate = SessionUsageAggregator.aggregate(sessions: sessions, in: interval, calendar: calendar)
        let messageCount = inDay.reduce(0) { $0 + ($1.stats?.messageCount ?? 0) }
        return UsageSummary(
            period: .today,
            sessionCount: inDay.count,
            models: aggregate.models,
            messageCount: messageCount,
            timeline: aggregate.timeline
        )
    }

    /// Build a summary scoped to an explicit `[start, end]` range of calendar
    /// days (inclusive on both ends). The stored `period` is set to
    /// ``StatsPeriod/allTime`` purely so ``trendSeries(now:calendar:)`` picks
    /// daily granularity — the human-facing range label always comes from the
    /// originating ``PeriodSelection``, never from `period`.
    static func makeCustom(start: Date, end: Date, sessions: [Session], pricing: ModelPricing, calendar: Calendar = .current) -> UsageSummary {
        let lo = calendar.startOfDay(for: min(start, end))
        guard let hiExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(start, end))) else {
            return .empty(period: .allTime)
        }
        let interval = DateInterval(start: lo, end: hiExclusive)
        let inRange = sessions.filter { sessionIntersects($0, interval: interval) }
        let aggregate = SessionUsageAggregator.aggregate(sessions: sessions, in: interval, calendar: calendar)
        let messageCount = inRange.reduce(0) { $0 + ($1.stats?.messageCount ?? 0) }
        return UsageSummary(
            period: .allTime,
            sessionCount: inRange.count,
            models: aggregate.models,
            messageCount: messageCount,
            timeline: aggregate.timeline
        )
    }

    /// Per-model series for the trend chart: hourly across *today* for
    /// ``StatsPeriod/today``, daily across the span of ``timeline`` otherwise.
    /// Every `(model × bucket-in-span)` is present (zero-filled) so each model
    /// has a continuous series to smooth.
    func trendSeries(now: Date = .now, calendar: Calendar = .current) -> TrendSeries {
        let models = timeline.modelsByTotalDescending
        guard !models.isEmpty else { return TrendSeries(granularity: period == .today ? .hour : .day, models: [], buckets: []) }

        let granularity: TrendGranularity = period == .today ? .hour : .day
        let unit: Calendar.Component = granularity == .hour ? .hour : .day

        let bucketed = timeline.rebucketed(by: unit, calendar: calendar)
        var byKey: [String: TokenUsage] = [:]   // "model|epoch" -> usage
        for b in bucketed { byKey["\(b.model)|\(b.start.timeIntervalSinceReferenceDate)"] = b.usage }

        // Domain of bucket starts.
        let starts: [Date]
        switch granularity {
        case .hour:
            let dayStart = calendar.startOfDay(for: now)
            starts = (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: dayStart) }
        case .day:
            guard let lo = bucketed.map(\.start).min(), let hi = bucketed.map(\.start).max() else {
                return TrendSeries(granularity: granularity, models: models, buckets: [])
            }
            var ds: [Date] = []
            var cur = lo
            while cur <= hi {
                ds.append(cur)
                guard let next = calendar.date(byAdding: unit, value: 1, to: cur) else { break }
                cur = next
            }
            starts = ds
        }

        var filled: [ModelBucket] = []
        filled.reserveCapacity(models.count * starts.count)
        for model in models {
            for start in starts {
                let usage = byKey["\(model)|\(start.timeIntervalSinceReferenceDate)"] ?? .zero
                filled.append(ModelBucket(model: model, start: start, usage: usage))
            }
        }
        return TrendSeries(granularity: granularity, models: models, buckets: filled)
    }
}

private extension UsageSummary {
    static func sessionIntersects(_ session: Session, interval: DateInterval?) -> Bool {
        guard let interval else { return true }
        guard let stats = session.stats else {
            return contains(session.lastModified, in: interval)
        }

        let fallback = stats.lastActivity ?? session.lastModified
        if !stats.billableMessages.isEmpty {
            return stats.billableMessages.contains { contains($0.timestamp ?? fallback, in: interval) }
        }

        if !stats.timeline.isEmpty {
            return stats.timeline.contains { contains($0.start, in: interval) }
        }

        return contains(fallback, in: interval)
    }

    static func contains(_ date: Date, in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }
}

private extension StatsPeriod {
    func interval(now: Date, calendar: Calendar) -> DateInterval? {
        guard let lower = lowerBound(now: now, calendar: calendar) else { return nil }
        return DateInterval(start: lower, end: .distantFuture)
    }
}

/// Time grain used by the Usage trend chart.
enum TrendGranularity: Sendable, Hashable { case hour, day }

/// The trend chart's data: a continuous, zero-filled per-model series.
struct TrendSeries: Sendable, Hashable {
    let granularity: TrendGranularity
    /// Models present, ordered by total tokens descending.
    let models: [String]
    /// Zero-filled buckets covering every `(model × bucket-in-span)`.
    let buckets: [ModelBucket]

    var isEmpty: Bool { buckets.allSatisfy { $0.tokens == 0 } }

    var dataRevisionID: String {
        var totalsByModel: [String: TokenUsage] = [:]
        var firstStart: Date?
        var lastStart: Date?
        for bucket in buckets {
            totalsByModel[bucket.model, default: .zero] += bucket.usage
            firstStart = min(firstStart ?? bucket.start, bucket.start)
            lastStart = max(lastStart ?? bucket.start, bucket.start)
        }

        let modelTotals = models.map { model in
            "\(model):\(totalsByModel[model, default: .zero].dataRevisionID)"
        }
        return [
            granularity.revisionID,
            models.joined(separator: ","),
            String(buckets.count),
            firstStart.map { String(Int($0.timeIntervalSinceReferenceDate.rounded())) } ?? "nil",
            lastStart.map { String(Int($0.timeIntervalSinceReferenceDate.rounded())) } ?? "nil",
            modelTotals.joined(separator: "|"),
        ]
        .joined(separator: "#")
    }

    func buckets(for model: String) -> [ModelBucket] {
        buckets.filter { $0.model == model }.sorted { $0.start < $1.start }
    }
}

private extension TrendGranularity {
    var revisionID: String {
        switch self {
        case .hour: "hour"
        case .day: "day"
        }
    }
}
