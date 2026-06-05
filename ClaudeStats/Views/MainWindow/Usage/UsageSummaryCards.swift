import SwiftUI

struct UsageSummaryCards: View {
    let summary: UsageSummary
    let includeCacheInTokens: Bool
    let costEstimationMode: CostEstimationMode
    let cacheHitRate: Double?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    card(L10n.string("usage.stat.tokens", defaultValue: "TOKENS"), Format.tokens(summary.totalTokens(includingCacheRead: includeCacheInTokens)))
                    card(L10n.string("usage.stat.estimated_cost", defaultValue: "EST. COST"), formattedCost)
                    card(L10n.string("usage.stat.sessions", defaultValue: "SESSIONS"), "\(summary.sessionCount)")
                }
                GridRow {
                    card(L10n.string("usage.stat.messages", defaultValue: "MESSAGES"), Format.tokens(summary.messageCount))
                    card(L10n.string("usage.stat.cache_hit", defaultValue: "CACHE HIT"), cacheHitRate.map(Format.percent) ?? "--")
                    card(L10n.string("usage.stat.cached", defaultValue: "CACHED"), Format.tokens(summary.totalUsage.cacheReadTokens))
                }
            }

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    card(L10n.string("usage.stat.tokens", defaultValue: "TOKENS"), Format.tokens(summary.totalTokens(includingCacheRead: includeCacheInTokens)))
                    card(L10n.string("usage.stat.estimated_cost", defaultValue: "EST. COST"), formattedCost)
                }
                GridRow {
                    card(L10n.string("usage.stat.sessions", defaultValue: "SESSIONS"), "\(summary.sessionCount)")
                    card(L10n.string("usage.stat.messages", defaultValue: "MESSAGES"), Format.tokens(summary.messageCount))
                }
                GridRow {
                    card(L10n.string("usage.stat.cache_hit", defaultValue: "CACHE HIT"), cacheHitRate.map(Format.percent) ?? "--")
                    card(L10n.string("usage.stat.cached", defaultValue: "CACHED"), Format.tokens(summary.totalUsage.cacheReadTokens))
                }
            }
        }
    }

    private var formattedCost: String {
        Format.costEstimate(summary.totalCost(for: costEstimationMode),
                            mode: costEstimationMode,
                            usesCredits: summary.totalCostUsesCredits(for: costEstimationMode))
    }

    private func card(_ label: String, _ value: String) -> some View {
        StatCard(label: label, value: value)
    }
}

#if DEBUG
#Preview {
    UsageSummaryCards(
        summary: .empty(period: .last30Days),
        includeCacheInTokens: true,
        costEstimationMode: .standardAPI,
        cacheHitRate: 0.84
    )
    .padding(24)
    .frame(width: 760)
    .background(Color.stxBackground)
}
#endif
