import SwiftUI
import AppKit

/// The main window's left column. Two regions stacked vertically:
///   - Top nav (Dashboard, STATS for usage/leaderboards/activity, then TOOLS
///     for configuration, Git, and terminal tools).
/// Settings stays pinned at the bottom.
///
/// Lives over a window-level `NSVisualEffectView` (`.sidebar` material), so
/// its own background stays transparent.
struct SidebarColumn: View {
    @Binding var page: MainPage
    var availablePages: [MainPage]
    var isLinuxDoActive = false
    var isSessionsActive = false
    var isConfigsActive = false
    var isMemoryActive = false
    var isWarpActive = false
    var onOpenSettings: () -> Void
    var onOpenLinuxDo: () -> Void
    var onOpenSessions: () -> Void
    var onOpenConfigs: () -> Void
    var onOpenMemory: () -> Void
    var onOpenNetwork: () -> Void
    var onOpenWarp: () -> Void
    var onOpenOps: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var updateState: UpdaterController.UpdateState = .idle
    @State private var availableUpdateVersion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader

            navRow(.dashboard)
            if AppVariant.isEnabled(.linuxDo) {
                SidebarRow(
                    title: MainPage.linuxDo.title,
                    symbol: MainPage.linuxDo.symbol,
                    assetName: MainPage.linuxDo.assetName,
                    isSelected: isLinuxDoActive,
                    trailingSymbol: "chevron.right",
                    showsTrailingOnHover: true
                ) {
                    clearTextFocus()
                    onOpenLinuxDo()
                }
            }
            if AppVariant.isEnabled(.sessions) {
                SidebarRow(
                    title: "Sessions",
                    symbol: AppIcon.Resource.transcriptSearch,
                    isSelected: isSessionsActive,
                    trailingSymbol: "chevron.right",
                    showsTrailingOnHover: true
                ) {
                    clearTextFocus()
                    onOpenSessions()
                }
            }

            sectionHeader("STATS")
            navRow(.usage)
            navRow(.leaderboards)
            if env.preferences.aiActivityAnalysisEnabled { navRow(.activity) }
            if env.preferences.systemMonitorEnabled { navRow(.system) }

            sectionHeader("TOOLS")
            navRow(.dailyReport)
            navRow(.gantt)
            if AppVariant.isEnabled(.warp) {
                SidebarRow(
                    title: "Warp",
                    symbol: AppIcon.Workspace.warp,
                    isSelected: isWarpActive,
                    trailingSymbol: "chevron.right",
                    showsTrailingOnHover: true
                ) {
                    clearTextFocus()
                    onOpenWarp()
                }
            }
            if AppVariant.isEnabled(.memory) {
                SidebarRow(
                    title: "Memory",
                    symbol: AppIcon.Workspace.memory,
                    isSelected: isMemoryActive,
                    trailingSymbol: "chevron.right",
                    showsTrailingOnHover: true
                ) {
                    clearTextFocus()
                    onOpenMemory()
                }
            }
            if AppVariant.isEnabled(.config) {
                SidebarRow(
                    title: "Config",
                    symbol: AppIcon.Workspace.configs,
                    isSelected: isConfigsActive,
                    trailingSymbol: "chevron.right",
                    showsTrailingOnHover: true
                ) {
                    clearTextFocus()
                    onOpenConfigs()
                }
            }
            if env.preferences.gitTrackingEnabled { navRow(.git) }
            if AppVariant.isEnabled(.ops) {
                SidebarRow(
                    title: "Ops",
                    symbol: AppIcon.Workspace.ops,
                    isSelected: false,
                    trailingSymbol: "chevron.right",
                    showsTrailingOnHover: true
                ) {
                    clearTextFocus()
                    onOpenOps()
                }
            }
            if AppVariant.isEnabled(.network) {
                SidebarRow(
                    title: "Network",
                    symbol: AppIcon.Workspace.network,
                    isSelected: false,
                    trailingSymbol: "chevron.right",
                    showsTrailingOnHover: true
                ) {
                    clearTextFocus()
                    onOpenNetwork()
                }
            }

            Spacer(minLength: 0)

