import SwiftUI

struct GitHubConnectionSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tokenDraft: String = ""
    @State private var githubError: String?

    var body: some View {
        VStack(spacing: 0) {
            statusRow
            SettingRowDivider()
            connectionControls
        }
    }

    private var statusRow: some View {
        SettingRow(title: "Status") {
            Group {
                switch env.github.status {
                case .disconnected:
                    Text("Not connected")
                        .foregroundStyle(Color.stxMuted)
                case .connecting:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Connecting...")
                            .foregroundStyle(Color.stxMuted)
                    }
                case .connected(let login, let syncedAt, let isStale):
                    HStack(spacing: 6) {
                        Text("@\(login)")
                        if let syncedAt {
                            Text("UPD \(Format.relativeDate(syncedAt))")
                                .foregroundStyle(Color.stxMuted)
                        }
                        if isStale {
                            Text("(stale)")
                                .foregroundStyle(Color.stxAccent)
                        }
                    }
                case .failed(let reason):
                    Text(reason)
                        .foregroundStyle(Color.stxAccent)
                        .lineLimit(2)
                }
            }
            .font(.sora(12))
        }
    }

    @ViewBuilder
    private var connectionControls: some View {
        switch env.github.status {
        case .disconnected, .failed:
            tokenInput
        case .connecting:
            HStack {
                ProgressView().controlSize(.mini)
                Text("Connecting...")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        case .connected:
            HStack(spacing: 8) {
                Button("Sync now") {
                    Task { await env.github.syncNow() }
                }
                Button("Disconnect", role: .destructive) {
                    env.github.disconnect(login: env.preferences.githubLogin)
                    env.preferences.githubLogin = ""
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var tokenInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SecureField("Personal access token", text: $tokenDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { saveGitHubToken() }
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let githubError {
                Text(githubError)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Link(
                "Create a fine-grained token (no scopes needed)...",
                destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!
            )
            .font(.sora(11))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func saveGitHubToken() {
        let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        githubError = nil
        Task {
            do {
                let login = try await env.github.connect(token: token)
                env.preferences.githubLogin = login
                tokenDraft = ""
            } catch let err as GitHubClient.ClientError {
                githubError = String(describing: err)
            } catch {
                githubError = error.localizedDescription
            }
        }
    }
}

struct LeaderboardProfileSettings: View {
    @Environment(AppEnvironment.self) private var env

    private var canSync: Bool {
        env.preferences.leaderboardsEnabled
            && !env.preferences.leaderboardNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && env.leaderboards.syncStatus != .syncing
            && env.leaderboards.syncStatus != .checkingAccount
            && !env.leaderboards.isSavingProfile
    }

    private var canRandomizeAvatar: Bool {
        env.preferences.leaderboardsEnabled
            && env.leaderboards.syncStatus != .syncing
            && env.leaderboards.syncStatus != .checkingAccount
            && !env.leaderboards.isSavingProfile
    }

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(spacing: 0) {
            nicknameRow(prefs: prefs)
            SettingRowDivider()
            avatarRow
            SettingRowDivider()
            statusRow
            SettingRowDivider()
            syncRow
        }
    }

    private func nicknameRow(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return SettingRow(
            title: "Public nickname",
            description: "Shown on the leaderboard instead of your iCloud identity."
        ) {
            TextField("Nickname", text: $prefs.leaderboardNickname)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { Task { await env.leaderboards.syncNow() } }
        }
    }

    private var avatarRow: some View {
        SettingRow(
            title: "Public avatar",
            description: "A generated Beam avatar linked to your iCloud leaderboard profile."
        ) {
            HStack(spacing: 10) {
                BeamAvatarView(seed: env.leaderboards.avatarSeed, size: 46, isDecorative: false)
                Button {
                    Task { await env.leaderboards.randomizeAvatar() }
                } label: {
                    Image(systemName: AppIcon.Action.sync)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxAccent)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
                .help("Randomize avatar")
                .disabled(!canRandomizeAvatar)

                if env.leaderboards.isSavingProfile {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
        }
    }

    private var statusRow: some View {
        SettingRow(title: "Status") {
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    if env.leaderboards.syncStatus == .checkingAccount || env.leaderboards.syncStatus == .syncing {
                        ProgressView().controlSize(.mini)
                    }
                    Text(env.leaderboards.syncStatus.displayText)
                        .font(.sora(12))
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                }
                Text(env.leaderboards.accountState.displayText)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
        }
    }

    private var syncRow: some View {
        SettingRow(
            title: "Sync",
            description: "Runs in the background while the app is open. You can force a sync here."
        ) {
            HStack(spacing: 8) {
                if let last = env.preferences.leaderboardLastSyncedAt {
                    Text(Format.shortDate(last))
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
                Button("Sync now") {
                    Task { await env.leaderboards.syncNow() }
                }
                .disabled(!canSync)
            }
        }
    }

    private var statusColor: Color {
        switch env.leaderboards.syncStatus {
        case .failed, .needsNickname:
            return .stxAccent
        default:
            return .stxMuted
        }
    }
}
