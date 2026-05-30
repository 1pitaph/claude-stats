import SwiftUI

struct MemoryGraphMemoryHistorySection: View {
    @Bindable var graphStore: MemoryGraphStore
    let memoryID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("History")
                    .font(.sora(12, weight: .semibold))
                Spacer(minLength: 0)
                Button {
                    Task { await graphStore.refreshHistory(memoryID: memoryID) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Reload history")
                .disabled(graphStore.loadingHistoryMemoryIDs.contains(memoryID))
            }

            if graphStore.loadingHistoryMemoryIDs.contains(memoryID) {
                ProgressView()
                    .controlSize(.small)
            } else if let history = graphStore.history(for: memoryID) {
                if history.versions.isEmpty {
                    Text("No versions recorded.")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(history.versions.prefix(8))) { version in
                            MemoryGraphVersionRow(version: version)
                        }
                    }
                }
            } else if let error = graphStore.historyLastError {
                Text(error)
                    .font(.sora(11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    Task { await graphStore.loadHistory(memoryID: memoryID) }
                } label: {
                    Label("Load History", systemImage: "clock.arrow.circlepath")
                }
                .controlSize(.small)
            }
        }
        .task(id: memoryID) {
            await graphStore.loadHistory(memoryID: memoryID)
        }
    }
}

private struct MemoryGraphVersionRow: View {
    let version: CodeMemoryMemoryVersion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("v\(version.version)")
                    .font(.sora(10, weight: .semibold).monospaced())
                Text(version.eventType)
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.stxAccent)
                Spacer(minLength: 0)
                Text(version.status)
                    .font(.sora(9, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
            }
            Text(version.title)
                .font(.sora(11, weight: .semibold))
                .lineLimit(2)
            Text(MemoryFormat.timestamp(version.timestamp))
                .font(.sora(9).monospaced())
                .foregroundStyle(Color.stxMuted)
            if !version.body.isEmpty {
                Text(version.body)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(3)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct MemoryGraphInspectorFactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.sora(10).monospaced())
                .foregroundStyle(Color.stxMuted)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.sora(10).monospaced())
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}
