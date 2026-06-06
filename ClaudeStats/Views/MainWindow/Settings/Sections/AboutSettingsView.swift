import SwiftUI
import AppKit

struct AboutSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var automaticallyDownloadsUpdates = false
    @State private var automaticallyChecksForUpdates = false
    @State private var allowsAutomaticUpdates = false

    var onShowReleaseHistory: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(title: "Data") {
                VStack(spacing: 0) {
                    SettingRow(title: "Claude config directory",
                               description: ClaudePaths.default.configDirectory.path) {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([ClaudePaths.default.configDirectory])
                        }
                    }
                }
                .settingCard()
            }

            SettingGroup(title: "About") {
                VStack(spacing: 0) {
                    SettingRow(title: "Version",
                               description: appVersionString) {
                        Button("Check for Updates…") { env.updater.checkForUpdates() }
                    }
                    SettingRowDivider()
                    SettingRow(title: "Automatically download updates",
                               description: automaticDownloadDescription) {
                        Toggle("", isOn: automaticDownloadBinding)
                            .toggleStyle(.appSwitch)
                            .disabled(!canToggleAutomaticDownloads)
                    }
                    SettingRowDivider()
                    SettingRow(title: "Release History",
                               description: "See what changed since 1.4.0") {
                        Button("View…", action: onShowReleaseHistory)
                    }
                    SettingRowDivider()
                    SettingRow(title: counterpartVersionTitle,
                               description: counterpartVersionDescription) {
                        Button(counterpartVersionButtonTitle, action: openCounterpartDownloadPage)
                            .help(counterpartVersionHelp)
                    }
                }
                .settingCard()
            }
        }
        .onAppear(perform: syncUpdateSettings)
        .onReceive(NotificationCenter.default.publisher(for: UpdaterController.updateSettingsDidChange)) { _ in
            syncUpdateSettings()
        }
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private var counterpartVersionTitle: String {
        AppVariant.isLite ? "Full version" : "Lite version"
    }

    private var counterpartVersionDescription: String {
        if AppVariant.isLite {
            "Download Claude Stats with Dictionary, Linux.do, Warp, Config, Ops, Network, Local AI, and Notch Island."
        } else {
            "Download Claude Stats Lite with the core stats, Git, and daily reports."
        }
    }

    private var counterpartVersionButtonTitle: String {
        AppVariant.isLite ? "Download Full…" : "Download Lite…"
    }

    private var counterpartVersionHelp: String {
        AppVariant.isLite
            ? "Open the latest GitHub release to download Claude Stats."
            : "Open the latest GitHub release to download Claude Stats Lite."
    }

    private var canToggleAutomaticDownloads: Bool {
        automaticallyChecksForUpdates && allowsAutomaticUpdates
    }

    private var automaticDownloadDescription: String {
        if !automaticallyChecksForUpdates {
            return "Automatic update checks are off, so background downloads are unavailable."
        }
        if !allowsAutomaticUpdates {
            return "This build does not allow automatic background downloads."
        }
        return "Download updates in the background and install them later from the sidebar update pill."
    }

    private var automaticDownloadBinding: Binding<Bool> {
        Binding(
            get: { automaticallyDownloadsUpdates },
            set: { newValue in
                automaticallyDownloadsUpdates = newValue
                env.updater.setAutomaticallyDownloadsUpdates(newValue)
                syncUpdateSettings()
            }
        )
    }

    private func syncUpdateSettings() {
        automaticallyDownloadsUpdates = env.updater.automaticallyDownloadsUpdates
        automaticallyChecksForUpdates = env.updater.automaticallyChecksForUpdates
        allowsAutomaticUpdates = env.updater.allowsAutomaticUpdates
    }

    private func openCounterpartDownloadPage() {
        NSWorkspace.shared.open(Self.releasesURL)
    }

    private static let releasesURL = URL(string: "https://github.com/1pitaph/claude-stats/releases/latest")!
}

#if DEBUG
#Preview {
    AboutSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
