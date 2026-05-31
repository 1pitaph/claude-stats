import SwiftUI

struct ReleaseHistoryPanel: View {
    let entries: [ReleaseHistoryEntry]
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Color.stxStroke)
                .frame(height: 1)
            AppScrollView {
                timeline
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
            }
        }
        .appSurface(.plainFill)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.stxStroke)
                .frame(width: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: -8, y: 0)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Release History")
                    .font(.sora(15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Since 1.4.0")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }

            Spacer(minLength: 12)

            Button(action: onClose) {
                Image(systemName: AppIcon.Action.close)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                    .frame(width: 28, height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close Release History")
            .accessibilityLabel("Close Release History")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                ReleaseHistoryTimelineItem(
                    entry: entry,
                    isLast: entry.id == entries.last?.id
                )
            }
        }
        .background(alignment: .leading) {
            if entries.count > 1 {
                Rectangle()
                    .fill(Color.stxStroke)
                    .frame(width: 1)
                    .padding(.leading, 6)
                    .padding(.vertical, 8)
            }
        }
    }
}

private struct ReleaseHistoryTimelineItem: View {
    let entry: ReleaseHistoryEntry
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.stxAccent)
                .frame(width: 9, height: 9)
                .overlay {
                    Circle()
                        .strokeBorder(AppSurface.panelFill, lineWidth: 2)
                }
                .frame(width: 13, height: 13)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.version)
                        .font(.sora(13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(entry.date)
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }

                Text(entry.headline)
                    .font(.sora(12, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.changes, id: \.self) { change in
                        ReleaseHistoryChangeRow(text: change)
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : 24)
        }
    }
}

private struct ReleaseHistoryChangeRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.stxMuted.opacity(0.56))
                .frame(width: 4, height: 4)
                .padding(.top, 6)

            Text(text)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("Release History Panel") {
    ReleaseHistoryPanel(entries: ReleaseHistoryCatalog.entries, onClose: {})
        .frame(width: 380, height: 620)
        .background(Color.stxBackground)
}
#endif