            SidebarRow(title: "Settings", symbol: AppIcon.Workspace.settings, isSelected: false) {
                clearTextFocus()
                onOpenSettings()
            }
        }
        .padding(.bottom, 10)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { clearTextFocus() }
        }
        .onAppear(perform: syncUpdateAvailability)
        .onReceive(NotificationCenter.default.publisher(for: UpdaterController.updateAvailabilityDidChange)) { _ in
            syncUpdateAvailability()
        }
    }

    // MARK: - Top nav

    private var sidebarHeader: some View {
        HStack {
            Spacer(minLength: 0)
            if updateState.showsUpdatePill {
                updatePill
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(height: 44)
        .padding(.leading, 96)
        .padding(.trailing, 12)
        .animation(.easeOut(duration: 0.16), value: updateState)
        .animation(.easeOut(duration: 0.16), value: availableUpdateVersion)
    }

    private var updatePill: some View {
        Button(action: openUpdateUI) {
            HStack(spacing: 6) {
                Image(systemName: AppIcon.Action.downloadToLine)
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 12, height: 12)
                Text(verbatim: "UPDATE")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(updatePillBackground))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(updatePillForeground)
        .disabled(!updateState.canOpenUpdateUI)
        .help(updatePillHelp)
        .accessibilityLabel(updatePillHelp)
    }

    private var updatePillHelp: String {
        switch updateState {
        case .idle:
            "No update available"
        case .downloading:
            availableUpdateVersion.map { "Downloading update \($0)" } ?? "Downloading update"
        case .readyToInstall:
            availableUpdateVersion.map { "Install update \($0)" } ?? "Install update"
        case .installing:
            availableUpdateVersion.map { "Installing update \($0)" } ?? "Installing update"
        case .available:
            availableUpdateVersion.map { "Open update \($0)" } ?? "Open update"
        }
    }

    private var updatePillBackground: Color {
        switch updateState {
        case .downloading:
            Color.primary.opacity(0.08)
        case .idle:
            Color.clear
        case .available, .readyToInstall, .installing:
            Color.stxAccent.opacity(0.16)
        }
    }

    private var updatePillForeground: Color {
        updateState.canOpenUpdateUI ? Color.stxAccent : Color.stxMuted
    }

    private func openUpdateUI() {
        guard updateState.canOpenUpdateUI else { return }
        clearTextFocus()
        env.updater.checkForUpdates()
    }

    private func syncUpdateAvailability() {
        updateState = env.updater.updateState
        availableUpdateVersion = env.updater.availableUpdateVersion
    }

    @ViewBuilder
    private func navRow(_ p: MainPage) -> some View {
        if availablePages.contains(p) {
            SidebarRow(
                title: p.title,
                symbol: p.symbol,
                assetName: p.assetName,
                isSelected: page == p
            ) {
                clearTextFocus()
                page = p
            }
        }
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

    private func clearTextFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

// MARK: - Top nav row

/// One sidebar nav row: an icon + label inside a rounded selection chip.
struct SidebarRow: View {
    let title: String
    let symbol: String
    var assetName: String? = nil
    let isSelected: Bool
    var trailingText: String? = nil
    var trailingSymbol: String?
    var showsTrailingOnHover = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                Text(LocalizedStringKey(title))
                    .font(.sora(13))
                    .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                Spacer(minLength: 0)
                if let trailingText {
                    Text(trailingText)
                        .font(.sora(9).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                        .lineLimit(1)
                }
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                        .opacity(showsTrailingOnHover ? (hovering ? 1 : 0) : 1)
                        .frame(width: 12)
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

    @ViewBuilder
    private var icon: some View {
        if let assetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .opacity(isSelected ? 1 : 0.82)
                .frame(width: 18)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
        }
    }
}

#if DEBUG
#Preview("Sidebar column") {
    @Previewable @State var page: MainPage = .dashboard
    return SidebarColumn(
        page: $page,
        availablePages: [.dashboard, .usage, .activity, .dailyReport, .git],
        isLinuxDoActive: false,
        isSessionsActive: false,
        isConfigsActive: false,
        isMemoryActive: false,
        isWarpActive: false,
        onOpenSettings: {},
        onOpenLinuxDo: {},
        onOpenSessions: {},
        onOpenConfigs: {},
        onOpenMemory: {},
        onOpenNetwork: {},
        onOpenWarp: {},
        onOpenOps: {}
    )
    .environment(AppEnvironment.preview())
    .frame(width: 240, height: 600)
    .background(VisualEffectBackground())
}
#endif
