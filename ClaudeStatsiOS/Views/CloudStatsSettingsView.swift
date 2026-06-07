import ClaudeStatsCore
import ClaudeStatsSync
import SwiftUI

struct CloudStatsSettingsView: View {
    let store: CloudStatsSnapshotStore
    let statusSummary: StatsStatusSummary
    let statusPreferences: StatsStatusDisplayPreferencesStore
    let loadSampleData: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    init(
        store: CloudStatsSnapshotStore,
        statusSummary: StatsStatusSummary,
        statusPreferences: StatsStatusDisplayPreferencesStore,
        loadSampleData: (() -> Void)? = nil
    ) {
        self.store = store
        self.statusSummary = statusSummary
        self.statusPreferences = statusPreferences
        self.loadSampleData = loadSampleData
    }

    var body: some View {
        NavigationStack {
            List {
                iCloudSyncSection
                statusSection

                #if CLAUDE_STATS_DEV_TOOLS
                Section("Developer") {
                    Button {
                        loadSampleData?()
                    } label: {
                        Label("Use Sample Data", systemImage: "wand.and.sparkles")
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var iCloudSyncSection: some View {
        Section {
            NavigationLink {
                CloudStatsICloudSyncSettingsView(store: store)
            } label: {
                CloudStatsICloudSyncSettingsLabel(store: store)
            }
        }
    }

    private var statusSection: some View {
        Section("Status") {
            Picker(
                "Dashboard Status",
                selection: Binding(
                    get: { statusPreferences.selectedProviderID },
                    set: { statusPreferences.selectedProviderID = $0 }
                )
            ) {
                ForEach(StatsStatusProviderID.allCases) { providerID in
                    Text(providerID.displayName).tag(providerID)
                }
            }
            .pickerStyle(.segmented)

            if let provider = statusSummary.provider(statusPreferences.selectedProviderID) {
                if provider.items.isEmpty {
                    Text("Status items will appear after the next Mac sync.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(provider.items) { item in
                        Toggle(
                            isOn: Binding(
                                get: { statusPreferences.isItemVisible(item, in: provider) },
                                set: { statusPreferences.setItemVisibility(item, in: provider, isVisible: $0) }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                Text(item.status.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(
                            statusPreferences.isItemVisible(item, in: provider)
                                && !statusPreferences.canHideItem(item, in: provider)
                        )
                    }
                }
            } else {
                Text("\(statusPreferences.selectedProviderID.statusTitle) will appear after the next Mac sync.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CloudStatsICloudSyncSettingsLabel: View {
    let store: CloudStatsSnapshotStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 26)
            Text("iCloud Sync")
        }
    }

    private var symbol: String {
        switch store.state {
        case .loaded:
            store.usesSampleData ? "wand.and.sparkles" : "icloud"
        case .failed:
            "exclamationmark.icloud"
        case .empty:
            "icloud.slash"
        case .idle, .loading:
            "clock"
        }
    }

    private var color: Color {
        switch store.state {
        case .loaded:
            .teal
        case .failed:
            .red
        case .empty:
            .orange
        case .idle, .loading:
            .secondary
        }
    }
}

private struct CloudStatsICloudSyncSettingsView: View {
    let store: CloudStatsSnapshotStore

    var body: some View {
        List {
            Section {
                CloudStatsSyncInfoRow(
                    title: "Status",
                    value: statusText,
                    valueColor: statusColor
                )
                CloudStatsSyncInfoRow(
                    title: "iCloud Account",
                    value: store.accountStatus.displayText,
                    valueColor: accountColor
                )
                CloudStatsSyncInfoRow(
                    title: "Last Updated",
                    value: relativeText(store.snapshot?.generatedAt),
                    valueColor: .secondary
                )
                CloudStatsSyncInfoRow(
                    title: "Last Checked",
                    value: relativeText(store.lastCheckedAt),
                    valueColor: .secondary
                )
            }

            Section {
                Button {
                    Task { await store.load() }
                } label: {
                    HStack {
                        Text("Check iCloud Sync")
                        Spacer()
                        if store.state == .loading {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.state == .loading)
            }

            if let error = store.lastError, !error.isEmpty {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusText: String {
        if store.usesSampleData {
            return "Sample Data"
        }
        switch store.state {
        case .idle:
            return "Not Checked"
        case .loading:
            return "Checking"
        case .loaded:
            return "Synced"
        case .empty:
            return "No Snapshot"
        case .failed:
            return "Failed"
        }
    }

    private var statusColor: Color {
        switch store.state {
        case .loaded:
            .teal
        case .failed:
            .red
        case .empty:
            .orange
        case .idle, .loading:
            .secondary
        }
    }

    private var accountColor: Color {
        switch store.accountStatus {
        case .available:
            .teal
        case .unknown:
            .secondary
        case .noAccount, .restricted, .unavailable:
            .orange
        }
    }

    private func relativeText(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

private struct CloudStatsSyncInfoRow: View {
    let title: String
    let value: String
    let valueColor: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
            Spacer(minLength: 10)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 2)
    }
}
