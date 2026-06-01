import SwiftUI
import AppKit

/// Which pane of the stats panel is shown.
enum StatsPane: String, CaseIterable, Identifiable {
    case sessions, usage, activity, git
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sessions: L10n.string("stats.pane.sessions", defaultValue: "SESSIONS")
        case .usage: L10n.string("stats.pane.usage", defaultValue: "USAGE")
        case .activity: L10n.string("stats.pane.activity", defaultValue: "ACTIVITY")
        case .git: L10n.string("stats.pane.git", defaultValue: "GIT")
        }
    }
}

/// How much of the share timestamp to show in the exported panel's header
/// corner. Year + month are always shown; this picks the extra precision.
enum ExportStampPrecision: String, Hashable, CaseIterable, Identifiable {
    case monthOnly, day, minute
    var id: String { rawValue }
    var label: String {
        switch self {
        case .monthOnly: L10n.string("export.stamp.month", defaultValue: "Month")
        case .day: L10n.string("export.stamp.day", defaultValue: "Day")
        case .minute: L10n.string("export.stamp.time", defaultValue: "Time")
        }
    }
    func string(for date: Date) -> String {
        switch self {
        case .monthOnly: date.formatted(.dateTime.month(.abbreviated).year())
        case .day: date.formatted(.dateTime.month(.abbreviated).day().year())
        case .minute: date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
        }
    }
}

/// Per-pane frozen state for an exported panel — the share window resolves all
/// of these and ``StatsPanelBody`` picks the one matching the selected pane.
struct StatsExportConfig {
    /// Usage pane settings. `.period` is also reused by the Sessions pane.
    var usage: UsageView.ExportConfig
    var activity: AIActivityView.ExportData
    /// Whether the exported snapshot includes the top strip (the platform
    /// switcher when multiple platforms are enabled, otherwise the scanline bar).
    var showTopBar: Bool = true
    /// The share timestamp shown in the header corner (replaces the live
    /// "UPD …" readout).
    var stampDate: Date = .now
    var stampPrecision: ExportStampPrecision = .monthOnly
}

