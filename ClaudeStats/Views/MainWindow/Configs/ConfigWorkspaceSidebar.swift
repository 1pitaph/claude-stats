import AppKit
import SwiftUI

struct ConfigWorkspaceSidebar: View {
    @Bindable var store: ConfigWorkspaceStore
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

            if store.showsSearch {
                searchField
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            ConfigWorkspaceSidebarRow(
                title: ConfigWorkspaceSection.overview.title,
                symbol: ConfigWorkspaceSection.overview.symbol,
                count: nil,
                indent: 0,
                isSelected: store.section == .overview
            ) {
                clearSearchFocus()
                store.select(.overview)
            }

            ConfigWorkspaceSidebarRow(
                title: ConfigWorkspaceSection.files.title,
                symbol: ConfigWorkspaceSection.files.symbol,
                count: store.counts.configFileCount,
                indent: 0,
                isSelected: store.section == .files
            ) {
                clearSearchFocus()
                store.select(.files)
            }

            sectionHeader("FILES")
            ForEach(ConfigFilesSection.allCases) { item in
                ConfigWorkspaceSidebarRow(
                    title: item.title,
                    symbol: item.symbol,
                    count: store.fileCount(for: item),
                    indent: 12,
                    isSelected: store.section == .files && store.filesSection == item
                ) {
                    clearSearchFocus()
                    store.selectFileSection(item)
                }
            }

            ConfigWorkspaceSidebarRow(
                title: ConfigWorkspaceSection.providers.title,
                symbol: ConfigWorkspaceSection.providers.symbol,
                count: store.counts.providerCount,
                indent: 0,
                isSelected: store.section == .providers
            ) {
                clearSearchFocus()
                store.select(.providers)
            }

            ConfigWorkspaceSidebarRow(
                title: ConfigWorkspaceSection.profiles.title,
                symbol: ConfigWorkspaceSection.profiles.symbol,
                count: store.counts.profileCount,
                indent: 0,
                isSelected: store.section == .profiles
            ) {
                clearSearchFocus()
                store.select(.profiles)
            }

            ConfigWorkspaceSidebarRow(
                title: ConfigWorkspaceSection.diagnostics.title,
                symbol: ConfigWorkspaceSection.diagnostics.symbol,
                count: store.counts.diagnosticCount,
                indent: 0,
                isSelected: store.section == .diagnostics
            ) {
                clearSearchFocus()
                store.select(.diagnostics)
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
            await store.loadIfNeeded(
                sessions: env.store.sessions,
                keyStorageMode: env.preferences.apiProviderKeyStorageMode
            )
        }
    }

    private var statusCard: some View {
        let counts = store.counts
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("CONFIG")
                    .font(.sora(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                if store.isLoadingActiveSection {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            HStack(spacing: 10) {
                AIConfigsMiniStat(value: "\(counts.providerCount)", label: "providers")
                AIConfigsMiniStat(value: "\(counts.configFileCount)", label: "files")
                AIConfigsMiniStat(value: "\(counts.profileCount)", label: "profiles")
                Spacer(minLength: 0)
                Button {
                    refresh()
                } label: {
                    Image(systemName: AppIcon.Action.refresh)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(store.isLoadingActiveSection)
                .help("Refresh Config")
            }

            HStack(spacing: 8) {
                Image(systemName: counts.diagnosticCount == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(counts.diagnosticCount == 0 ? Color.stxAccent : Color(red: 0.92, green: 0.58, blue: 0.16))
                Text(counts.diagnosticCount == 0 ? "No diagnostics" : "\(counts.diagnosticCount) diagnostics")
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
        let text = Binding<String>(
            get: { store.activeSearchText },
            set: { store.activeSearchText = $0 }
        )

        return HStack(spacing: 6) {
            Image(systemName: AppIcon.Action.search)
                .font(.system(size: 11))
                .foregroundStyle(Color.stxMuted)
                .accessibilityHidden(true)
            TextField(store.searchPlaceholder, text: text)
                .textFieldStyle(.plain)
                .font(.sora(11))
                .focused($searchFieldFocused)
            if !store.activeSearchText.isEmpty {
                Button {
                    store.activeSearchText = ""
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

    private func sectionHeader(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(.sora(10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Color.stxMuted)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func refresh() {
        Task {
            await store.refreshActiveSection(
                sessions: env.store.sessions,
                keyStorageMode: env.preferences.apiProviderKeyStorageMode
            )
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

private struct ConfigWorkspaceSidebarRow: View {
    let title: String
    let symbol: String
    let count: Int?
    let indent: CGFloat
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
            .padding(.leading, 10 + indent)
            .padding(.trailing, 10)
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

#if DEBUG
#Preview("Config sidebar") {
    let env = AppEnvironment.preview()
    return ConfigWorkspaceSidebar(store: env.configWorkspace, onExit: {})
        .environment(env)
        .frame(width: 240, height: 620)
        .background(VisualEffectBackground())
}
#endif
