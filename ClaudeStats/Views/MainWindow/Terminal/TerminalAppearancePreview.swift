import SwiftUI

struct TerminalAppearancePreview: View {
    @Environment(\.colorScheme) private var hostColorScheme

    let chromeMode: TerminalChromeMode
    let backgroundStyle: TerminalBackgroundStyle

    var body: some View {
        ZStack {
            TerminalBackdropView(style: backgroundStyle, colorScheme: hostColorScheme)

            VStack(spacing: 0) {
                if chromeMode.showsTopTabs {
                    previewTabs
                }

                previewSurface

                if chromeMode.showsStatusBar {
                    previewStatus
                }
            }
            .background(TerminalPalette.chromeBackground.opacity(0.94), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(TerminalPalette.stroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(12)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.stxStroke, lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
    }

    private var previewTabs: some View {
        HStack(spacing: 5) {
            previewTab(title: "claude-stats", selected: true)
            previewTab(title: "build", selected: false)
            Spacer(minLength: 0)
            Image(systemName: AppIcon.Action.add)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TerminalPalette.muted)
                .frame(width: 30, height: 30)
        }
        .frame(height: 42)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.045))
    }

    private func previewTab(title: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: AppIcon.Runtime.terminal)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(selected ? TerminalPalette.text : TerminalPalette.muted)
        .padding(.horizontal, 12)
        .frame(width: 146, height: 29, alignment: .leading)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TerminalPalette.chromeRaised)
            }
        }
    }

    private var previewSurface: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("1pitaph@MacBook")
                    .foregroundStyle(TerminalPalette.success)
                Text("claude-stats")
                    .foregroundStyle(TerminalPalette.muted)
                Text("%")
                    .foregroundStyle(TerminalPalette.dimmed)
            }
            .font(.system(size: 12, weight: .regular, design: .monospaced))

            RoundedRectangle(cornerRadius: 2)
                .fill(TerminalPalette.text)
                .frame(width: 7, height: 15)
                .opacity(0.82)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TerminalPalette.terminalBackground)
    }

    private var previewStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: AppIcon.Resource.folder)
                .font(.system(size: 11, weight: .medium))
            Text("~/dev/mac/claude-stats")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .lineLimit(1)
            Spacer()
            Text("2 tabs")
                .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
        }
        .foregroundStyle(TerminalPalette.muted)
        .frame(height: 32)
        .padding(.horizontal, 12)
        .background(Color.black.opacity(0.18))
    }
}