/// The stats panel body: a scanline strip, a header, a Sessions/Usage title bar
/// with a toggle, and the selected pane. Used both inside ``MenuPanelView`` (the
/// dropdown, which adds the Settings/Quit footer) and in the share-export window.
///
/// When `export` is non-nil the view is in "export" mode: the Usage pane's
/// period picker becomes a static label below the chart, the chart honours the
/// frozen style/scale from the config, the Activity pane renders a pre-resolved
/// snapshot, the header's refresh control is hidden, and the pane content takes
/// its intrinsic height (so `ImageRenderer` captures the whole thing rather than
/// a clipped/scrolled slice).
struct StatsPanelBody: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow
    @Binding var pane: StatsPane
    var export: StatsExportConfig? = nil

    private var isExport: Bool { export != nil }

    /// Git gets a pane only when tracking is on *and* the user wants it in-panel
    /// (otherwise it lives in its own window, opened from the header button).
    private var gitInPanel: Bool { env.preferences.gitTrackingEnabled && !env.preferences.gitOpensInWindow }
    private var gitInWindow: Bool { env.preferences.gitTrackingEnabled && env.preferences.gitOpensInWindow }

    private var availablePanes: [StatsPane] {
        var panes: [StatsPane] = []
        if AppVariant.isEnabled(.sessions) {
            panes.append(.sessions)
        }
        panes.append(.usage)
        if env.preferences.aiActivityAnalysisEnabled { panes.append(.activity) }
        if gitInPanel { panes.append(.git) }
        return panes
    }

    private var effectivePane: StatsPane {
        availablePanes.contains(pane) ? pane : .usage
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isExport || (export?.showTopBar ?? true) {
                if env.preferences.enabledProviders.count > 1 {
                    ProviderSwitcherBar(interactive: !isExport)
                } else {
                    TickBar(active: env.store.isLoading)
                }
            }
            header
            StxRule()
            paneBar

            Group {
                switch effectivePane {
                case .sessions:
                    #if CLAUDE_STATS_LITE
                    UsageView(mode: export.map { .export($0.usage) } ?? .interactive)
                    #else
                    SessionListView(mode: export.map { .export($0.usage.period) } ?? .interactive)
                    #endif
                case .usage: UsageView(mode: export.map { .export($0.usage) } ?? .interactive)
                case .activity: AIActivityView(mode: export.map { .export($0.activity) } ?? .interactive)
                case .git: GitActivityView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: isExport ? nil : .infinity)
        }
        .onChange(of: env.preferences.aiActivityAnalysisEnabled) { _, enabled in
            if !enabled && pane == .activity { pane = .usage }
        }
        .onChange(of: gitInPanel) { _, inPanel in
            if !inPanel && pane == .git { pane = .usage }
        }
    }

    private var paneBar: some View {
        HStack(spacing: 10) {
            Text(effectivePane.title)
                .font(.sora(18, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                ForEach(availablePanes) { p in
                    PaneChip(title: p.title, isSelected: p == effectivePane) { pane = p }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(L10n.format("stats.header.provider_stats",
                             defaultValue: "%@ STATS",
                             env.preferences.selectedProvider.shortName))
                .font(.sora(15, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.primary)
            Spacer()
            if let export {
                Text(export.stampPrecision.string(for: export.stampDate))
                    .font(.sora(9))
                    .tracking(0.5)
                    .foregroundStyle(Color.stxMuted)
            } else if let last = env.store.lastRefreshedAt {
                Text(L10n.format("stats.header.updated",
                                 defaultValue: "UPD %@",
                                 Format.relativeDate(last)))
                    .font(.sora(9))
                    .tracking(0.5)
                    .foregroundStyle(Color.stxMuted)
            }
            if !isExport && gitInWindow {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: GitActivityView.windowID)
                } label: {
                    BracketBox(spacing: 4) {
                        Image(systemName: AppIcon.Workspace.git).font(.system(size: 10, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxMuted)
                .help("Open Git activity")
            }
            if !isExport {
                Button {
                    Task { await env.store.refresh() }
                } label: {
                    BracketBox(spacing: 4) {
                        if env.store.isLoading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: AppIcon.Action.refresh).font(.system(size: 10, weight: .bold))
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxMuted)
                .disabled(env.store.isLoading)
                .help("Refresh now")

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: MainWindowView.windowID)
                } label: {
                    BracketBox(spacing: 4) {
                        Image(systemName: AppIcon.Window.main).font(.system(size: 10, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxMuted)
                .help("Open the main window")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Root of the dropdown panel: the stats panel body plus a footer with
/// Settings / Share / Quit.
struct MenuPanelView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow

    private static let panelSize = CGSize(width: 380, height: 560)

    @State private var pane: StatsPane = .usage
    @State private var updateAvailable = false
    @State private var availableUpdateVersion: String?

    var body: some View {
        VStack(spacing: 0) {
            StatsPanelBody(pane: $pane)
            StxRule()
            footer
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height, alignment: .topLeading)
        .fixedSize(horizontal: true, vertical: true)
        .clipped()
        .background(VisualEffectBackground(material: .popover))
        .background(MenuPanelWindowSizeLock(size: Self.panelSize))
        .stxFont(13)
        .tint(.stxAccent)
        .onAppear(perform: syncUpdateAvailability)
        .onReceive(NotificationCenter.default.publisher(for: UpdaterController.updateAvailabilityDidChange)) { _ in
            syncUpdateAvailability()
        }
        .animation(.easeOut(duration: 0.16), value: updateAvailable)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: MainWindowView.windowID)
                NotificationCenter.default.post(name: .openSettingsInMainWindow, object: nil)
            } label: {
                BracketBox(spacing: 5) {
                    Label("SETTINGS", systemImage: AppIcon.Workspace.settings)
                        .labelStyle(.titleAndIcon)
                        .font(.sora(10))
                        .tracking(0.8)
                }
            }
            .buttonStyle(.plain)
            if updateAvailable {
                updateButton
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: ShareExportView.windowID)
            } label: {
                BracketBox(spacing: 5) {
                    Label("SHARE", systemImage: AppIcon.Action.exportFile)
                        .labelStyle(.titleAndIcon)
                        .font(.sora(10))
                        .tracking(0.8)
                }
            }
            .buttonStyle(.plain)
            .help(L10n.string("menu.footer.share.help", defaultValue: "Export a snapshot as a PNG"))
            Spacer()
            Button {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.requestUserTermination()
                } else {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                BracketBox(spacing: 5) {
                    Label("QUIT", systemImage: AppIcon.Action.quit)
                        .labelStyle(.titleAndIcon)
                        .font(.sora(10))
                        .tracking(0.8)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var updateButton: some View {
        Button {
            env.updater.checkForUpdates()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: AppIcon.Action.downloadFilled)
                    .font(.system(size: 10, weight: .bold))
                Text("UPDATE")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
            }
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Color.stxAccent.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.stxAccent.opacity(0.58), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.stxAccent)
        .help(updateButtonHelp)
        .accessibilityLabel(updateButtonHelp)
    }

    private var updateButtonHelp: String {
        if let availableUpdateVersion {
            return L10n.format("menu.footer.update.install_version",
                               defaultValue: "Install update %@",
                               availableUpdateVersion)
        }
        return L10n.string("menu.footer.update.install", defaultValue: "Install update")
    }

    private func syncUpdateAvailability() {
        updateAvailable = env.updater.updateAvailable
        availableUpdateVersion = env.updater.availableUpdateVersion
    }
}

/// `MenuBarExtra` with `.window` derives its NSPanel size from SwiftUI's
/// preferred size on every interaction. The compact stats panel intentionally
/// contains flexible scroll/chart content, so we pin the host panel to the
/// product's fixed compact size and avoid a click-triggered resize feedback loop.
private struct MenuPanelWindowSizeLock: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> LockView {
        let view = LockView()
        view.size = size
        return view
    }

    func updateNSView(_ nsView: LockView, context: Context) {
        nsView.size = size
        nsView.applySoon()
    }

    final class LockView: NSView {
        var size: CGSize = .zero
        private weak var lockedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            lockedWindow = window
            applySoon()
        }

        override func layout() {
            super.layout()
            applyIfNeeded()
        }

        func applySoon() {
            DispatchQueue.main.async { [weak self] in
                self?.applyIfNeeded()
            }
        }

        private func applyIfNeeded() {
            guard let window = window ?? lockedWindow, size != .zero else { return }
            lockedWindow = window
            let target = NSSize(width: size.width, height: size.height)
            if window.contentMinSize != target {
                window.contentMinSize = target
            }
            if window.contentMaxSize != target {
                window.contentMaxSize = target
            }
            guard let contentView = window.contentView else { return }
            let current = contentView.bounds.size
            if abs(current.width - target.width) > 0.5 || abs(current.height - target.height) > 0.5 {
                window.setContentSize(target)
            }
        }
    }
}

/// A small underlined tab chip used in the pane bar to switch panes.
private struct PaneChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title)
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(isSelected ? .primary : (hovering ? Color.primary : Color.primary.opacity(0.40)))
                Rectangle()
                    .fill(Color.stxAccent)
                    .frame(height: 1.5)
                    .scaleEffect(x: isSelected ? 1 : 0, anchor: .center)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

#if DEBUG
#Preview("Panel") {
    MenuPanelView()
        .environment(AppEnvironment.preview())
}

#Preview("Panel — empty") {
    MenuPanelView()
        .environment(AppEnvironment.preview(populated: false))
}
#endif
