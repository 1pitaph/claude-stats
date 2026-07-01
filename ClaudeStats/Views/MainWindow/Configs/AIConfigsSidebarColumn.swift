import AppKit
import SwiftUI

struct AIConfigsSidebarColumn: View {
    @Binding var section: AIConfigsSection
    @Binding var searchText: String
    var onExit: () -> Void

    @Environment(AppEnvironment.self) private var env
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)

            SidebarRow(
                title: "Back to App",
                symbol: AppIcon.Navigation.back,
                isSelected: false,
                action: close
            )

            statusCard
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 10)

            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            ForEach(AIConfigsSection.allCases) { item in
                AIConfigsSidebarSectionRow(
                    section: item,
                    count: env.aiConfigs.count(for: item, query: searchText),
                    isSelected: section == item
                ) {
                    clearSearchFocus()
                    section = item
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { clearSearchFocus() }
        }
        .task {
            await env.aiConfigs.loadIfNeeded(sessions: env.store.sessions)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("CONFIGS")
                    .font(.sora(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                if env.aiConfigs.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            HStack(spacing: 10) {
                WorkspaceMiniStat(value: "\(env.aiConfigs.snapshot.summary.existingDocumentCount)", label: "files")
                WorkspaceMiniStat(value: "\(env.aiConfigs.snapshot.summary.diagnosticCount)", label: "issues")
                Spacer(minLength: 0)
                Button {
                    refresh()
                } label: {
                    Image(systemName: AppIcon.Action.refresh)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(env.aiConfigs.isLoading)
                .help("Refresh configs")
            }

            if let scannedAt = env.aiConfigs.snapshot.scannedAt {
                Text("Updated \(Format.relativeDate(scannedAt))")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: AppIcon.Action.search)
                .font(.system(size: 11))
                .foregroundStyle(Color.stxMuted)
                .accessibilityHidden(true)
            TextField("Search configs", text: $searchText)
                .textFieldStyle(.plain)
                .font(.sora(11))
                .focused($searchFieldFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: AppIcon.Action.clear)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private func refresh() {
        Task {
            await env.aiConfigs.reload(sessions: env.store.sessions)
        }
    }

    private func close() {
        clearSearchFocus()
        onExit()
    }

    private func clearSearchFocus() {
        searchFieldFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

private struct AIConfigsSidebarSectionRow: View {
    let section: AIConfigsSection
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                Text(section.title)
                    .font(.sora(13))
                    .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(count)")
                    .font(.sora(9).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
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
