import Foundation

struct SessionUsageAggregate: Sendable, Hashable {
    let models: [ModelUsage]
    let timeline: [ModelBucket]

    var totalUsage: TokenUsage { models.reduce(.zero) { $0 + $1.usage } }
    var totalCost: CostEstimate { models.reduce(.zero) { $0 + $1.costEstimate } }
}

struct ProviderModelUsage: Sendable, Hashable, Identifiable {
    let provider: ProviderKind
    let model: String
    let messageCount: Int
    let usage: TokenUsage
    let costEstimate: CostEstimate

    var id: String { "\(provider.rawValue)|\(model)" }
    var estimatedCost: Double { costEstimate.standardAPI }
}

struct ProviderModelBucket: Sendable, Hashable, Identifiable {
    let provider: ProviderKind
    let model: String
    let start: Date
    let usage: TokenUsage

    var id: String { "\(provider.rawValue)|\(model)|\(start.timeIntervalSinceReferenceDate)" }
    var modelID: String { "\(provider.rawValue)|\(model)" }
    var tokens: Int { usage.total }
}

struct ProviderSessionUsageAggregate: Sendable, Hashable {
    let models: [ProviderModelUsage]
    let timeline: [ProviderModelBucket]

    var totalUsage: TokenUsage { models.reduce(.zero) { $0 + $1.usage } }
    var totalCost: CostEstimate { models.reduce(.zero) { $0 + $1.costEstimate } }
}

enum SessionUsageAggregator {
    static func aggregate(sessions: [Session], calendar: Calendar = .current) -> SessionUsageAggregate {
        let core = aggregateCore(sessions: sessions, interval: nil, calendar: calendar, includeProvider: false)
        return SessionUsageAggregate(
            models: core.models.map {
                ModelUsage(
                    model: $0.key.model,
                    messageCount: $0.value.count,
                    usage: $0.value.usage,
                    costEstimate: $0.value.cost
                )
            },
            timeline: core.timeline.map {
                ModelBucket(model: $0.key.model, start: $0.start, usage: $0.usage)
            }
        )
    }

    static func aggregate(sessions: [Session], in interval: DateInterval, calendar: Calendar = .current) -> SessionUsageAggregate {
        let core = aggregateCore(sessions: sessions, interval: interval, calendar: calendar, includeProvider: false)
        return SessionUsageAggregate(
            models: core.models.map {
                ModelUsage(
                    model: $0.key.model,
                    messageCount: $0.value.count,
                    usage: $0.value.usage,
                    costEstimate: $0.value.cost
                )
            },
            timeline: core.timeline.map {
                ModelBucket(model: $0.key.model, start: $0.start, usage: $0.usage)
            }
        )
    }

    static func aggregateByProvider(sessions: [Session], calendar: Calendar = .current) -> ProviderSessionUsageAggregate {
        let core = aggregateCore(sessions: sessions, interval: nil, calendar: calendar, includeProvider: true)
        return ProviderSessionUsageAggregate(
            models: core.models.map {
                ProviderModelUsage(
                    provider: $0.key.provider ?? .claude,
                    model: $0.key.model,
                    messageCount: $0.value.count,
                    usage: $0.value.usage,
                    costEstimate: $0.value.cost
                )
            },
            timeline: core.timeline.map {
                ProviderModelBucket(
                    provider: $0.key.provider ?? .claude,
                    model: $0.key.model,
                    start: $0.start,
                    usage: $0.usage
                )
            }
        )
    }

