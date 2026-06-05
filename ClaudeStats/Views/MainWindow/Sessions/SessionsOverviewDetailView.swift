import SwiftUI

/// Provider-scoped sessions landing page shown when the user enters Sessions
/// from the main sidebar. Selecting a concrete transcript in the secondary
/// sidebar swaps this overview for ``SessionDetailView``.
struct SessionsOverviewDetailView: View {
    @Environment(AppEnvironment.self) private var env

    private var provider: ProviderKind {
        env.preferences.selectedProvider
    }

    private var sessions: [Session] {
        env.store.sessions(for: provider)
    }

    private var summary: UsageSummary {
        env.store.summary(for: .allTime, provider: provider)
    }

    private var projectCount: Int {
        Set(sessions.map(\.projectDirectoryName)).count
    }

    private var lastActivity: Date? {
        sessions.map(activityDate).max()
    }

    private var recentSessions: [Session] {
        Array(sessions.sorted { activityDate($0) > activityDate($1) }.prefix(8))
    }

    private var cacheHitRate: Double? {
        env.store.cacheHitRate(for: summary.totalUsage, provider: provider)
    }

    var body: some View {
        CenteredPaneContainer {
            VStack(alignment: .leading, spacing: 18) {
                header

                if sessions.isEmpty {
                    emptyState
                } else {
                    statsGrid
                    modelBreakdown
                    recentSessionsSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: provider.iconSystemName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(provider.accentColor)
                Text("SESSIONS")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
            }

            Text("\(provider.shortName) session statistics")
                .font(.sora(24, weight: .semibold))

            Text("All discovered conversations for the current provider.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                env.store.isLoading ? "Scanning Sessions" : "No Sessions",
                systemImage: env.store.isLoading ? "arrow.triangle.2.circlepath" : "tray"
            )
        } description: {
            Text(emptyStateMessage)
        }
        .font(.sora(12))
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var emptyStateMessage: String {
        if env.store.isLoading {
            return "Scanning sessions for \(provider.shortName)..."
        }
        if let path = env.store.dataDirectoryPath(for: provider), !path.isEmpty {
            return "No sessions found in \(path)."
        }
        return "No sessions for \(provider.shortName) yet."
    }

    private var statsGrid: some View {
        ViewThatFits(in: .horizontal) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    sessionCountCard
                    projectCountCard
                    messageCountCard
                    tokenCountCard
                }
                GridRow {
                    estimatedCostCard
                    modelCountCard
                    cacheHitCard
                    lastActivityCard
                }
            }

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    sessionCountCard
                    projectCountCard
                }
                GridRow {
                    messageCountCard
                    tokenCountCard
                }
                GridRow {
                    estimatedCostCard
                    modelCountCard
                }
                GridRow {
                    cacheHitCard
                    lastActivityCard
                }
            }
        }
    }

    private var sessionCountCard: some View {
        StatCard(label: "SESSIONS", value: "\(summary.sessionCount)")
    }

    private var projectCountCard: some View {
        StatCard(label: "PROJECTS", value: "\(projectCount)")
    }

    private var messageCountCard: some View {
        StatCard(label: "MESSAGES", value: Format.tokens(summary.messageCount))
    }

    private var tokenCountCard: some View {
        StatCard(
            label: "TOTAL TOKENS",
            value: Format.tokens(summary.totalTokens(includingCacheRead: env.preferences.includeCacheInTokens))
        )
    }

    private var estimatedCostCard: some View {
        let mode = env.preferences.costEstimationMode
        return StatCard(
            label: "EST. COST",
            value: Format.costEstimate(summary.totalCost(for: mode),
                                       mode: mode,
                                       usesCredits: summary.totalCostUsesCredits(for: mode))
        )
    }

    private var modelCountCard: some View {
        StatCard(label: "MODELS", value: "\(summary.models.count)")
    }

    private var cacheHitCard: some View {
        StatCard(
            label: "CACHE HIT",
            value: cacheHitRate.map { Format.percent($0) } ?? "--",
            animatesNumericValue: false
        )
    }

    private var lastActivityCard: some View {
        StatCard(
            label: "LAST ACTIVITY",
            value: lastActivity.map { Format.relativeDate($0) } ?? "--",
            animatesNumericValue: false
        )
    }

    @ViewBuilder
    private var modelBreakdown: some View {
        if !summary.models.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("BY MODEL")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.stxMuted)
                ModelTable(
                    models: summary.models,
                    includeCacheInTotals: env.preferences.includeCacheInTokens,
                    displayName: { env.store.displayName(forModel: $0, provider: provider) }
                )
            }
        }
    }

    @ViewBuilder
    private var recentSessionsSection: some View {
        if !recentSessions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT SESSIONS")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.stxMuted)

                VStack(spacing: 0) {
                    ForEach(recentSessions) { session in
                        SessionRow(session: session)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .appSurface(.compactCard(radius: 10))
            }
        }
    }

    private func activityDate(_ session: Session) -> Date {
        session.stats?.lastActivity ?? session.lastModified
    }
}

#if DEBUG
#Preview("Sessions overview") {
    SessionsOverviewDetailView()
        .environment(AppEnvironment.preview())
        .frame(width: 760, height: 640)
        .background(Color.stxBackground)
}
#endif
