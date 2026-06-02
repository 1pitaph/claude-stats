import SwiftUI
import AppKit

struct AboutSettingsView: View {
    @Environment(AppEnvironment.self) private var env
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
            "Download Claude Stats with Linux.do, Warp, Config, Ops, Network, and Notch Island."
        } else {
            "Download Claude Stats Lite with the core stats, Git, daily reports, and local AI."
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
