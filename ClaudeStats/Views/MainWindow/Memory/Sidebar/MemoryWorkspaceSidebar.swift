import AppKit
import SwiftUI

struct MemoryWorkspaceSidebar: View {
    @Bindable var store: MemoryStore
    var onExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)

            SidebarRow(
                title: "Back to App",
                symbol: "chevron.left",
                isSelected: false,
                action: close
            )

            statusCard
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 10)

            ForEach(MemoryWorkspaceSection.allCases) { section in
                MemorySidebarRow(
                    title: title(for: section),
                    symbol: symbol(for: section),
                    count: count(for: section),
                    isSelected: store.section == section
                ) {
                    clearFocus()
                    store.select(section)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { clearFocus() }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("MEMORY")
                    .font(.sora(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                if store.isCodeMemoryLoading || store.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            HStack(spacing: 10) {
                AIConfigsMiniStat(value: "\(store.codeHealth?.memoryCount ?? 0)", label: "active")
                Spacer(minLength: 0)
                Button {
                    Task { await store.refreshCodeMemoryStatus() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(store.isCodeMemoryLoading)
                .help("Refresh Code Memory")
            }

            HStack(spacing: 8) {
                Image(systemName: store.lastError == nil ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.lastError == nil ? Color.stxAccent : Color(red: 0.92, green: 0.58, blue: 0.16))
                Text(store.lastError ?? (store.codeHealth == nil ? "sidecar offline" : "sidecar ready"))
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1))
    }

    private func title(for section: MemoryWorkspaceSection) -> String {
        switch section {
        case .search: "Search"
        case .memories: "Memories"
        case .graph: "Graph"
        case .review: "Review"
        case .settings: "Settings"
        }
    }

    private func symbol(for section: MemoryWorkspaceSection) -> String {
        switch section {
        case .search: "magnifyingglass"
        case .memories: "folder"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .review: "checklist"
        case .settings: "gearshape"
        }
    }

    private func count(for section: MemoryWorkspaceSection) -> Int? {
        switch section {
        case .search:
            let total = store.codeSearchResults.count + store.codeGraphResults.count + store.codeSourceResults.count
            return total > 0 ? total : nil
        case .memories:
            return store.codeHealth?.memoryCount
        case .graph:
            let count = store.graph.filteredChangeEvents.count
            return count > 0 ? count : nil
        case .review:
            return store.review.totalCount
        case .settings:
            return nil
        }
    }

    private func close() {
        clearFocus()
        onExit()
    }

    private func clearFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

private struct MemorySidebarRow: View {
    let title: String
    let symbol: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                Text(title)
                    .font(.sora(13))
                    .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let count {
                    Text("\(count)")
                        .font(.sora(9).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.10))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}
