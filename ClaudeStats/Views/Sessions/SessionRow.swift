import SwiftUI
import AppKit

struct SessionRow: View {
    @Environment(AppEnvironment.self) private var env
    let session: Session

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: session.provider.iconSystemName)
                .foregroundStyle(session.provider.accentColor)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectDisplayName)
                    .font(.sora(12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(session.stats?.title ?? session.externalID)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.relativeDate(session.stats?.lastActivity ?? session.lastModified))
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                HStack(spacing: 6) {
                    if let stats = session.stats {
                        modelDots(stats.models)
                        Label(
                            Format.tokens(stats.totalTokens(includingCacheRead: env.preferences.includeCacheInTokens)),
                            systemImage: AppIcon.Metric.number
                        )
                        .labelStyle(.titleAndIcon)
                        Text(Format.cost(stats.totalCost(for: env.preferences.costEstimationMode)))
                    }
                }
                .font(.sora(9).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal Transcript in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.filePath)])
            }
            if let cwd = session.cwd, FileManager.default.fileExists(atPath: cwd) {
                Button("Open Project Folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                }
            }
        }
    }

    /// Up to four model swatches (then a `+N`), colored to match the Usage screen.
    @ViewBuilder
    private func modelDots(_ models: [ModelUsage]) -> some View {
        let shown = Array(models.prefix(4).enumerated())
        if !shown.isEmpty {
            HStack(spacing: 3) {
                ForEach(shown, id: \.element.id) { idx, _ in
                    Rectangle().fill(ModelPalette.color(at: idx)).frame(width: 6, height: 6)
                }
                if models.count > shown.count {
                    Text("+\(models.count - shown.count)")
                        .font(.sora(8, weight: .medium))
                        .foregroundStyle(Color.stxMuted.opacity(0.7))
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        ForEach(Session.previewSamples) { SessionRow(session: $0).padding(8) }
    }
    .environment(AppEnvironment.preview())
    .frame(width: 380, height: 200)
    .background(Color.stxBackground)
    .preferredColorScheme(.dark)
}
#endif
