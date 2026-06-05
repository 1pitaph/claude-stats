import ClaudeStatsCore
import SwiftUI

struct CloudStatsSettingsView: View {
    let statusSummary: StatsStatusSummary
    let statusPreferences: StatsStatusDisplayPreferencesStore
    let loadSampleData: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    init(
        statusSummary: StatsStatusSummary,
        statusPreferences: StatsStatusDisplayPreferencesStore,
        loadSampleData: (() -> Void)? = nil
    ) {
        self.statusSummary = statusSummary
        self.statusPreferences = statusPreferences
        self.loadSampleData = loadSampleData
    }

    var body: some View {
        NavigationStack {
            List {
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
