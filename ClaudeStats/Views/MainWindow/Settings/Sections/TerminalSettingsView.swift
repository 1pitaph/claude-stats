import SwiftUI

struct TerminalSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(title: "Runtime") {
                SettingSegmentCard(
                    selection: $prefs.terminalRuntimeKind,
                    options: TerminalRuntimeKind.allCases.map {
                        SettingSegmentCard<TerminalRuntimeKind>.Option(
                            value: $0,
                            title: $0.displayName,
                            subtitle: $0.description,
                            symbol: $0.symbol
                        )
                    }
                )
            }

            SettingGroup(title: "Appearance") {
                TerminalAppearancePreview(
                    chromeMode: prefs.terminalChromeMode,
                    backgroundStyle: prefs.terminalBackgroundStyle
                )
            }

            SettingGroup(title: "Chrome") {
                SettingSegmentCard(
                    selection: $prefs.terminalChromeMode,
                    options: TerminalChromeMode.allCases.map {
                        SettingSegmentCard<TerminalChromeMode>.Option(
                            value: $0,
                            title: $0.displayName,
                            subtitle: $0.description,
                            symbol: $0.symbol
                        )
                    }
                )
            }

            SettingGroup(title: "Background") {
                SettingSegmentCard(
                    selection: $prefs.terminalBackgroundStyle,
                    options: TerminalBackgroundStyle.allCases.map {
                        SettingSegmentCard<TerminalBackgroundStyle>.Option(
                            value: $0,
                            title: $0.displayName,
                            subtitle: $0.description,
                            symbol: $0.symbol
                        )
                    }
                )
            }
        }
    }
}

#if DEBUG
#Preview {
    TerminalSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 760)
}
#endif
