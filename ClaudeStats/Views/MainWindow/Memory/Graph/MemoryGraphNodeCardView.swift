import SwiftUI

struct MemoryGraphNodeCardView: View {
    let node: MemoryGraphPresentation.Node
    let isSelected: Bool
    let isHighlighted: Bool
    let isDimmed: Bool
    var isCompact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isCompact {
                compactBody
            } else {
                cardBody
            }
        }
        .buttonStyle(.plain)
        .opacity(isDimmed ? 0.28 : 1)
        .help(node.helpText)
        .accessibilityLabel(node.displayTitle)
        .accessibilityValue(node.subtitle ?? "")
    }

    private var compactBody: some View {
        Image(systemName: MemoryGraphStyle.symbol(for: node.kind))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 26, height: 26)
            .background(fill, in: Circle())
            .overlay(Circle().strokeBorder(stroke, lineWidth: isSelected ? 2 : 1))
            .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0.04), radius: isSelected ? 8 : 3, y: 2)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: MemoryGraphStyle.symbol(for: node.kind))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(node.displayTitle)
                    .font(.sora(10, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if node.count > 1 {
                    Text("\(node.count)")
                        .font(.sora(9, weight: .semibold).monospaced())
                        .foregroundStyle(color)
                }
            }

            if let subtitle = node.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !node.badges.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(node.badges.prefix(3)), id: \.self) { badge in
                        Text(badge)
                            .font(.sora(8, weight: .semibold).monospaced())
                            .foregroundStyle(color)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.12), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(width: width, alignment: .leading)
        .frame(minHeight: 82, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(stroke, lineWidth: isSelected ? 2 : 1))
        .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0.04), radius: isSelected ? 8 : 3, y: 2)
    }

    private var width: CGFloat {
        switch node.lane {
        case .source:
            214
        case .event:
            node.kind == "group" ? 238 : 228
        case .memory:
            236
        }
    }

    private var color: Color {
        MemoryGraphStyle.color(for: node)
    }

    private var fill: Color {
        if isSelected {
            return color.opacity(0.23)
        }
        if isHighlighted {
            return Color.stxAccent.opacity(0.18)
        }
        return Color.primary.opacity(0.07)
    }

    private var stroke: Color {
        if isSelected {
            return Color.stxAccent
        }
        if isHighlighted {
            return Color.stxAccent.opacity(0.85)
        }
        return color.opacity(0.48)
    }
}