    static func aggregateByProvider(
        sessions: [Session],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> ProviderSessionUsageAggregate {
        let core = aggregateCore(sessions: sessions, interval: interval, calendar: calendar, includeProvider: true)
        return ProviderSessionUsageAggregate(
            models: core.models.map {
                ProviderModelUsage(
                    provider: $0.key.provider ?? .claude,
                    model: $0.key.model,
                    messageCount: $0.value.count,
                    usage: $0.value.usage,
                    costEstimate: $0.value.cost
                )
            },
            timeline: core.timeline.map {
                ProviderModelBucket(
                    provider: $0.key.provider ?? .claude,
                    model: $0.key.model,
                    start: $0.start,
                    usage: $0.usage
                )
            }
        )
    }

    static func favoriteModelTotals(sessions: [Session]) -> [String: Int64] {
        var totals: [String: Int64] = [:]
        var seen: Set<String> = []

        for session in sessions {
            guard let stats = session.stats else { continue }
            if !stats.billableMessages.isEmpty {
                for bill in stats.billableMessages {
                    if let hash = bill.hash {
                        if seen.contains(hash) { continue }
                        seen.insert(hash)
                    }
                    let name = bill.model.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard isFavoriteModelName(name) else { continue }
                    totals[name, default: 0] += Int64(bill.usage.total)
                }
            } else if !stats.timeline.isEmpty {
                for bucket in stats.timeline {
                    let name = bucket.model.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard isFavoriteModelName(name) else { continue }
                    totals[name, default: 0] += Int64(bucket.usage.total)
                }
            } else {
                for model in stats.models {
                    let name = model.model.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard isFavoriteModelName(name) else { continue }
                    totals[name, default: 0] += Int64(model.usage.total)
                }
            }
        }

        return totals
    }

    private static let providerPlaceholderModelNames: Set<String> = {
        Set(ProviderKind.allCases.flatMap { provider in
            [
                normalizedFavoriteModelKey(provider.rawValue),
                normalizedFavoriteModelKey(provider.displayName),
                normalizedFavoriteModelKey(provider.shortName),
            ]
        })
    }()

    static func isFavoriteModelName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !providerPlaceholderModelNames.contains(normalizedFavoriteModelKey(trimmed))
    }

    private static func normalizedFavoriteModelKey(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func aggregateCore(
        sessions: [Session],
        interval: DateInterval?,
        calendar: Calendar,
        includeProvider: Bool
    ) -> AggregateCore {
        var perModel: [AggregateKey: (count: Int, usage: TokenUsage, cost: CostEstimate)] = [:]
        var perModelHourly: [AggregateKey: [Date: TokenUsage]] = [:]
        var seen: Set<String> = []

        func key(provider: ProviderKind, model: String) -> AggregateKey {
            AggregateKey(provider: includeProvider ? provider : nil, model: model)
        }

        func add(provider: ProviderKind, model: String, count: Int, usage: TokenUsage, cost: CostEstimate) {
            let key = key(provider: provider, model: model)
            var acc = perModel[key] ?? (0, .zero, .zero)
            acc.count += count
            acc.usage += usage
            acc.cost += cost
            perModel[key] = acc
        }

        func addTimeline(provider: ProviderKind, model: String, date: Date, usage: TokenUsage) {
            guard usage.total > 0 else { return }
            let hour = calendar.dateInterval(of: .hour, for: date)?.start
                ?? calendar.startOfDay(for: date)
            perModelHourly[key(provider: provider, model: model), default: [:]][hour, default: .zero] += usage
        }

        for session in sessions {
            guard let stats = session.stats else { continue }

            if !stats.billableMessages.isEmpty {
                let fallbackDate = stats.lastActivity ?? session.lastModified
                for bill in stats.billableMessages {
                    let attributionDate = bill.timestamp ?? fallbackDate
                    guard contains(attributionDate, in: interval) else { continue }
                    if let hash = bill.hash {
                        if seen.contains(hash) { continue }
                        seen.insert(hash)
                    }
                    add(provider: session.provider, model: bill.model, count: 1, usage: bill.usage, cost: bill.cost)
                    if let timestamp = bill.timestamp {
                        addTimeline(provider: session.provider, model: bill.model, date: timestamp, usage: bill.usage)
                    }
                }
                continue
            }

            if let interval, !stats.timeline.isEmpty {
                var modelsByName: [String: ModelUsage] = [:]
                for model in stats.models {
                    modelsByName[model.model] = model
                }
                let buckets = stats.timeline.filter { contains($0.start, in: interval) }
                for bucket in buckets {
                    let modelUsage = modelsByName[bucket.model]
                    add(
                        provider: session.provider,
                        model: bucket.model,
                        count: messageCount(for: bucket, modelUsage: modelUsage),
                        usage: bucket.usage,
                        cost: costEstimate(for: bucket, modelUsage: modelUsage)
                    )
                    addTimeline(provider: session.provider, model: bucket.model, date: bucket.start, usage: bucket.usage)
                }
                continue
            }

            let activity = stats.lastActivity ?? session.lastModified
            guard contains(activity, in: interval) else { continue }

            for model in stats.models {
                add(provider: session.provider, model: model.model, count: model.messageCount, usage: model.usage, cost: model.costEstimate)
            }

            let buckets: [ModelBucket]
            if !stats.timeline.isEmpty {
                buckets = stats.timeline
            } else {
                let bucketStart = calendar.dateInterval(of: .hour, for: activity)?.start ?? activity
                buckets = stats.models.compactMap { model in
                    guard model.usage.total > 0 else { return nil }
                    return ModelBucket(model: model.model, start: bucketStart, usage: model.usage)
                }
            }
            for bucket in buckets {
                addTimeline(provider: session.provider, model: bucket.model, date: bucket.start, usage: bucket.usage)
            }
        }

        let models = perModel
            .map { (key: $0.key, value: $0.value) }
            .sorted { lhs, rhs in
                if lhs.value.usage.total != rhs.value.usage.total {
                    return lhs.value.usage.total > rhs.value.usage.total
                }
                if lhs.key.model != rhs.key.model { return lhs.key.model < rhs.key.model }
                return (lhs.key.provider?.rawValue ?? "") < (rhs.key.provider?.rawValue ?? "")
            }
        let timeline = perModelHourly
            .flatMap { key, byHour in byHour.map { AggregateBucket(key: key, start: $0.key, usage: $0.value) } }
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                if lhs.key.model != rhs.key.model { return lhs.key.model < rhs.key.model }
                return (lhs.key.provider?.rawValue ?? "") < (rhs.key.provider?.rawValue ?? "")
            }
        return AggregateCore(models: models, timeline: timeline)
    }

