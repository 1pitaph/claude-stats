import SwiftUI

struct LeaderboardsSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    var onSelectSection: (SettingsSection) -> Void = { _ in }

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            if !prefs.leaderboardsEnabled {
                FeatureDisabledNotice(
                    featureName: "CloudKit Leaderboards",
                    message: "Turn them on in Features to edit your public profile and sync aggregate scores."
                ) {
                    onSelectSection(.features)
                }
            }

            VStack(alignment: .leading, spacing: 28) {
                SettingGroup(
                    title: "CloudKit Leaderboards",
                    caption: "Publishes aggregate scores and public profile metadata to CloudKit's public database. The app never uploads prompts, paths, session titles, costs, or transcript content."
                ) {
                    LeaderboardProfileSettings()
                        .settingCard()
                }
                activityNote
                privacyGroup
            }
            .disabledSettingsBlock(!prefs.leaderboardsEnabled)
        }
        .task { await env.leaderboards.checkAccountStatus() }
        .onChange(of: prefs.leaderboardsEnabled) { _, enabled in
            if enabled {
                Task { await env.leaderboards.syncIfDue(force: false) }
            }
        }
    }

    private var activityNote: some View {
        let canSubmitActivity = env.preferences.aiActivityAnalysisEnabled && ScreenTimeService.canRead()
        return SettingGroup(title: "Activity Score") {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: canSubmitActivity ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(canSubmitActivity ? Color.stxMuted : Color.stxAccent)
                Text(canSubmitActivity
                     ? "Activity minutes will be included in leaderboard syncs."
                     : "Activity minutes are skipped until AI Activity Analysis is enabled and Full Disk Access is granted.")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
            .settingCard()
        }
    }

    private var privacyGroup: some View {
        SettingGroup(title: "Privacy") {
            VStack(alignment: .leading, spacing: 8) {
                privacyLine("Uploaded: nickname, public status, metric, UTC period, aggregate score, app version, update time.")
                privacyLine("Uploaded avatar data is only a random seed and the Beam variant name, never a photo or iCloud identity.")
                privacyLine("Favorite model metadata may be shown on public profiles when available.")
                privacyLine("Never uploaded: prompts, transcript text, project paths, filenames, costs, or session titles.")
                privacyLine("Leaderboard periods use UTC so everyone competes in the same day/week/month window.")
            }
            .settingCard()
        }
    }

    private func privacyLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(Color.stxAccent)
            Text(text)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview {
    LeaderboardsSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
