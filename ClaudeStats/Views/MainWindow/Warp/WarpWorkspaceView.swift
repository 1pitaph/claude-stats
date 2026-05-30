import SwiftUI
import WarpEmbed

struct WarpWorkspaceView: View {
    let section: WarpWorkspaceSection
    @ObservedObject var store: WarpSessionStore
    let chromeMode: TerminalChromeMode
    let backgroundStyle: TerminalBackgroundStyle

    private let horizontalInset: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            store.ensureDefaultSession()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WARP")
                .font(.sora(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.stxMuted)
            HStack(spacing: 10) {
                Text(section.detailTitle)
                    .font(.sora(24, weight: .semibold))
                    .lineLimit(1)
                WarpRuntimeStatusPill(availability: store.availability)
            }
            Text(section.detailDescription)
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .sessions:
            WarpRuntimeSessionView(
                store: store,
                chromeMode: chromeMode,
                backgroundStyle: backgroundStyle
            )
        case .agents:
            WarpPendingWorkspacePane(
                section: section,
                availability: store.availability,
                rows: [
                    WarpPendingRow(symbol: "sparkles", title: "Agent Panel", detail: "Route Warp ADE agent sessions here once the app bridge exposes them."),
                    WarpPendingRow(symbol: "bubble.left.and.bubble.right", title: "Conversation State", detail: "Mirror agent status, active prompt, and run progress without launching Warp.app."),
                    WarpPendingRow(symbol: "terminal", title: "Shell Context", detail: "Bind agent actions to the active embedded Warp session.")
                ]
            )
        case .files:
            WarpPendingWorkspacePane(
                section: section,
                availability: store.availability,
                rows: [
                    WarpPendingRow(symbol: "folder", title: "File Tree", detail: "Host Warp project navigation beside the embedded runtime."),
                    WarpPendingRow(symbol: "doc.text.magnifyingglass", title: "Diff Review", detail: "Surface code review and change inspection when Warp exposes those views."),
                    WarpPendingRow(symbol: "arrow.triangle.branch", title: "Workspace Scope", detail: "Keep file actions bound to the Claude Stats workspace.")
                ]
            )
        case .settings:
            WarpPendingWorkspacePane(
                section: section,
                availability: store.availability,
                rows: [
                    WarpPendingRow(symbol: "checkmark.seal", title: "Runtime", detail: store.availability.message),
                    WarpPendingRow(symbol: "paintpalette", title: "Appearance", detail: "Map app terminal chrome, font, and color preferences into Warp-specific controls."),
                    WarpPendingRow(symbol: "keyboard", title: "Input", detail: "Reserve controls for focus, clipboard, key handling, and shortcut conflicts.")
                ]
            )
        }
    }
}

struct WarpRuntimeSessionView: View {
    @ObservedObject var store: WarpSessionStore
    let chromeMode: TerminalChromeMode
    let backgroundStyle: TerminalBackgroundStyle

    var body: some View {
        ZStack {
            TerminalBackdropView(style: backgroundStyle, colorScheme: .dark)

            VStack(spacing: 0) {
                if chromeMode.showsTopTabs {
                    header
                }

                ZStack {
                    TerminalPalette.terminalBackground
                    WarpHostView(store: store)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if chromeMode.showsStatusBar {
                    statusBar
                }
            }
            .background(TerminalPalette.chromeBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(TerminalPalette.stroke, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.26), radius: 22, y: 14)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .terminalEntrance(cornerRadius: 8)
            .padding(14)
        }
        .environment(\.colorScheme, .dark)
        .background(Color.stxBackground)
        .onAppear {
            store.ensureDefaultSession()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TerminalPalette.accent)

            Text("Warp")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(TerminalPalette.text)

            Spacer()

            if !store.availability.isReady {
                Text("bridge pending")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(TerminalPalette.muted)
            }
        }
        .frame(height: 46)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.045))
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: store.availability.isReady ? "checkmark.circle" : "wrench.and.screwdriver")
                .font(.system(size: 11, weight: .medium))
            Text(store.availability.isReady ? "Warp embedded runtime ready" : "Warp embedded runtime pending")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(TerminalPalette.muted)
        .frame(height: 32)
        .padding(.horizontal, 12)
        .background(Color.black.opacity(0.18))
    }
}

struct WarpRuntimeStatusPill: View {
    let availability: WarpRuntimeAvailability

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: availability.isReady ? "checkmark.circle.fill" : "wrench.and.screwdriver")
                .font(.system(size: 10, weight: .semibold))
            Text(availability.isReady ? "Ready" : "Pending")
                .font(.sora(10, weight: .semibold))
        }
        .foregroundStyle(availability.isReady ? Color.green : Color.stxMuted)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color.primary.opacity(0.055), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct WarpPendingWorkspacePane: View {
    let section: WarpWorkspaceSection
    let availability: WarpRuntimeAvailability
    let rows: [WarpPendingRow]

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 16) {
                readinessCard
                roadmapCard
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label(section.detailTitle, systemImage: section.symbol)
                    .font(.sora(14, weight: .semibold))
                WarpRuntimeStatusPill(availability: availability)
                Spacer()
            }

            Text("This Warp ADE surface is reserved while the in-window bridge matures.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)

            Text(availability.message)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .mainWindowPanel()
    }

    private var roadmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Next surfaces", systemImage: "rectangle.3.group")
                .font(.sora(14, weight: .semibold))

            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.stxAccent)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title)
                            .font(.sora(12, weight: .semibold))
                        Text(row.detail)
                            .font(.sora(11))
                            .foregroundStyle(Color.stxMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .mainWindowPanel()
    }
}

private struct WarpPendingRow: Identifiable {
    let symbol: String
    let title: String
    let detail: String

    var id: String { title }
}

#if DEBUG
#Preview("Warp workspace") {
    @Previewable @State var section: WarpWorkspaceSection = .sessions
    return WarpWorkspaceView(
        section: section,
        store: WarpSessionStore(),
        chromeMode: .tabsAndStatus,
        backgroundStyle: .fluidGradient
    )
    .environment(AppEnvironment.preview())
    .frame(width: 980, height: 720)
    .background(Color.stxBackground)
}
#endif
