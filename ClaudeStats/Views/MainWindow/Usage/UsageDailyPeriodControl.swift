import SwiftUI

struct UsageDailyPeriodControl: View {
    @Binding var period: StatsPeriod
    @Binding var selectedDay: Date

    private var isSelected: Bool {
        period == .today
    }

    private var canStepForward: Bool {
        UsageDailyDateNavigator.canStepForward(from: selectedDay)
    }

    var body: some View {
        PillTimeStepperBar(
            canStepForward: canStepForward,
            isCenterSelected: isSelected,
            previousHelp: L10n.string("usage.daily_date.previous_help", defaultValue: "Previous day"),
            nextHelp: L10n.string("usage.daily_date.next_help", defaultValue: "Next day"),
            centerHelp: L10n.string("usage.daily_date.center_help", defaultValue: "Show selected day"),
            centerAccessibilityLabel: L10n.string("usage.daily_date.center_accessibility", defaultValue: "Selected usage day"),
            accessibilityLabel: L10n.string("usage.daily_date.accessibility", defaultValue: "Usage day"),
            onPrevious: {
                stepDay(-1)
            },
            onNext: {
                stepDay(1)
            },
            onCenter: {
                withAnimation(.easeOut(duration: 0.18)) {
                    period = .today
                }
            }
        ) { _ in
            Text(UsageDailyDateNavigator.label(for: selectedDay))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func stepDay(_ offset: Int) {
        withAnimation(.easeOut(duration: 0.18)) {
            selectedDay = UsageDailyDateNavigator.stepped(from: selectedDay, by: offset)
            period = .today
        }
    }
}

#if DEBUG
#Preview {
    struct Wrap: View {
        @State private var period: StatsPeriod = .today
        @State private var selectedDay = UsageDailyDateNavigator.todayStart()

        var body: some View {
            UsageDailyPeriodControl(period: $period, selectedDay: $selectedDay)
                .padding(24)
                .background(Color.stxBackground)
        }
    }

    return Wrap()
}
#endif
