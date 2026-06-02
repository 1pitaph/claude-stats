import SwiftUI

struct ActivityControls: View {
    @Binding var range: ActivityRange
    let selectedDay: Date
    let canStepForward: Bool
    let isLoading: Bool
    let onStepDay: (Int) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Spacer(minLength: 0)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .help("Loading activity")
            }

            ActivityDailyPeriodControl(
                range: $range,
                selectedDay: selectedDay,
                canStepForward: canStepForward,
                onStepDay: onStepDay
            )

            ActivityRangeChips(range: $range)
        }
        .animation(.easeOut(duration: 0.18), value: range)
    }
}

private struct ActivityDailyPeriodControl: View {
    @Binding var range: ActivityRange
    let selectedDay: Date
    let canStepForward: Bool
    let onStepDay: (Int) -> Void

    private var isSelected: Bool {
        range == .day
    }

    var body: some View {
        PillTimeStepperBar(
            canStepForward: canStepForward,
            isCenterSelected: isSelected,
            previousHelp: "Previous day",
            nextHelp: "Next day",
            centerHelp: "Show selected day",
            centerAccessibilityLabel: "Selected day",
            accessibilityLabel: "Day navigation",
            onPrevious: {
                stepDay(-1)
            },
            onNext: {
                stepDay(1)
            },
            onCenter: {
                withAnimation(.easeOut(duration: 0.18)) {
                    range = .day
                }
            }
        ) { _ in
            Text(ActivityDailyDateLabel.label(for: selectedDay))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func stepDay(_ offset: Int) {
        withAnimation(.easeOut(duration: 0.18)) {
            onStepDay(offset)
            range = .day
        }
    }
}

private enum ActivityDailyDateLabel {
    static func label(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        if day == today {
            return L10n.string("activity.daily_date.today", defaultValue: "Today")
        }

        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
            ?? today.addingTimeInterval(-86_400)
        if day == yesterday {
            return L10n.string("activity.daily_date.yesterday", defaultValue: "Yesterday")
        }

        return Format.day(day)
    }
}

private struct ActivityRangeChips: View {
    @Binding var range: ActivityRange

    private static let values: [ActivityRange] = [.last7Days, .last30Days]

    var body: some View {
        PillSegmentedBar(
            Self.values,
            selection: $range,
            help: { "Show last \($0.dayCount) days" },
            accessibilityLabel: { "Last \($0.dayCount) days" }
        ) { value, _ in
            Text(value.mainWindowLabel)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity range")
    }
}

#if DEBUG
#Preview {
    struct Wrap: View {
        @State private var range = ActivityRange.day
        var body: some View {
            ActivityControls(
                range: $range,
                selectedDay: .now,
                canStepForward: false,
                isLoading: false,
                onStepDay: { _ in }
            )
            .padding(24)
            .frame(width: 720)
            .background(Color.stxBackground)
        }
    }

    return Wrap()
}
#endif
