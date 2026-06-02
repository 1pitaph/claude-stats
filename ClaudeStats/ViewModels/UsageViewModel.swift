import Foundation
import Observation

/// How the Usage trend panel is drawn.
enum TrendChartStyle: Sendable, Hashable { case line, bar }

/// Vertical scaling for the trend panel — `log` (ln(1+x)) compresses big gaps
/// between models so the smaller ones stay legible.
enum TrendScaleMode: Sendable, Hashable { case linear, log }

struct UsageDerivedData: Sendable {
    struct Key: Sendable, Hashable {
        let period: StatsPeriod
        let selectedDay: Date
        let provider: ProviderKind
        let lastRefreshedAt: Date?

        var chartSeriesID: String {
            let refreshID = lastRefreshedAt
                .map { String(Int(($0.timeIntervalSinceReferenceDate * 1_000).rounded())) }
                ?? "never"
            return "\(provider.rawValue)|\(period.rawValue)|\(selectedDay.timeIntervalSinceReferenceDate)|\(refreshID)"
        }
    }

    let key: Key
    let summary: UsageSummary
    let series: TrendSeries
    let cacheHitRate: Double?

    @MainActor
    static func make(key: Key, store: SessionStore) -> UsageDerivedData {
        let summary = key.period == .today
            ? store.summary(forDay: key.selectedDay, provider: key.provider)
            : store.summary(for: key.period, provider: key.provider)
        let series = summary.trendSeries(now: key.selectedDay)
        let cacheHitRate = store.cacheHitRate(for: summary.totalUsage, provider: key.provider)
        return UsageDerivedData(key: key, summary: summary, series: series, cacheHitRate: cacheHitRate)
    }

    static func empty(for key: Key) -> UsageDerivedData {
        let summary = UsageSummary.empty(period: key.period)
        return UsageDerivedData(
            key: key,
            summary: summary,
            series: summary.trendSeries(),
            cacheHitRate: nil
        )
    }
}

/// UI state for the Usage screen: the selected ``StatsPeriod`` plus how the
/// trend panel is drawn. The summary itself is derived from a ``SessionStore``
/// passed in by the view.
@MainActor
@Observable
final class UsageViewModel {
    var period: StatsPeriod = .allTime
    var selectedDay: Date = UsageDailyDateNavigator.todayStart()
    /// Line vs. bar for the trend panel (ignored for the Today/hourly view,
    /// which is always a smoothed line).
    var chartStyle: TrendChartStyle = .line
    /// Linear vs. ln scaling (only used in line mode on non-Today periods).
    var scaleMode: TrendScaleMode = .linear
    /// When on, the trend panel stacks by token *type* (Output / Input /
    /// Cache Write / Cache Read) instead of by model — surfaces cache-hit
    /// efficiency at a glance.
    var stackByType: Bool = false
    private(set) var derivedData: UsageDerivedData?

    func summary(from store: SessionStore, provider: ProviderKind) -> UsageSummary {
        store.summary(for: period, provider: provider)
    }

    func refreshDerivedData(from store: SessionStore, provider: ProviderKind, lastRefreshedAt: Date?) {
        let key = UsageDerivedData.Key(
            period: period,
            selectedDay: UsageDailyDateNavigator.normalized(selectedDay),
            provider: provider,
            lastRefreshedAt: lastRefreshedAt
        )
        guard derivedData?.key != key else { return }
        derivedData = UsageDerivedData.make(key: key, store: store)
    }

    func displayedDerivedData(provider: ProviderKind, lastRefreshedAt: Date?) -> UsageDerivedData {
        let key = UsageDerivedData.Key(
            period: period,
            selectedDay: UsageDailyDateNavigator.normalized(selectedDay),
            provider: provider,
            lastRefreshedAt: lastRefreshedAt
        )
        guard let derivedData, derivedData.key == key else {
            return .empty(for: key)
        }
        return derivedData
    }
}
