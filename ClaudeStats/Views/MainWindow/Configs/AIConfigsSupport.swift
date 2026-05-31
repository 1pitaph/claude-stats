import SwiftUI

enum AIConfigsPaneMetrics {
    static let browserMinWidth: CGFloat = 300
    static let inspectorMinWidth: CGFloat = 420
    static let browserMinHeight: CGFloat = 220
    static let inspectorMinHeight: CGFloat = 300
    static let workspaceAutoBreakpoint: CGFloat = 860

    static let sideBySideConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: browserMinWidth,
        secondaryMinimumPaneLength: inspectorMinWidth
    )
    static let stackedConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: browserMinHeight,
        secondaryMinimumPaneLength: inspectorMinHeight
    )
}

struct AIConfigsBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.sora(8, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct AIConfigsMetricCard: View {
    let title: String
    let value: String
    var symbol: String?
    var tint: Color = Color.stxAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 16)
                }
                Text(title.uppercased())
                    .font(.sora(9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Color.stxMuted)
            }
            Text(value)
                .font(.sora(22, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1))
    }
}

struct AIConfigsMiniStat: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.sora(9, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.sora(9))
                .foregroundStyle(Color.stxMuted)
        }
    }
}

struct AIConfigsEmptyState: View {
    let title: String
    let message: String
    var symbol: String = AppIcon.Resource.transcriptSearch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.stxMuted)
            Text(title)
                .font(.sora(15, weight: .semibold))
            Text(message)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension AIConfigProject {
    var configsIconName: String {
        switch kind {
        case .global: AppIcon.Network.domain
        case .project: AppIcon.Resource.folder
        case .unassigned: AppIcon.Resource.tray
        }
    }

    var configsDetailText: String {
        switch kind {
        case .global:
            "Global AI tool files"
        case .unassigned:
            "Plans without a clear project"
        case .project:
            path ?? "Project"
        }
    }
}
