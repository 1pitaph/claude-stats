import SwiftUI

/// The status-item content: an icon plus a compact tokens-or-cost figure for
/// the configured period.
struct MenuBarLabel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let prefs = env.preferences
        let summary = env.store.summary(for: prefs.menuBarPeriod, provider: prefs.selectedProvider)
        let value = valueText(summary: summary, metric: prefs.menuBarMetric)
        HStack(spacing: 4) {
            Image(systemName: AppIcon.Workspace.usage)
            Text(value)
                .monospacedDigit()
                .stxNumericValueTransition(value: value)
        }
        .accessibilityLabel("\(prefs.selectedProvider.shortName) Stats — \(prefs.menuBarPeriod.displayName)")
    }

    private func valueText(summary: UsageSummary, metric: MenuBarMetric) -> String {
        if env.store.sessions(for: env.preferences.selectedProvider).isEmpty && env.store.isLoading { return "…" }
        switch metric {
        case .tokens:
            return Format.tokens(summary.totalTokens(includingCacheRead: env.preferences.menuBarIncludesCache))
        case .cost:
            return Format.cost(summary.totalCost(for: env.preferences.costEstimationMode))
        }
    }
}

#if DEBUG
// Standalone preview of the status-item content only. The label actually
// lives in the system menu bar via `MenuBarExtra` — a `Scene`, which Xcode's
// Canvas can't render. Run the app (`bash scripts/run-debug.sh`) to see it
// in the real menu bar.
#Preview("Menu bar label") {
    VStack(alignment: .leading, spacing: 14) {
        MenuBarLabel().environment(AppEnvironment.preview())
        MenuBarLabel().environment(AppEnvironment.preview())
            .environment(\.colorScheme, .dark)
            .padding(6)
            .background(.black)
        MenuBarLabel().environment(AppEnvironment.preview(populated: false))
    }
    .padding()
}
#endif
