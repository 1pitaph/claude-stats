import SwiftUI

struct CloudStatsSettingsView: View {
    let loadSampleData: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    init(loadSampleData: (() -> Void)? = nil) {
        self.loadSampleData = loadSampleData
    }

    var body: some View {
        NavigationStack {
            List {
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
}