    private static func contains(_ date: Date, in interval: DateInterval?) -> Bool {
        guard let interval else { return true }
        return date >= interval.start && date < interval.end
    }

    private static func costEstimate(for bucket: ModelBucket, modelUsage: ModelUsage?) -> CostEstimate {
        guard let modelUsage,
              modelUsage.usage.total > 0,
              bucket.usage.total > 0 else {
            return .zero
        }
        let fraction = Double(bucket.usage.total) / Double(modelUsage.usage.total)
        return scaled(modelUsage.costEstimate, by: fraction)
    }

    private static func messageCount(for bucket: ModelBucket, modelUsage: ModelUsage?) -> Int {
        guard let modelUsage,
              modelUsage.usage.total > 0,
              bucket.usage.total > 0 else {
            return bucket.usage.total > 0 ? 1 : 0
        }
        let fraction = Double(bucket.usage.total) / Double(modelUsage.usage.total)
        return roundedInt(Double(modelUsage.messageCount) * fraction)
    }

    private static func scaled(_ cost: CostEstimate, by fraction: Double) -> CostEstimate {
        CostEstimate(
            standardAPI: cost.standardAPI * fraction,
            detailedBilling: cost.detailedBilling * fraction,
            codexCredits: cost.codexCredits.map { $0 * fraction }
        )
    }

    private static func roundedInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return max(0, Int(value.rounded()))
    }

    private struct AggregateKey: Sendable, Hashable {
        let provider: ProviderKind?
        let model: String
    }

    private struct AggregateBucket: Sendable, Hashable {
        let key: AggregateKey
        let start: Date
        let usage: TokenUsage
    }

    private struct AggregateCore {
        let models: [(key: AggregateKey, value: (count: Int, usage: TokenUsage, cost: CostEstimate))]
        let timeline: [AggregateBucket]
    }
}
