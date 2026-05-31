import SwiftUI

struct MenuBarSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(title: "Show", caption: "Pick which metric the menu-bar status item displays.") {
                SettingSegmentCard(
                    selection: $prefs.menuBarMetric,
                    options: [
                        .init(value: .tokens,
                              title: "Tokens",
                              subtitle: "Total tokens across the chosen period.",
                              symbol: AppIcon.Metric.number),
                        .init(value: .cost,
                              title: "Cost",
                              subtitle: "Estimated USD across the chosen period.",
                              symbol: AppIcon.Metric.cost),
                    ]
                )
            }

            SettingGroup(title: "Period") {
                VStack(spacing: 0) {
                    SettingRow(title: "Time range",
                               description: "How far back to add up the menu-bar metric.") {
                        AppSelect(
                            .localized("Time range"),
                            selection: $prefs.menuBarPeriod,
                            options: StatsPeriod.allCases.map {
                                AppSelectOption(value: $0, title: .localized($0.displayName))
                            },
                            width: 180
                        )
                    }

                    if prefs.menuBarMetric == .tokens {
                        SettingRowDivider()
                        SettingRow(title: "Include cache reads",
                                   description: "Independent from the in-app setting, so the menu bar can show a less inflated figure (or vice versa).") {
                            Toggle("", isOn: $prefs.menuBarIncludesCache)
                                .labelsHidden()
                                .toggleStyle(.appSwitch)
                        }
                    }
                }
                .settingCard()
            }
        }
    }
}

#if DEBUG
#Preview {
    MenuBarSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
