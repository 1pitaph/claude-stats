import ClaudeStatsCore
import Foundation

@MainActor
enum StatsStatusSnapshotBuilder {
    static func make(environment env: AppEnvironment) -> StatsStatusSummary {
        StatsStatusSummary(
            providers: [
                makeClaudeStatus(status: env.claudeStatus),
                makeOpenAIStatus(status: env.openAIStatus),
            ].compactMap { $0 }
        )
    }

    static func makeClaudeStatus(status: ClaudeStatusViewModel) -> StatsStatusProviderSnapshot? {
        guard let snapshot = status.snapshot else { return nil }
        let components = snapshot.components
        let defaultVisibleIDs = ClaudeStatusComponentCatalog.visibleComponentIDs(
            from: ClaudeStatusComponentCatalog.defaultVisibleComponentIDs,
            components: components
        )
        let histories = components.compactMap { component in
            status.uptimeSnapshot?.history(for: component).map { makeClaudeUptimeHistory($0) }
        }

        return StatsStatusProviderSnapshot(
            providerID: .claude,
            providerName: "Claude",
            statusPageURL: status.statusPageURL,
            pageName: snapshot.pageName,
            pageUpdatedAt: snapshot.pageUpdatedAt,
            rollup: StatsStatusRollup(
                severity: StatsStatusSeverity(rawStatus: snapshot.rollup.severity.rawStatus),
                description: snapshot.rollup.description
            ),
            items: components.map { component in
                StatsStatusItem(
                    id: component.id,
                    name: component.name,
                    status: StatsStatusSeverity(rawStatus: component.status.rawStatus),
                    updatedAt: component.updatedAt,
                    position: component.position
                )
            },
            defaultVisibleItemIDs: defaultVisibleIDs,
            uptimeHistories: histories,
            incidents: snapshot.incidents
                .filter { !$0.isResolved }
                .map { incident in
                    StatsStatusIncident(
                        id: incident.id,
                        name: incident.name,
                        status: incident.status,
                        impact: StatsStatusSeverity(rawStatus: incident.impact.rawStatus),
                        shortlink: incident.shortlink,
                        startedAt: incident.startedAt,
                        updatedAt: incident.updatedAt
                    )
                },
            fetchedAt: snapshot.fetchedAt,
            isSummaryStale: status.isStale,
            summaryError: status.lastError,
            isUptimeStale: status.isUptimeStale,
            uptimeError: status.uptimeLastError
        )
    }

    static func makeOpenAIStatus(status: OpenAIStatusViewModel) -> StatsStatusProviderSnapshot? {
        guard let snapshot = status.snapshot else { return nil }
        let groups = status.availableGroups
        let defaultVisibleIDs = OpenAIStatusGroupCatalog.visibleGroupIDs(
            from: OpenAIStatusGroupCatalog.defaultVisibleGroupIDs,
            groups: groups
        )
        let histories = groups.compactMap { group in
            status.uptimeSnapshot?.history(for: group).map { makeOpenAIUptimeHistory($0) }
        }

        return StatsStatusProviderSnapshot(
            providerID: .openAI,
            providerName: "OpenAI",
            statusPageURL: status.statusPageURL,
            pageName: snapshot.pageName,
            pageUpdatedAt: snapshot.pageUpdatedAt,
            rollup: StatsStatusRollup(
                severity: StatsStatusSeverity(rawStatus: snapshot.rollup.severity.rawStatus),
                description: snapshot.rollup.description
            ),
            items: groups.map { group in
                StatsStatusItem(
                    id: group.id,
                    name: group.name,
                    status: StatsStatusSeverity(rawStatus: group.status.rawStatus),
                    updatedAt: group.updatedAt,
                    position: group.position
                )
            },
            defaultVisibleItemIDs: defaultVisibleIDs,
            uptimeHistories: histories,
            incidents: snapshot.incidents
                .filter { !$0.isResolved }
                .map { incident in
                    StatsStatusIncident(
                        id: incident.id,
                        name: incident.name,
                        status: incident.status,
                        impact: StatsStatusSeverity(rawStatus: incident.impact.rawStatus),
                        shortlink: incident.shortlink,
                        startedAt: incident.startedAt,
                        updatedAt: incident.updatedAt
                    )
                },
            fetchedAt: snapshot.fetchedAt,
            isSummaryStale: status.isStale,
            summaryError: status.lastError,
            isUptimeStale: status.isUptimeStale,
            uptimeError: status.uptimeLastError
        )
    }

    private static func makeClaudeUptimeHistory(_ history: ClaudeStatusUptimeHistory) -> StatsStatusUptimeHistory {
        StatsStatusUptimeHistory(
            itemID: history.componentID,
            itemName: history.componentName,
            startDate: history.startDate,
            days: history.recentDays().map { day in
                StatsStatusUptimeDay(
                    date: day.date,
                    partialOutageSeconds: day.partialOutageSeconds,
                    majorOutageSeconds: day.majorOutageSeconds,
                    relatedEvents: day.relatedEvents.map { event in
                        StatsStatusUptimeEvent(name: event.name, code: event.code)
                    },
                    barFillHex: day.barFillHex
                )
            },
            sourceUptimePercent: history.sourceUptimePercent
        )
    }

    private static func makeOpenAIUptimeHistory(_ history: OpenAIStatusUptimeHistory) -> StatsStatusUptimeHistory {
        StatsStatusUptimeHistory(
            itemID: history.groupID,
            itemName: history.groupName,
            startDate: history.startDate,
            days: history.recentDays().map { day in
                StatsStatusUptimeDay(
                    date: day.date,
                    degradedPerformanceSeconds: day.degradedPerformanceSeconds,
                    partialOutageSeconds: day.partialOutageSeconds,
                    fullOutageSeconds: day.fullOutageSeconds,
                    relatedEvents: day.relatedEvents.map { event in
                        StatsStatusUptimeEvent(name: event.name, code: event.code, permalink: event.permalink)
                    }
                )
            },
            sourceUptimePercent: history.sourceUptimePercent
        )
    }
}
