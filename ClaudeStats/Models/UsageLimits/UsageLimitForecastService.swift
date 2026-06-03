import Foundation

struct UsageLimitForecastService: Sendable {
    private struct TokenBucket: Sendable {
        let start: Date
        let tokens: Double
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

    private let minimumSnapshots = 4
    private let minimumUsableRatios = 2
    private let forecastHistoryWindow: TimeInterval = 7 * 86_400
    private let hour: TimeInterval = 3_600
    private let smoothingAlpha = 0.35
    private let bootstrapSimulations = 240
    private let bootstrapBlockLength = 6

    func forecasts(
        sessions: [Session],
        reports: [UsageLimitReport],
        history: [UsageLimitHistoryEntry],
        now: Date = .now
    ) -> [UsageLimitForecast] {
        let tokenBucketsByProvider = Dictionary(
            uniqueKeysWithValues: ProviderKind.allCases.map { provider in
                (provider, tokenBuckets(for: provider, sessions: sessions, now: now))
            }
        )

        return reports.flatMap { report -> [UsageLimitForecast] in
            guard let snapshot = report.snapshot else { return [] }
            return snapshot.windows.compactMap { window -> UsageLimitForecast? in
                guard window.isCoreSevenDayLimit(for: snapshot.provider) else { return nil }
                return forecast(
                    reportStatus: report.status,
                    snapshot: snapshot,
                    window: window,
                    history: history,
                    tokenBuckets: tokenBucketsByProvider[snapshot.provider] ?? [],
                    now: now
                )
            }
        }
        .sorted { $0.id < $1.id }
    }

