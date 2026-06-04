import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var languageRestartNoticeVisible = false

    private static let refreshOptions = [1, 2, 5, 10, 15, 30, 60]

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(title: "Startup") {
                VStack(spacing: 0) {
                    SettingRow(title: "Launch at login",
                               description: "Open Claude Stats automatically when you log in to your Mac.") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.appSwitch)
                    }
                    .onChange(of: launchAtLogin) { _, newValue in LaunchAtLogin.setEnabled(newValue) }
                    SettingRowDivider()
                    SettingRow(title: "Open main window on launch",
                               description: "Show the main window when Claude Stats starts, including when you double-click the app.") {
                        Toggle("", isOn: $prefs.openMainWindowOnLaunch)
                            .labelsHidden()
                            .toggleStyle(.appSwitch)
                    }
                }
                .settingCard()
            }

            SettingGroup(title: "Language") {
                VStack(spacing: 0) {
                    SettingRow(title: "App language",
                               description: "Choose the language Claude Stats uses after the next restart.") {
                        AppSelect(
                            .localized("App language"),
                            selection: $prefs.appLanguagePreference,
                            options: AppLanguagePreference.allCases.map { language in
                                AppSelectOption(value: language, title: .verbatim(language.displayName()))
                            },
                            width: 170
                        )
                    }
                    .onChange(of: prefs.appLanguagePreference) { _, _ in
                        languageRestartNoticeVisible = true
                    }
                    if languageRestartNoticeVisible {
                        SettingRowDivider()
                        Text(L10n.restartLanguageNotice())
                            .font(.sora(11))
                            .foregroundStyle(Color.stxAccent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                }
                .settingCard()
            }

            SettingGroup(title: "Refresh") {
                VStack(spacing: 0) {
                    SettingRow(title: "Refresh every",
                               description: "How often Claude Stats re-scans your session logs in the background.") {
                        AppSelect(
                            .localized("Refresh every"),
                            selection: $prefs.autoRefreshMinutes,
                            options: Self.refreshOptions.map { minutes in
                                AppSelectOption(value: minutes, title: .verbatim(L10n.refreshInterval(minutes: minutes)))
                            },
                            width: 160
                        )
                    }
                    .onChange(of: prefs.autoRefreshMinutes) { _, _ in env.applyAutoRefreshSetting() }
                }
                .settingCard()
            }

            SettingGroup(title: "Behavior") {
                VStack(spacing: 0) {
                    SettingRow(title: "Remember selected platform",
                               description: "When off, the app starts on the first enabled platform each launch instead of the one you last viewed.") {
                        Toggle("", isOn: $prefs.rememberSelectedProvider)
                            .labelsHidden()
                            .toggleStyle(.appSwitch)
                    }
                    SettingRowDivider()
                    SettingRow(title: "Detail edge fade",
                               description: "Blend the main detail pane into the sidebar with a soft boundary fade.") {
                        Toggle("", isOn: $prefs.detailPanelBoundaryFalloffEnabled)
                            .labelsHidden()
                            .toggleStyle(.appSwitch)
                    }
                    SettingRowDivider()
                    SettingRow(title: "Include cache reads in token counts",
                               description: "Anthropic's API re-reports the cached context on every assistant turn, so the same tokens get counted many times. Turn off to show only \u{201C}new\u{201D} traffic (input + output + cache writes). Estimated cost is unaffected.") {
                        Toggle("", isOn: $prefs.includeCacheInTokens)
                            .labelsHidden()
                            .toggleStyle(.appSwitch)
                    }
                    SettingRowDivider()
                    SettingRow(title: "Cost mode",
                               description: "API estimate uses standard first-party token prices. Detailed billing also applies fast mode and web search charges when Claude logs expose them.") {
                        AppSelect(
                            .localized("Cost mode"),
                            selection: $prefs.costEstimationMode,
                            options: CostEstimationMode.allCases.map { mode in
                                AppSelectOption(value: mode, title: .localized(mode.displayName))
                            },
                            width: 170
                        )
                    }
                    SettingRowDivider()
                    SettingRow(title: "API key storage",
                               description: "Where API Provider Switcher saves provider keys. JSON keeps them with provider data; Keychain stores references in the library.") {
                        AppSelect(
                            .localized("API key storage"),
                            selection: $prefs.apiProviderKeyStorageMode,
                            options: APIProviderKeyStorageMode.allCases.map { mode in
                                AppSelectOption(value: mode, title: .localized(mode.displayName))
                            },
                            width: 150
                        )
                    }
                }
                .settingCard()
            }
        }
    }
}

#if DEBUG
#Preview {
    GeneralSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
