import SwiftUI
import WarpEmbed

struct TerminalWorkspaceView: View {
    @Environment(AppEnvironment.self) private var env

    @ObservedObject var warpStore: WarpSessionStore

    var body: some View {
        switch env.preferences.terminalRuntimeKind {
        case .warp:
            WarpRuntimeSessionView(
                store: warpStore,
                chromeMode: env.preferences.terminalChromeMode,
                backgroundStyle: env.preferences.terminalBackgroundStyle
            )
        case .disabled:
            TerminalRuntimeDisabledView()
        }
    }
}

#if DEBUG
#Preview("Terminal workspace") {
    TerminalWorkspaceView(warpStore: WarpSessionStore())
        .environment(AppEnvironment.preview())
        .frame(width: 900, height: 560)
}
#endif

private struct TerminalRuntimeDisabledView: View {
    var body: some View {
        ZStack {
            Color.stxBackground
            VStack(spacing: 10) {
                Image(systemName: AppIcon.Status.disabled)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(TerminalPalette.dimmed)
                Text("Terminal runtime disabled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TerminalPalette.muted)
            }
        }
    }
}
