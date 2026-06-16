import Foundation

enum OpenAIFloatingStatusAdapter {
    static let targetGroupID = OpenAIStatusGroupCatalog.codexID
    static let dayCount = 30

    @MainActor
    static func summary(from status: OpenAIStatusViewModel) -> FloatingProviderStatusSummary? {
        guard let snapshot = status.snapshot else { return nil }
        return summary(
            snapshot: snapshot,
            uptimeSnapshot: status.uptimeSnapshot,
            isStale: status.isStale,
            isUptimeStale: status.isUptimeStale
        )
    }

    static func summary(
        snapshot: OpenAIStatusSnapshot,
        uptimeSnapshot: OpenAIStatusUptimeSnapshot?,
        isStale: Bool = false,
        isUptimeStale: Bool = false
    ) -> FloatingProviderStatusSummary? {
        guard let group = targetGroup(in: snapshot, uptimeSnapshot: uptimeSnapshot) else { return nil }
        let history = uptimeSnapshot?.history(for: group)

        return FloatingProviderStatusSummary(
            id: "openai:\(group.id)",
            title: group.name,
            statusText: group.status.displayName,
            severity: FloatingStatusSeverity(group.status),
            days: days(from: history),
            uptimePercent: history?.uptimePercent(recentDayCount: dayCount),
            isStale: isStale || isUptimeStale
        )
    }

    private static func targetGroup(
        in snapshot: OpenAIStatusSnapshot,
        uptimeSnapshot: OpenAIStatusUptimeSnapshot?
    ) -> OpenAIStatusGroup? {
        let groups = OpenAIStatusGroupCatalog.groups(
            from: snapshot.components,
            definitions: uptimeSnapshot?.groupDefinitions ?? OpenAIStatusGroupCatalog.defaultGroupDefinitions
        )
        return groups.first { $0.id == targetGroupID }
            ?? snapshot.groups.first { $0.id == targetGroupID }
            ?? groups.first { $0.name.caseInsensitiveCompare("Codex") == .orderedSame }
            ?? snapshot.groups.first { $0.name.caseInsensitiveCompare("Codex") == .orderedSame }
    }

    private static func days(from history: OpenAIStatusUptimeHistory?) -> [FloatingStatusDay] {
        guard let history else { return [] }
        return history.recentDays(count: dayCount).map { day in
            FloatingStatusDay(
                date: day.date,
                state: state(for: day, startDate: history.startDate),
                helpText: helpText(for: day)
            )
        }
    }

    private static func state(for day: OpenAIStatusUptimeDay, startDate: Date?) -> FloatingStatusDay.State {
        if let startDate, day.date < startDate {
            return .noData
        }
        if day.fullOutageSeconds > 0 {
            return .majorOutage
        }
        if day.partialOutageSeconds > 0 || day.degradedPerformanceSeconds > 0 {
            return .partialOutage
        }
        switch day.chartSeverity {
        case .fullOutage:
            return .majorOutage
        case .partialOutage, .degradedPerformance, .underMaintenance:
            return .partialOutage
        case .operational, .unknown, nil:
            return .operational
        }
    }

    private static func helpText(for day: OpenAIStatusUptimeDay) -> String {
        let date = Format.day(day.date)
        guard day.hasOutage else { return "\(date): no downtime recorded" }

        var parts: [String] = []
        if day.degradedPerformanceSeconds > 0 {
            parts.append("degraded performance \(Format.duration(TimeInterval(day.degradedPerformanceSeconds)))")
        }
        if day.partialOutageSeconds > 0 {
            parts.append("partial outage \(Format.duration(TimeInterval(day.partialOutageSeconds)))")
        }
        if day.fullOutageSeconds > 0 {
            parts.append("full outage \(Format.duration(TimeInterval(day.fullOutageSeconds)))")
        }
        if parts.isEmpty, !day.displaySeverity.isOperational {
            parts.append(day.displaySeverity.displayName)
        }
        if let event = day.relatedEvents.first {
            parts.append(event.name)
        }
        return "\(date): \(parts.joined(separator: ", "))"
    }
}

private extension FloatingStatusSeverity {
    init(_ severity: OpenAIStatusSeverity) {
        switch severity {
        case .operational:
            self = .operational
        case .underMaintenance:
            self = .underMaintenance
        case .degradedPerformance:
            self = .degradedPerformance
        case .partialOutage:
            self = .partialOutage
        case .fullOutage:
            self = .majorOutage
        case .unknown:
            self = .unknown
        }
    }
}
