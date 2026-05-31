import SwiftUI

struct GitChangedFileRow: View {
    static let rowHeight: CGFloat = 30
    static let contentHorizontalInset: CGFloat = 12

    private static let metricSpacing: CGFloat = 16

    let model: GitChangedFileRowModel
    let onOpen: (GitChangedFileRowModel) -> Void

    @ViewBuilder
    var body: some View {
        if model.isOpenable {
            Button {
                onOpen(model)
            } label: {
                rowChrome
            }
            .buttonStyle(.plain)
            .rowFrame
            .help(model.helpText)
            .accessibilityLabel(Text(model.accessibilityLabel))
        } else {
            rowChrome
                .rowFrame
                .help(model.helpText)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(model.accessibilityLabel))
        }
    }

    private var rowChrome: some View {
        HStack(spacing: Self.metricSpacing) {
            leadingMetric
                .fixedSize(horizontal: true, vertical: false)
            Text(model.path)
                .font(.sora(10, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Spacer(minLength: 8)

            if !model.statusBadges.isEmpty {
                statusBadges
            }

            if model.isOpenable {
                disclosureIcon
            }
        }
        .padding(.horizontal, Self.contentHorizontalInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leadingMetric: some View {
        if let badge = model.kindBadge {
            badgeView(badge)
        } else if let churn = model.churn {
            churnView(churn)
        }
    }

    @ViewBuilder
    private func churnView(_ churn: GitChangedFileRowModel.Churn) -> some View {
        switch churn {
        case .binary:
            Text("bin")
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
        case .text(let insertions, let deletions):
            HStack(spacing: Self.metricSpacing) {
                Text("+\(insertions)")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(GitPalette.add)
                Text("-\(deletions)")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(GitPalette.del)
            }
        }
    }

    private var statusBadges: some View {
        HStack(spacing: 5) {
            ForEach(model.statusBadges) { badge in
                badgeView(badge)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func badgeView(_ badge: GitChangedFileRowModel.Badge) -> some View {
        Text(badge.label)
            .font(.sora(8, weight: .semibold).monospacedDigit())
            .foregroundStyle(badgeColor(badge.tone))
            .lineLimit(1)
            .help(badge.help)
    }

    private var disclosureIcon: some View {
        Image(systemName: AppIcon.Navigation.disclosure)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Color.stxMuted)
            .frame(width: 22, height: 22)
    }

    private func badgeColor(_ tone: GitChangedFileRowModel.Tone) -> Color {
        switch tone {
        case .add: return GitPalette.add
        case .delete: return GitPalette.del
        case .tag: return GitPalette.tag
        case .head: return GitPalette.head
        case .danger: return Color.red
        case .muted: return Color.stxMuted
        }
    }
}

private extension View {
    var rowFrame: some View {
        frame(
            maxWidth: .infinity,
            minHeight: GitChangedFileRow.rowHeight,
            maxHeight: GitChangedFileRow.rowHeight,
            alignment: .leading
        )
        .contentShape(Rectangle())
    }
}
