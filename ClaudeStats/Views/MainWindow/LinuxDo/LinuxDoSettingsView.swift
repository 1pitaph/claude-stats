import AppKit
import SwiftUI

struct LinuxDoSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var store: LinuxDoStore
    @State private var webLoginPresented = false

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(
                title: "Connection",
                caption: "LinuxDo signs in with a browser session, matching the website experience."
            ) {
                VStack(spacing: 0) {
                    SettingRow(title: "Account", description: accountDescription) {
                        if store.isSigningIn {
                            ProgressView()
                                .controlSize(.small)
                        } else if store.isAuthenticated {
                            Button("Sign Out") {
                                Task { await store.signOut() }
                            }
                            .controlSize(.small)
                        } else {
                            Button("Sign In") {
                                webLoginPresented = true
                            }
                            .controlSize(.small)
                        }
                    }
                    SettingRow(title: "Open Linux.do", description: "Open the community in your default browser.") {
                        Button("Open") {
                            NSWorkspace.shared.open(URL(string: "https://linux.do")!)
                        }
                        .controlSize(.small)
                    }
                }
                .settingCard()
            }

            SettingGroup(
                title: "Notifications",
                caption: "Claude Stats polls Linux.do every two minutes and sends local macOS notifications for new unread items."
            ) {
                VStack(spacing: 0) {
                    SettingRow(title: "Local notifications", description: notificationDescription) {
                        Toggle("", isOn: notificationBinding(prefs: prefs))
                            .labelsHidden()
                            .disabled(!store.isAuthenticated)
                    }
                    SettingRow(title: "Refresh now", description: "Fetch the latest LinuxDo notifications without changing read state.") {
                        Button {
                            Task { await store.refreshNotifications(announce: false) }
                        } label: {
                            if store.isRefreshingNotifications {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Refresh")
                            }
                        }
                        .controlSize(.small)
                        .disabled(!store.isAuthenticated || store.isRefreshingNotifications)
                    }
                }
                .settingCard()
            }

            SettingGroup(title: "Storage") {
                VStack(spacing: 0) {
                    SettingRow(title: "Cached topics", description: "Remove cached LinuxDo feeds, categories, and topic detail snapshots.") {
                        Button("Clear Cache") {
                            store.clearCache()
                        }
                        .controlSize(.small)
                    }
                }
                .settingCard()
            }

            if let error = store.lastError {
                LinuxDoInlineError(message: error)
            }
        }
        .sheet(isPresented: $webLoginPresented) {
            LinuxDoWebLoginSheet(store: store, isPresented: $webLoginPresented)
        }
    }

    private var accountDescription: String {
        if let user = store.currentUser {
            return "Signed in as @\(user.username)."
        }
        if !env.preferences.linuxDoLastLoginUsername.isEmpty {
            return "Last signed in as @\(env.preferences.linuxDoLastLoginUsername) using \(store.authenticationDescription.lowercased())."
        }
        return store.isAuthenticated ? "Signed in using \(store.authenticationDescription.lowercased()). User details will load when Linux.do is reachable." : "Guest browsing. Sign in to enable notifications."
    }

    private var notificationDescription: String {
        switch store.notificationAuthorization {
        case .denied:
            return "Notifications are denied in macOS Settings."
        case .authorized, .provisional, .ephemeral:
            return "New unread Linux.do notifications appear as local macOS alerts."
        case .notDetermined:
            return "macOS will ask for permission when you enable this."
        case .unknown:
            return "Notification permission status is unknown."
        }
    }

    private func notificationBinding(prefs: Preferences) -> Binding<Bool> {
        Binding(
            get: { prefs.linuxDoNotificationsEnabled },
            set: { enabled in
                Task { await store.setNotificationsEnabled(enabled) }
            }
        )
    }
}

#if DEBUG
#Preview("LinuxDo settings") {
    LinuxDoSettingsView(store: AppEnvironment.preview().linuxDo)
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 760)
}
#endif
