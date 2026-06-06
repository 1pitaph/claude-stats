import ClaudeStatsCore
import ClaudeStatsSync
import SwiftUI

struct CloudStatsSyncSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(
                title: "Stats Snapshot",
                caption: "Publishes the current aggregated usage snapshot to CloudKit's private database so the iOS app can read it."
            ) {
                VStack(spacing: 0) {
                    statusRow
                    SettingRowDivider()
                    accountRow
                    SettingRowDivider()
                    lastPublishedRow
                    SettingRowDivider()
                    recordRow
                    SettingRowDivider()
                    actionRow
                    if let error = env.cloudStatsSyncState.lastError, !error.isEmpty {
                        SettingRowDivider()
                        errorRow(error)
                    }
                }
                .settingCard()
            }

            SettingGroup(title: "Privacy") {
                VStack(alignment: .leading, spacing: 8) {
                    privacyLine("Uploaded: aggregate tokens, costs, sessions, daily summaries, usage-limit snapshots, activity intervals, and dashboard totals.")
                    privacyLine("Project paths are anonymized to labels like Project 1 before upload.")
                    privacyLine("Not uploaded: prompts, transcript text, filenames, raw project paths, or full session logs.")
                }
            }
        }
        .task {
            await env.refreshCloudStatsSnapshotSyncStatus()
        }
    }

    private var statusRow: some View {
        SettingRow(title: "Status", description: statusDescription) {
            HStack(spacing: 8) {
                if env.cloudStatsSyncState.isBusy {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: statusSymbol)
                        .foregroundStyle(statusColor)
                }
                Text(verbatim: env.cloudStatsSyncState.phase.displayText)
                    .font(.sora(12, weight: .medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
            }
        }
    }

    private var accountRow: some View {
        SettingRow(
            title: "iCloud account",
            description: "The private snapshot is available only to devices signed in to the same iCloud account."
        ) {
            Text(verbatim: env.cloudStatsSyncState.accountStatus.displayText)
                .font(.sora(12))
                .foregroundStyle(accountColor)
                .lineLimit(2)
        }
    }

    private var lastPublishedRow: some View {
        SettingRow(
            title: "Last published",
            description: lastGeneratedDescription
        ) {
            Text(verbatim: dateText(env.cloudStatsSyncState.lastPublishedAt))
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
        }
    }

    private var recordRow: some View {
        SettingRow(
            title: "CloudKit record",
            description: "Container \(CloudStatsCloudKitClient.defaultContainerIdentifier)"
        ) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(verbatim: CloudStatsCloudKitClient.recordType)
                    .font(.sora(12, weight: .medium))
                    .foregroundStyle(.primary)
                Text(verbatim: "\(CloudStatsCloudKitClient.latestRecordName) / schema v\(StatsSnapshotSchema.currentVersion)")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
        }
    }

    private var actionRow: some View {
        SettingRow(
            title: "Actions",
            description: "Check iCloud status or publish the latest in-memory snapshot now."
        ) {
            HStack(spacing: 8) {
                Button {
                    Task { await env.refreshCloudStatsSnapshotSyncStatus() }
                } label: {
                    Label("Check", systemImage: AppIcon.Action.refresh)
                }
                .disabled(env.cloudStatsSyncState.isBusy)

                Button {
                    Task { await env.publishCloudStatsSnapshotNow() }
                } label: {
                    Label("Publish Now", systemImage: AppIcon.Action.sync)
                }
                .disabled(!env.cloudStatsSyncState.canPublish)
            }
        }
    }

    private func errorRow(_ error: String) -> some View {
        SettingRow(title: "Last error") {
            Text(verbatim: error)
                .font(.sora(12))
                .foregroundStyle(Color.stxAccent)
                .lineLimit(3)
        }
    }

    private var statusDescription: String {
        switch env.cloudStatsSyncState.phase {
        case .notChecked:
            "Open this page or press Check to inspect the CloudKit runtime state."
        case .missingEntitlement:
            "This build is not signed with the CloudKit entitlement. Use DebugCloudKit or a signed release build to publish."
        case .checkingAccount:
            "Checking whether the current iCloud account can access the private database."
        case .ready:
            "This Mac can publish the private stats snapshot."
        case .publishing:
            "Encoding the current StatsSnapshot and saving it to CloudKit."
        case .published:
            "The latest snapshot was saved to CloudKit. iOS will load it from the private database."
        case .unavailable:
            env.cloudStatsSyncState.accountStatus.displayText
        case .failed:
            env.cloudStatsSyncState.lastError ?? "The last publish attempt failed."
        }
    }

    private var lastGeneratedDescription: String {
        guard let generatedAt = env.cloudStatsSyncState.lastSnapshotGeneratedAt else {
            return "The iOS app reads the most recent successful publish."
        }
        return "Snapshot generated \(Format.shortDate(generatedAt))."
    }

    private var statusSymbol: String {
        switch env.cloudStatsSyncState.phase {
        case .ready, .published:
            AppIcon.Status.success
        case .missingEntitlement, .unavailable:
            AppIcon.Status.warning
        case .failed:
            AppIcon.Status.error
        case .notChecked, .checkingAccount, .publishing:
            AppIcon.Settings.iCloudSync
        }
    }

    private var statusColor: Color {
        switch env.cloudStatsSyncState.phase {
        case .ready, .published:
            Color.stxAccent
        case .missingEntitlement, .unavailable, .failed:
            Color.stxAccent
        case .notChecked, .checkingAccount, .publishing:
            Color.stxMuted
        }
    }

    private var accountColor: Color {
        switch env.cloudStatsSyncState.accountStatus {
        case .available:
            Color.stxAccent
        case .unknown:
            Color.stxMuted
        case .noAccount, .restricted, .unavailable:
            Color.stxAccent
        }
    }

    private func privacyLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(Color.stxAccent)
            Text(verbatim: text)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return Format.shortDate(date)
    }
}

#if DEBUG
#Preview {
    CloudStatsSyncSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
