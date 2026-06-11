import Foundation

struct SessionUsageAggregate: Sendable, Hashable {
    let models: [ModelUsage]
    let timeline: [ModelBucket]

    var totalUsage: TokenUsage { models.reduce(.zero) { $0 + $1.usage } }
    var totalCost: CostEstimate { models.reduce(.zero) { $0 + $1.costEstimate } }
}

enum SessionUsageAggregator {
    static func aggregate(sessions: [Session], calendar: Calendar = .current) -> SessionUsageAggregate {
        aggregate(sessions: sessions, interval: nil, calendar: calendar)
    }

    static func aggregate(sessions: [Session], in interval: DateInterval, calendar: Calendar = .current) -> SessionUsageAggregate {
        aggregate(sessions: sessions, interval: interval, calendar: calendar)
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
                    guard !name.isEmpty else { continue }
                    totals[name, default: 0] += Int64(bill.usage.total)
                }
            } else if !stats.timeline.isEmpty {
                for bucket in stats.timeline {
                    let name = bucket.model.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    totals[name, default: 0] += Int64(bucket.usage.total)
                }
            } else {
                for model in stats.models {
                    let name = model.model.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    totals[name, default: 0] += Int64(model.usage.total)
                }
            }
        }

        return totals
    }

    private static func aggregate(
        sessions: [Session],
        interval: DateInterval?,
        calendar: Calendar
    ) -> SessionUsageAggregate {
        var perModel: [String: (count: Int, usage: TokenUsage, cost: CostEstimate)] = [:]
        var perModelHourly: [String: [Date: TokenUsage]] = [:]
        var seen: Set<String> = []

        func add(model: String, count: Int, usage: TokenUsage, cost: CostEstimate) {
            var acc = perModel[model] ?? (0, .zero, .zero)
            acc.count += count
            acc.usage += usage
            acc.cost += cost
            perModel[model] = acc
        }

        func addTimeline(model: String, date: Date, usage: TokenUsage) {
            guard usage.total > 0 else { return }
            let hour = calendar.dateInterval(of: .hour, for: date)?.start
                ?? calendar.startOfDay(for: date)
            perModelHourly[model, default: [:]][hour, default: .zero] += usage
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
                    add(model: bill.model, count: 1, usage: bill.usage, cost: bill.cost)
                    if let timestamp = bill.timestamp {
                        addTimeline(model: bill.model, date: timestamp, usage: bill.usage)
                    }
                }
                continue
            }

            if let interval, !stats.timeline.isEmpty {
                let buckets = stats.timeline.filter { contains($0.start, in: interval) }
                for bucket in buckets {
                    add(model: bucket.model, count: bucket.usage.total > 0 ? 1 : 0, usage: bucket.usage, cost: .zero)
                    addTimeline(model: bucket.model, date: bucket.start, usage: bucket.usage)
                }
                continue
            }

            let activity = stats.lastActivity ?? session.lastModified
            guard contains(activity, in: interval) else { continue }

            for model in stats.models {
                add(model: model.model, count: model.messageCount, usage: model.usage, cost: model.costEstimate)
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
                addTimeline(model: bucket.model, date: bucket.start, usage: bucket.usage)
            }
        }

        let models = perModel
            .map { ModelUsage(model: $0.key, messageCount: $0.value.count, usage: $0.value.usage, costEstimate: $0.value.cost) }
            .sorted { $0.usage.total > $1.usage.total }
        let timeline = perModelHourly
            .flatMap { model, byHour in byHour.map { ModelBucket(model: model, start: $0.key, usage: $0.value) } }
            .sorted { $0.start < $1.start }
        return SessionUsageAggregate(models: models, timeline: timeline)
    }

    private static func contains(_ date: Date, in interval: DateInterval?) -> Bool {
        guard let interval else { return true }
        return date >= interval.start && date < interval.end
    }
}
