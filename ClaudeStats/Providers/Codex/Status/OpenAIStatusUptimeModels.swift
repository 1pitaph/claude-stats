import Foundation

struct OpenAIStatusUptimeSnapshot: Sendable, Codable, Equatable {
    let histories: [String: OpenAIStatusUptimeHistory]
    let groupDefinitions: [OpenAIStatusGroupDefinition]
    let fetchedAt: Date

    func history(for group: OpenAIStatusGroup) -> OpenAIStatusUptimeHistory? {
        histories[group.id]
            ?? histories.values.first { $0.groupName == group.name }
    }
}

struct OpenAIStatusUptimeHistory: Identifiable, Sendable, Codable, Equatable {
    let groupID: String
    let groupName: String
    let startDate: Date?
    let days: [OpenAIStatusUptimeDay]
    let sourceUptimePercent: Double?

    var id: String { groupID }

    func recentDays(count: Int = OpenAIStatusUptimeWindow.dayCount) -> [OpenAIStatusUptimeDay] {
        guard days.count > count else { return days }
        return Array(days.suffix(count))
    }

    func uptimePercent(recentDayCount: Int = OpenAIStatusUptimeWindow.dayCount) -> Double? {
        if let sourceUptimePercent {
            return sourceUptimePercent
        }

        let window = recentDays(count: recentDayCount)
        let validDays = window.filter { day in
            guard let startDate else { return true }
            return day.date >= startDate
        }
        guard !validDays.isEmpty else { return nil }

        let totalSeconds = validDays.count * OpenAIStatusUptimeWindow.secondsPerDay
        let downtimeSeconds = validDays.reduce(0) { total, day in
            total + min(OpenAIStatusUptimeWindow.secondsPerDay, day.outageSeconds)
        }
        guard totalSeconds > 0 else { return nil }

        let uptimeRatio = 1 - (Double(downtimeSeconds) / Double(totalSeconds))
        return max(0, min(1, uptimeRatio)) * 100
    }
}

struct OpenAIStatusUptimeDay: Identifiable, Sendable, Codable, Equatable {
    let date: Date
    let degradedPerformanceSeconds: Int
    let partialOutageSeconds: Int
    let fullOutageSeconds: Int
    let relatedEvents: [OpenAIStatusUptimeEvent]
    let chartSeverity: OpenAIStatusSeverity?
    let barFillHex: String?

    var id: Date { date }

    init(
        date: Date,
        degradedPerformanceSeconds: Int = 0,
        partialOutageSeconds: Int = 0,
        fullOutageSeconds: Int = 0,
        relatedEvents: [OpenAIStatusUptimeEvent] = [],
        chartSeverity: OpenAIStatusSeverity? = nil,
        barFillHex: String? = nil
    ) {
        self.date = date
        self.degradedPerformanceSeconds = max(0, degradedPerformanceSeconds)
        self.partialOutageSeconds = max(0, partialOutageSeconds)
        self.fullOutageSeconds = max(0, fullOutageSeconds)
        self.relatedEvents = relatedEvents
        self.chartSeverity = chartSeverity
        self.barFillHex = barFillHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            date: try container.decode(Date.self, forKey: .date),
            degradedPerformanceSeconds: try container.decodeIfPresent(Int.self, forKey: .degradedPerformanceSeconds) ?? 0,
            partialOutageSeconds: try container.decodeIfPresent(Int.self, forKey: .partialOutageSeconds) ?? 0,
            fullOutageSeconds: try container.decodeIfPresent(Int.self, forKey: .fullOutageSeconds) ?? 0,
            relatedEvents: try container.decodeIfPresent([OpenAIStatusUptimeEvent].self, forKey: .relatedEvents) ?? [],
            chartSeverity: try container.decodeIfPresent(OpenAIStatusSeverity.self, forKey: .chartSeverity),
            barFillHex: try container.decodeIfPresent(String.self, forKey: .barFillHex)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(degradedPerformanceSeconds, forKey: .degradedPerformanceSeconds)
        try container.encode(partialOutageSeconds, forKey: .partialOutageSeconds)
        try container.encode(fullOutageSeconds, forKey: .fullOutageSeconds)
        try container.encode(relatedEvents, forKey: .relatedEvents)
        try container.encodeIfPresent(chartSeverity, forKey: .chartSeverity)
        try container.encodeIfPresent(barFillHex, forKey: .barFillHex)
    }

    var outageSeconds: Int {
        degradedPerformanceSeconds + partialOutageSeconds + fullOutageSeconds
    }

    var displaySeverity: OpenAIStatusSeverity {
        if fullOutageSeconds > 0 {
            return .fullOutage
        }
        if partialOutageSeconds > 0 {
            return .partialOutage
        }
        if degradedPerformanceSeconds > 0 {
            return .degradedPerformance
        }
        return chartSeverity ?? .operational
    }

    var hasOutage: Bool {
        outageSeconds > 0 || !displaySeverity.isOperational
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case degradedPerformanceSeconds
        case partialOutageSeconds
        case fullOutageSeconds
        case relatedEvents
        case chartSeverity
        case barFillHex
    }
}

struct OpenAIStatusUptimeEvent: Sendable, Codable, Equatable {
    let name: String
    let code: String
    let permalink: URL?
}

enum OpenAIStatusUptimeWindow {
    static let dayCount = 90
    static let secondsPerDay = 24 * 60 * 60
}

struct OpenAIStatusUptimeRow: Identifiable, Sendable, Equatable {
    let group: OpenAIStatusGroup
    let history: OpenAIStatusUptimeHistory?

    var id: String { group.id }
}
