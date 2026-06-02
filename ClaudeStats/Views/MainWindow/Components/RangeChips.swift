import SwiftUI

/// Three small "Weekly / Monthly / All" chips at the top-right of the Dashboard.
/// Scopes the 8 stat cards only — the heatmap below them stays fixed at the
/// 3-month rolling window regardless of selection.
struct RangeChips: View {
    @Binding var period: StatsPeriod

    /// The chips we surface here, in display order. `.today` is intentionally
    /// omitted — the Dashboard story is "what does my recent activity look
    /// like", not "what happened today".
    static let supported: [StatsPeriod] = [.last7Days, .last30Days, .allTime]

    var body: some View {
        PillSegmentedBar(
            Self.supported,
            selection: $period
        ) { value, _ in
            Text(Self.label(for: value))
        }
    }

    private static func label(for period: StatsPeriod) -> String {
        switch period {
        case .allTime: L10n.string("range.all", defaultValue: "All")
        case .last30Days: L10n.string("range.monthly", defaultValue: "Monthly")
        case .last7Days: L10n.string("range.weekly", defaultValue: "Weekly")
        case .today: L10n.string("stats.period.today", defaultValue: "Today")
        }
    }
}

#if DEBUG
#Preview {
    struct Wrap: View {
        @State var p: StatsPeriod = .last30Days
        var body: some View {
            RangeChips(period: $p).padding(24).frame(width: 360)
        }
    }
    return Wrap().background(Color.stxBackground)
}
#endif
