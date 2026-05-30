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
    var isChatActive = false
    var isWarpActive = false
    var onOpenSettings: () -> Void
    var onOpenLinuxDo: () -> Void
    var onOpenSessions: () -> Void
    var onOpenConfigs: () -> Void
    var onOpenMemory: () -> Void
    var onOpenChat: () -> Void
    var onOpenNetwork: () -> Void
    var onOpenWarp: () -> Void
    var onOpenOps: () -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clear the traffic-light buttons (window uses `.hiddenTitleBar`).
            Color.clear.frame(height: 44)

            navRow(.dashboard)
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
            SidebarRow(
                title: "Sessions",
                symbol: "doc.text.magnifyingglass",
                isSelected: isSessionsActive,
                trailingSymbol: "chevron.right",
                showsTrailingOnHover: true
            ) {
                clearTextFocus()
                onOpenSessions()
            }

            sectionHeader("STATS")
            navRow(.usage)
            navRow(.leaderboards)
            if env.preferences.aiActivityAnalysisEnabled { navRow(.activity) }
            if env.preferences.systemMonitorEnabled { navRow(.system) }

            sectionHeader("TOOLS")
            SidebarRow(
                title: "Chat",
                symbol: "bubble.left.and.bubble.right",
                isSelected: isChatActive,
                trailingSymbol: "chevron.right",
                showsTrailingOnHover: true
            ) {
                clearTextFocus()
                onOpenChat()
            }
            SidebarRow(
                title: "Memory",
                symbol: "brain",
                isSelected: isMemoryActive,
                trailingSymbol: "chevron.right",
                showsTrailingOnHover: true
            ) {
                clearTextFocus()
                onOpenMemory()
            }
            SidebarRow(
                title: "Config",
                symbol: "slider.horizontal.3",
                isSelected: isConfigsActive,
                trailingSymbol: "chevron.right",
                showsTrailingOnHover: true
            ) {
                clearTextFocus()
                onOpenConfigs()
            }
            if env.preferences.gitTrackingEnabled { navRow(.git) }
            SidebarRow(
                title: "Ops",
                symbol: "wrench.and.screwdriver",
                isSelected: false,
                trailingSymbol: "chevron.right",
                showsTrailingOnHover: true
            ) {
                clearTextFocus()
                onOpenOps()
            }
            SidebarRow(
                title: "Network",
                symbol: "network",
                isSelected: false,
                trailingSymbol: "chevron.right",
                showsTrailingOnHover: true
            ) {
                clearTextFocus()
                onOpenNetwork()
            }
            SidebarRow(
                title: "Warp",
                symbol: "sparkles",
                isSelected: isWarpActive,
                trailingSymbol: "chevron.right",
                showsTrailingOnHover: true
            ) {
                clearTextFocus()
                onOpenWarp()
            }

            Spacer(minLength: 0)

            SidebarRow(title: "Settings", symbol: "gearshape", isSelected: false) {
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
    }

    // MARK: - Top nav

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
        availablePages: [.dashboard, .usage, .activity, .git],
        isLinuxDoActive: false,
        isSessionsActive: false,
        isConfigsActive: false,
        isMemoryActive: false,
        isChatActive: false,
        isWarpActive: false,
        onOpenSettings: {},
        onOpenLinuxDo: {},
        onOpenSessions: {},
        onOpenConfigs: {},
        onOpenMemory: {},
        onOpenChat: {},
        onOpenNetwork: {},
        onOpenWarp: {},
        onOpenOps: {}
    )
    .environment(AppEnvironment.preview())
    .frame(width: 240, height: 600)
    .background(VisualEffectBackground())
}
#endif
