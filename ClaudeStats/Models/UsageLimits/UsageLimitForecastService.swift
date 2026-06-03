import Foundation

struct UsageLimitForecastService: Sendable {
    private enum TokenSourceQuality: Sendable {
        case message
        case timeline
    }

    private struct TokenBucket: Sendable {
        let start: Date
        let duration: TimeInterval
        let tokens: Double
    }

    private struct TokenSeries: Sendable {
        let buckets: [TokenBucket]
        let bucketDuration: TimeInterval
        let historyWindow: TimeInterval
        let quality: TokenSourceQuality
    }

    private struct ForecastProfile: Sendable {
        let horizon: UsageLimitForecastHorizon
        let historyWindow: TimeInterval
        let bucketDuration: TimeInterval
        let minimumSnapshots: Int
        let minimumUsableRatios: Int
        let minimumUsageSpan: TimeInterval
        let minimumUsageGrowth: Double
        let smoothingAlpha: Double
        let bootstrapBlockLength: Int
        let minimumHitRatio: Double
        let requiresResetMatch: Bool
        let collectingSnapshotMessage: String
    }

    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        }

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return state
        }

        mutating func nextInt(upperBound: Int) -> Int {
            guard upperBound > 1 else { return 0 }
            return Int(next() % UInt64(upperBound))
        }
    }

    private let fiveMinutes: TimeInterval = 5 * 60
    private let thirtyMinutes: TimeInterval = 30 * 60
    private let hour: TimeInterval = 3_600
    private let bootstrapSimulations = 240

    func forecasts(
        sessions: [Session],
        reports: [UsageLimitReport],
        history: [UsageLimitHistoryEntry],
        now: Date = .now
    ) -> [UsageLimitForecast] {
        reports.flatMap { report -> [UsageLimitForecast] in
            guard let snapshot = report.snapshot else { return [] }
            return snapshot.windows.compactMap { window -> UsageLimitForecast? in
                guard let horizon = window.forecastHorizon(for: snapshot.provider) else { return nil }
                let profile = profile(for: horizon)
                let tokenSeries = tokenSeries(
                    for: snapshot.provider,
                    sessions: sessions,
                    now: now,
                    profile: profile
                )
                switch horizon {
                case .fiveHour:
                    return fiveHourForecast(
                        reportStatus: report.status,
                        snapshot: snapshot,
                        window: window,
                        history: history,
                        tokenSeries: tokenSeries,
                        profile: profile,
                        now: now
                    )
                case .sevenDay:
                    return sevenDayForecast(
                        reportStatus: report.status,
                        snapshot: snapshot,
                        window: window,
                        history: history,
                        tokenSeries: tokenSeries,
                        profile: profile,
                        now: now
                    )
                }
            }
        }
        .sorted { $0.id < $1.id }
    }

    private func profile(for horizon: UsageLimitForecastHorizon) -> ForecastProfile {
        switch horizon {
        case .fiveHour:
            ForecastProfile(
                horizon: .fiveHour,
                historyWindow: 5 * hour,
                bucketDuration: fiveMinutes,
                minimumSnapshots: 3,
                minimumUsableRatios: 2,
                minimumUsageSpan: thirtyMinutes,
                minimumUsageGrowth: 2,
                smoothingAlpha: 0.13,
                bootstrapBlockLength: 3,
                minimumHitRatio: 0.25,
                requiresResetMatch: false,
                collectingSnapshotMessage: "Collecting 5-hour usage snapshots."
            )
        case .sevenDay:
            ForecastProfile(
                horizon: .sevenDay,
                historyWindow: 7 * 86_400,
                bucketDuration: hour,
                minimumSnapshots: 4,
                minimumUsableRatios: 2,
                minimumUsageSpan: 0,
                minimumUsageGrowth: 0,
                smoothingAlpha: 0.35,
                bootstrapBlockLength: 6,
                minimumHitRatio: 0,
                requiresResetMatch: true,
                collectingSnapshotMessage: "Collecting 7-day usage snapshots."
            )
        }
    }

    private func sevenDayForecast(
        reportStatus: UsageLimitStatus,
        snapshot: UsageLimitSnapshot,
        window: UsageLimitWindow,
        history: [UsageLimitHistoryEntry],
        tokenSeries: TokenSeries,
        profile: ForecastProfile,
        now: Date
    ) -> UsageLimitForecast {
        let base = ForecastBase(snapshot: snapshot, window: window, horizon: profile.horizon)
        guard let prepared = prepareForecastInputs(
            reportStatus: reportStatus,
            snapshot: snapshot,
            window: window,
            history: history,
            profile: profile,
            now: now,
            base: base
        ) else {
            return base.make(status: .unavailable, confidence: .low, diagnostics: ["Usage snapshot is unavailable."])
        }

        switch prepared {
        case .terminal(let forecast):
            return forecast
        case .entries(let entries, let resetAt):
            guard entries.count >= profile.minimumSnapshots else {
                return base.make(
                    status: .collecting,
                    confidence: .low,
                    diagnostics: [profile.collectingSnapshotMessage]
                )
            }
            return forecastFromEntries(
                base: base,
                entries: entries,
                resetAt: resetAt,
                tokenSeries: tokenSeries,
                profile: profile,
                now: now,
                diagnostics: ["Based on \(entries.count) snapshots over the current 7-day cycle."]
            )
        }
    }

    private func fiveHourForecast(
        reportStatus: UsageLimitStatus,
        snapshot: UsageLimitSnapshot,
        window: UsageLimitWindow,
        history: [UsageLimitHistoryEntry],
        tokenSeries: TokenSeries,
        profile: ForecastProfile,
        now: Date
    ) -> UsageLimitForecast {
        let base = ForecastBase(snapshot: snapshot, window: window, horizon: profile.horizon)
        guard let prepared = prepareForecastInputs(
            reportStatus: reportStatus,
            snapshot: snapshot,
            window: window,
            history: history,
            profile: profile,
            now: now,
            base: base
        ) else {
            return base.make(status: .unavailable, confidence: .low, diagnostics: ["Usage snapshot is unavailable."])
        }

        switch prepared {
        case .terminal(let forecast):
            return forecast
        case .entries(let entries, let resetAt):
            guard entries.count >= profile.minimumSnapshots else {
                return base.make(
                    status: .collecting,
                    confidence: .low,
                    diagnostics: [profile.collectingSnapshotMessage]
                )
            }
            if let first = entries.first, let last = entries.last {
                guard last.capturedAt.timeIntervalSince(first.capturedAt) >= profile.minimumUsageSpan else {
                    return base.make(
                        status: .collecting,
                        confidence: .low,
                        diagnostics: ["Collecting a longer 5-hour usage trend."]
                    )
                }
                guard last.usedPercent - first.usedPercent >= profile.minimumUsageGrowth else {
                    return base.make(
                        status: .collecting,
                        confidence: .low,
                        diagnostics: ["Collecting enough 5-hour usage movement."]
                    )
                }
            }
            return forecastFromEntries(
                base: base,
                entries: entries,
                resetAt: resetAt,
                tokenSeries: tokenSeries,
                profile: profile,
                now: now,
                diagnostics: ["Based on \(entries.count) snapshots over the current 5-hour cycle."]
            )
        }
    }

    private enum PreparedInputs {
        case terminal(UsageLimitForecast)
        case entries([UsageLimitHistoryEntry], resetAt: Date)
    }

    private func prepareForecastInputs(
        reportStatus: UsageLimitStatus,
        snapshot: UsageLimitSnapshot,
        window: UsageLimitWindow,
        history: [UsageLimitHistoryEntry],
        profile: ForecastProfile,
        now: Date,
        base: ForecastBase
    ) -> PreparedInputs? {
        let currentUsedPercent = window.clampedUsedPercent

        guard reportStatus == .fresh else {
            return .terminal(base.make(
                status: .unavailable,
                confidence: .low,
                diagnostics: ["Usage snapshot is not fresh."]
            ))
        }
        guard let resetAt = window.resetAt else {
            return .terminal(base.make(
                status: .unavailable,
                confidence: .low,
                diagnostics: ["Usage reset time is unavailable."]
            ))
        }
        guard currentUsedPercent < 100 else {
            return .terminal(base.make(
                status: .limitReached,
                confidence: .high,
                diagnostics: ["Usage is already at or above the limit."]
            ))
        }

        let currentEntry = UsageLimitHistoryEntry(
            provider: snapshot.provider,
            window: window,
            capturedAt: snapshot.capturedAt,
            sourceLabel: snapshot.sourceLabel,
            sourcePath: snapshot.sourcePath,
            planType: snapshot.planType,
            limitID: snapshot.limitID
        )
        let entries = currentEntries(
            provider: snapshot.provider,
            windowID: window.id,
            resetAt: resetAt,
            history: history + [currentEntry],
            profile: profile,
            now: now
        )
        return .entries(entries, resetAt: resetAt)
    }

    private func forecastFromEntries(
        base: ForecastBase,
        entries: [UsageLimitHistoryEntry],
        resetAt: Date,
        tokenSeries: TokenSeries,
        profile: ForecastProfile,
        now: Date,
        diagnostics: [String]
    ) -> UsageLimitForecast {
        let ratios = usableTokenToPercentRatios(entries: entries, tokenBuckets: tokenSeries.buckets)
        guard ratios.count >= profile.minimumUsableRatios else {
            return base.make(
                status: .collecting,
                confidence: .low,
                diagnostics: ["Collecting enough token movement for prediction."]
            )
        }

        let beta = Self.median(ratios)
        guard beta > 0, beta.isFinite else {
            return base.make(
                status: .collecting,
                confidence: .low,
                diagnostics: ["Token-to-usage relationship is not measurable yet."]
            )
        }

        let neededTokens = (100 - base.currentUsedPercent) / beta
        let rateSeries = bucketedRateSeries(tokenSeries: tokenSeries, now: now)
        guard rateSeries.reduce(0, +) > 0 else {
            return base.make(
                status: .collecting,
                confidence: .low,
                diagnostics: ["Collecting recent token usage rates."]
            )
        }

        let recentIdle = profile.horizon == .fiveHour
            && tokenSum(tokenSeries.buckets, from: now.addingTimeInterval(-thirtyMinutes), to: now) <= 0
        let hitTimes = bootstrapHitTimes(
            rateSeries: rateSeries,
            neededTokens: neededTokens,
            now: now,
            resetAt: resetAt,
            profile: profile,
            recentIdle: recentIdle,
            seed: UInt64(abs(base.id.hashValue))
        )
        let minimumHits = Int(ceil(Double(bootstrapSimulations) * profile.minimumHitRatio))
        guard !hitTimes.isEmpty, hitTimes.count >= max(1, minimumHits) else {
            return base.make(
                status: .willNotReachBeforeReset,
                confidence: confidence(
                    ratios: ratios,
                    sampleCount: entries.count,
                    quality: tokenSeries.quality,
                    horizon: profile.horizon
                ),
                diagnostics: ["Projected usage does not reach the limit before reset."]
            )
        }

        let sortedHits = hitTimes.sorted()
        let lower = Self.percentile(sortedHits, 0.20)
        let median = Self.percentile(sortedHits, 0.50)
        let upper = Self.percentile(sortedHits, 0.80)
        let interval = DateInterval(start: min(lower, upper), end: max(lower, upper))
        return base.make(
            status: .forecast,
            reachInterval: interval,
            medianReachAt: median,
            confidence: confidence(
                ratios: ratios,
                sampleCount: entries.count,
                quality: tokenSeries.quality,
                horizon: profile.horizon
            ),
            diagnostics: diagnostics
        )
    }

    private func currentEntries(
        provider: ProviderKind,
        windowID: String,
        resetAt: Date,
        history: [UsageLimitHistoryEntry],
        profile: ForecastProfile,
        now: Date
    ) -> [UsageLimitHistoryEntry] {
        let cutoff = now.addingTimeInterval(-profile.historyWindow)
        let resetTolerance: TimeInterval = 1
        let sorted = history
            .filter {
                guard $0.matches(provider, windowID: windowID),
                      $0.capturedAt >= cutoff,
                      $0.capturedAt <= now.addingTimeInterval(60) else {
                    return false
                }
                guard let entryResetAt = $0.resetAt, entryResetAt > $0.capturedAt else {
                    return false
                }
                return !profile.requiresResetMatch || abs(entryResetAt.timeIntervalSince(resetAt)) <= resetTolerance
            }
            .sorted { $0.capturedAt < $1.capturedAt }
        let deduped = deduplicatedByCapturedSecond(sorted)

        guard !deduped.isEmpty else { return [] }
        let dropTolerance = profile.horizon == .fiveHour ? 0.5 : 0.001
        var startIndex = 0
        for index in deduped.indices.dropFirst() {
            if deduped[index].usedPercent + dropTolerance < deduped[deduped.index(before: index)].usedPercent {
                startIndex = index
            }
        }
        return Array(deduped[startIndex...])
    }

    private func deduplicatedByCapturedSecond(_ entries: [UsageLimitHistoryEntry]) -> [UsageLimitHistoryEntry] {
        var result: [UsageLimitHistoryEntry] = []
        for entry in entries {
            let capturedSecond = Int(entry.capturedAt.timeIntervalSince1970)
            if let last = result.last,
               Int(last.capturedAt.timeIntervalSince1970) == capturedSecond {
                result[result.count - 1] = entry
            } else {
                result.append(entry)
            }
        }
        return result
    }

    private func usableTokenToPercentRatios(
        entries: [UsageLimitHistoryEntry],
        tokenBuckets: [TokenBucket]
    ) -> [Double] {
        guard entries.count >= 2 else { return [] }
        var ratios: [Double] = []
        for index in entries.indices.dropFirst() {
            let previous = entries[entries.index(before: index)]
            let current = entries[index]
            let deltaPercent = current.usedPercent - previous.usedPercent
            guard deltaPercent > 0 else { continue }
            let deltaTokens = tokenSum(tokenBuckets, from: previous.capturedAt, to: current.capturedAt)
            guard deltaTokens > 0 else { continue }
            ratios.append(deltaPercent / deltaTokens)
        }
        return ratios.filter { $0.isFinite && $0 > 0 }
    }

    private func tokenSeries(
        for provider: ProviderKind,
        sessions: [Session],
        now: Date,
        profile: ForecastProfile
    ) -> TokenSeries {
        let cutoff = now.addingTimeInterval(-profile.historyWindow)
        var messageBuckets: [Date: Double] = [:]
        var seenHashes = Set<String>()

        for session in sessions where session.provider == provider {
            guard let stats = session.stats, !stats.billableMessages.isEmpty else { continue }
            for message in stats.billableMessages {
                guard let timestamp = message.timestamp,
                      timestamp >= cutoff,
                      timestamp <= now,
                      message.usage.total > 0 else {
                    continue
                }
                if let hash = message.hash {
                    guard seenHashes.insert(hash).inserted else { continue }
                }
                let bucketStart = bucketStart(for: timestamp, duration: profile.bucketDuration)
                messageBuckets[bucketStart, default: 0] += Double(message.usage.total)
            }
        }

        if !messageBuckets.isEmpty {
            return TokenSeries(
                buckets: messageBuckets.map {
                    TokenBucket(start: $0.key, duration: profile.bucketDuration, tokens: $0.value)
                }
                .sorted { $0.start < $1.start },
                bucketDuration: profile.bucketDuration,
                historyWindow: profile.historyWindow,
                quality: .message
            )
        }

        var timelineBuckets: [Date: Double] = [:]
        for session in sessions where session.provider == provider {
            guard let stats = session.stats else { continue }
            for bucket in stats.timeline {
                let interval = DateInterval(start: bucket.start, duration: hour)
                guard interval.end >= cutoff, interval.start <= now, bucket.usage.total > 0 else { continue }
                timelineBuckets[bucket.start, default: 0] += Double(bucket.usage.total)
            }
        }

        return TokenSeries(
            buckets: timelineBuckets.map {
                TokenBucket(start: $0.key, duration: hour, tokens: $0.value)
            }
            .sorted { $0.start < $1.start },
            bucketDuration: profile.bucketDuration,
            historyWindow: profile.historyWindow,
            quality: .timeline
        )
    }

    private func tokenSum(_ buckets: [TokenBucket], from start: Date, to end: Date) -> Double {
        guard end > start else { return 0 }
        let interval = DateInterval(start: start, end: end)
        return buckets.reduce(0) { partial, bucket in
            let bucketInterval = DateInterval(start: bucket.start, duration: bucket.duration)
            guard let overlap = ActivityAnalyzer.clip(bucketInterval, to: interval) else { return partial }
            return partial + bucket.tokens * (overlap.duration / bucket.duration)
        }
    }

    private func bucketedRateSeries(tokenSeries: TokenSeries, now: Date) -> [Double] {
        let bucketCount = max(1, Int(ceil(tokenSeries.historyWindow / tokenSeries.bucketDuration)))
        let end = bucketStart(for: now, duration: tokenSeries.bucketDuration)
        let start = end.addingTimeInterval(-Double(bucketCount - 1) * tokenSeries.bucketDuration)
        return (0..<bucketCount).map { offset in
            let bucketStart = start.addingTimeInterval(Double(offset) * tokenSeries.bucketDuration)
            return tokenSum(
                tokenSeries.buckets,
                from: bucketStart,
                to: bucketStart.addingTimeInterval(tokenSeries.bucketDuration)
            )
        }
    }

    private func bootstrapHitTimes(
        rateSeries: [Double],
        neededTokens: Double,
        now: Date,
        resetAt: Date,
        profile: ForecastProfile,
        recentIdle: Bool,
        seed: UInt64
    ) -> [Date] {
        guard neededTokens > 0, resetAt > now else { return [] }
        let horizonBuckets = max(1, Int(ceil(resetAt.timeIntervalSince(now) / profile.bucketDuration)))
        let maxBlockStart = max(1, rateSeries.count - profile.bootstrapBlockLength + 1)
        let initialRate = ewma(rateSeries, alpha: profile.smoothingAlpha)
        var generator = SeededGenerator(seed: seed)
        var hitTimes: [Date] = []
        hitTimes.reserveCapacity(bootstrapSimulations)

        for _ in 0..<bootstrapSimulations {
            var accumulated = 0.0
            var forecastRate = initialRate
            var elapsedBuckets = 0
            var hit: Date?

            while elapsedBuckets < horizonBuckets, hit == nil {
                let blockStart = generator.nextInt(upperBound: maxBlockStart)
                for offset in 0..<profile.bootstrapBlockLength where elapsedBuckets < horizonBuckets {
                    var sampledRate = rateSeries[min(blockStart + offset, rateSeries.count - 1)]
                    if recentIdle {
                        sampledRate *= 0.25
                    }
                    forecastRate = profile.smoothingAlpha * sampledRate + (1 - profile.smoothingAlpha) * forecastRate
                    if recentIdle {
                        forecastRate *= 0.72
                    }
                    let previous = accumulated
                    accumulated += max(0, forecastRate)
                    elapsedBuckets += 1

                    if accumulated >= neededTokens {
                        let ratio = accumulated > previous
                            ? min(1, max(0, (neededTokens - previous) / (accumulated - previous)))
                            : 1
                        hit = now.addingTimeInterval((Double(elapsedBuckets - 1) + ratio) * profile.bucketDuration)
                        break
                    }
                }
            }

            if let hit, hit <= resetAt {
                hitTimes.append(hit)
            }
        }
        return hitTimes
    }

    private func ewma(_ values: [Double], alpha: Double) -> Double {
        guard var current = values.first else { return 0 }
        for value in values.dropFirst() {
            current = alpha * value + (1 - alpha) * current
        }
        return current
    }

    private func confidence(
        ratios: [Double],
        sampleCount: Int,
        quality: TokenSourceQuality,
        horizon: UsageLimitForecastHorizon
    ) -> UsageLimitForecastConfidence {
        if horizon == .fiveHour, quality == .timeline {
            return .low
        }
        let median = Self.median(ratios)
        guard median > 0 else { return .low }
        let q1 = Self.percentileValue(ratios.sorted(), 0.25)
        let q3 = Self.percentileValue(ratios.sorted(), 0.75)
        let spread = (q3 - q1) / median
        if sampleCount >= 8, spread < 0.6 {
            return .high
        }
        if sampleCount >= 5, spread < 1.2 {
            return .medium
        }
        return .low
    }

    private func bucketStart(for date: Date, duration: TimeInterval) -> Date {
        let bucket = floor(date.timeIntervalSinceReferenceDate / duration) * duration
        return Date(timeIntervalSinceReferenceDate: bucket)
    }

    private static func median(_ values: [Double]) -> Double {
        percentileValue(values.sorted(), 0.50)
    }

    private static func percentile(_ dates: [Date], _ percentile: Double) -> Date {
        guard !dates.isEmpty else { return .distantFuture }
        let timestamps = dates.map(\.timeIntervalSinceReferenceDate)
        return Date(timeIntervalSinceReferenceDate: percentileValue(timestamps, percentile))
    }

    private static func percentileValue(_ sortedValues: [Double], _ percentile: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        guard sortedValues.count > 1 else { return sortedValues[0] }
        let clamped = min(1, max(0, percentile))
        let position = clamped * Double(sortedValues.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        guard lower != upper else { return sortedValues[lower] }
        let fraction = position - Double(lower)
        return sortedValues[lower] * (1 - fraction) + sortedValues[upper] * fraction
    }

    private struct ForecastBase {
        let id: String
        let provider: ProviderKind
        let windowID: String
        let label: String
        let horizon: UsageLimitForecastHorizon
        let capturedAt: Date
        let currentUsedPercent: Double
        let resetAt: Date?

        init(snapshot: UsageLimitSnapshot, window: UsageLimitWindow, horizon: UsageLimitForecastHorizon) {
            self.id = "\(snapshot.provider.rawValue)|\(window.id)"
            self.provider = snapshot.provider
            self.windowID = window.id
            self.label = window.label
            self.horizon = horizon
            self.capturedAt = snapshot.capturedAt
            self.currentUsedPercent = window.clampedUsedPercent
            self.resetAt = window.resetAt
        }

        func make(
            status: UsageLimitForecastStatus,
            reachInterval: DateInterval? = nil,
            medianReachAt: Date? = nil,
            confidence: UsageLimitForecastConfidence,
            diagnostics: [String]
        ) -> UsageLimitForecast {
            UsageLimitForecast(
                provider: provider,
                windowID: windowID,
                label: label,
                horizon: horizon,
                capturedAt: capturedAt,
                currentUsedPercent: currentUsedPercent,
                resetAt: resetAt,
                reachInterval: reachInterval,
                medianReachAt: medianReachAt,
                confidence: confidence,
                status: status,
                diagnostics: diagnostics
            )
        }
    }
}