    private func forecast(
        reportStatus: UsageLimitStatus,
        snapshot: UsageLimitSnapshot,
        window: UsageLimitWindow,
        history: [UsageLimitHistoryEntry],
        tokenBuckets: [TokenBucket],
        now: Date
    ) -> UsageLimitForecast {
        let currentUsedPercent = window.clampedUsedPercent
        let base = ForecastBase(snapshot: snapshot, window: window)

        guard reportStatus == .fresh else {
            return base.make(
                status: .unavailable,
                confidence: .low,
                diagnostics: ["Usage snapshot is not fresh."]
            )
        }
        guard let resetAt = window.resetAt else {
            return base.make(
                status: .unavailable,
                confidence: .low,
                diagnostics: ["Usage reset time is unavailable."]
            )
        }
        guard currentUsedPercent < 100 else {
            return base.make(
                status: .limitReached,
                confidence: .high,
                diagnostics: ["Usage is already at or above the limit."]
            )
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
        let entries = currentCycleEntries(
            provider: snapshot.provider,
            windowID: window.id,
            resetAt: resetAt,
            history: history + [currentEntry],
            now: now
        )

        guard entries.count >= minimumSnapshots else {
            return base.make(
                status: .collecting,
                confidence: .low,
                diagnostics: ["Collecting 7-day usage snapshots."]
            )
        }

        let ratios = usableTokenToPercentRatios(entries: entries, tokenBuckets: tokenBuckets)
        guard ratios.count >= minimumUsableRatios else {
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

        let neededTokens = (100 - currentUsedPercent) / beta
        let rateSeries = hourlyRateSeries(tokenBuckets: tokenBuckets, now: now)
        guard rateSeries.reduce(0, +) > 0 else {
            return base.make(
                status: .collecting,
                confidence: .low,
                diagnostics: ["Collecting recent token usage rates."]
            )
        }

        let hitTimes = bootstrapHitTimes(
            rateSeries: rateSeries,
            neededTokens: neededTokens,
            now: now,
            resetAt: resetAt,
            seed: UInt64(abs(base.id.hashValue))
        )

        guard !hitTimes.isEmpty else {
            return base.make(
                status: .willNotReachBeforeReset,
                confidence: confidence(ratios: ratios, sampleCount: entries.count),
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
            confidence: confidence(ratios: ratios, sampleCount: entries.count),
            diagnostics: ["Based on \(entries.count) snapshots over the current 7-day cycle."]
        )
    }

    private func currentCycleEntries(
        provider: ProviderKind,
        windowID: String,
        resetAt: Date,
        history: [UsageLimitHistoryEntry],
        now: Date
    ) -> [UsageLimitHistoryEntry] {
        let cutoff = now.addingTimeInterval(-forecastHistoryWindow)
        let resetTolerance: TimeInterval = 1
        let sorted = history
            .filter {
                $0.matches(provider, windowID: windowID)
                    && $0.capturedAt >= cutoff
                    && $0.capturedAt <= now.addingTimeInterval(60)
                    && $0.resetAt.map { abs($0.timeIntervalSince(resetAt)) <= resetTolerance } == true
            }
            .sorted { $0.capturedAt < $1.capturedAt }
        let deduped = deduplicatedByCapturedSecond(sorted)

        guard !deduped.isEmpty else { return [] }
        var startIndex = 0
        for index in deduped.indices.dropFirst() {
            if deduped[index].usedPercent + 0.001 < deduped[deduped.index(before: index)].usedPercent {
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

    private func tokenBuckets(for provider: ProviderKind, sessions: [Session], now: Date) -> [TokenBucket] {
        let cutoff = now.addingTimeInterval(-forecastHistoryWindow)
        var byHour: [Date: Double] = [:]
        var seenHashes = Set<String>()
        let calendar = Calendar.current

        for session in sessions where session.provider == provider {
            guard let stats = session.stats else { continue }

            if !stats.billableMessages.isEmpty {
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
                    let hourStart = calendar.dateInterval(of: .hour, for: timestamp)?.start ?? timestamp
                    byHour[hourStart, default: 0] += Double(message.usage.total)
                }
            } else {
                for bucket in stats.timeline where bucket.start >= cutoff && bucket.start <= now {
                    byHour[bucket.start, default: 0] += Double(bucket.usage.total)
                }
            }
        }

        return byHour.map { TokenBucket(start: $0.key, tokens: $0.value) }
            .sorted { $0.start < $1.start }
    }

    private func tokenSum(_ buckets: [TokenBucket], from start: Date, to end: Date) -> Double {
        guard end > start else { return 0 }
        return buckets.reduce(0) { partial, bucket in
            let bucketInterval = DateInterval(start: bucket.start, duration: hour)
            let interval = DateInterval(start: start, end: end)
            guard let overlap = ActivityAnalyzer.clip(bucketInterval, to: interval) else { return partial }
            return partial + bucket.tokens * (overlap.duration / hour)
        }
    }

    private func hourlyRateSeries(tokenBuckets: [TokenBucket], now: Date) -> [Double] {
        let calendar = Calendar.current
        let endHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let start = endHour.addingTimeInterval(-forecastHistoryWindow + hour)
        let byHour = Dictionary(uniqueKeysWithValues: tokenBuckets.map { ($0.start, $0.tokens) })
        return (0..<Int(forecastHistoryWindow / hour)).map { offset in
            let date = start.addingTimeInterval(Double(offset) * hour)
            return byHour[date] ?? 0
        }
    }

    private func bootstrapHitTimes(
        rateSeries: [Double],
        neededTokens: Double,
        now: Date,
        resetAt: Date,
        seed: UInt64
    ) -> [Date] {
        guard neededTokens > 0, resetAt > now else { return [] }
        let horizonHours = max(1, Int(ceil(resetAt.timeIntervalSince(now) / hour)))
        let maxBlockStart = max(1, rateSeries.count - bootstrapBlockLength + 1)
        let initialRate = ewma(rateSeries)
        var generator = SeededGenerator(seed: seed)
        var hitTimes: [Date] = []
        hitTimes.reserveCapacity(bootstrapSimulations)

        for _ in 0..<bootstrapSimulations {
            var accumulated = 0.0
            var forecastRate = initialRate
            var elapsedHours = 0
            var hit: Date?

            while elapsedHours < horizonHours, hit == nil {
                let blockStart = generator.nextInt(upperBound: maxBlockStart)
                for offset in 0..<bootstrapBlockLength where elapsedHours < horizonHours {
                    let sampledRate = rateSeries[min(blockStart + offset, rateSeries.count - 1)]
                    forecastRate = smoothingAlpha * sampledRate + (1 - smoothingAlpha) * forecastRate
                    let previous = accumulated
                    accumulated += max(0, forecastRate)
                    elapsedHours += 1

                    if accumulated >= neededTokens {
                        let ratio = accumulated > previous
                            ? min(1, max(0, (neededTokens - previous) / (accumulated - previous)))
                            : 1
                        hit = now.addingTimeInterval((Double(elapsedHours - 1) + ratio) * hour)
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

    private func ewma(_ values: [Double]) -> Double {
        guard var current = values.first else { return 0 }
        for value in values.dropFirst() {
            current = smoothingAlpha * value + (1 - smoothingAlpha) * current
        }
        return current
    }

    private func confidence(ratios: [Double], sampleCount: Int) -> UsageLimitForecastConfidence {
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
        let capturedAt: Date
        let currentUsedPercent: Double
        let resetAt: Date?

        init(snapshot: UsageLimitSnapshot, window: UsageLimitWindow) {
            self.id = "\(snapshot.provider.rawValue)|\(window.id)"
            self.provider = snapshot.provider
            self.windowID = window.id
            self.label = window.label
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
