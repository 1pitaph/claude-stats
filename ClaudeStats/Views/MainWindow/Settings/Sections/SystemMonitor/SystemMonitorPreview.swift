import SwiftUI

struct SystemMonitorPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label("System", systemImage: AppIcon.Workspace.system)
                    .font(.sora(13, weight: .semibold))
                Spacer()
                Text("3s")
                    .font(.sora(10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }

            HStack(alignment: .top, spacing: 10) {
                previewCard(
                    title: "CPU",
                    value: "42%",
                    colors: [Color.stxRamp[1], Color.stxRamp[0]]
                )
                previewCard(
                    title: "Memory",
                    value: "64%",
                    colors: [Color.stxRamp[0], Color.stxRamp[1], Color.stxRamp[3]]
                )
                previewCard(
                    title: "Network",
                    value: "1.8 MB/s",
                    colors: [Color.stxRamp[3], Color.stxRamp[0]]
                )
            }
        }
        .padding(16)
        .frame(height: 210)
        .appSurface(.compactCard(radius: 10))
    }

    private func previewCard(title: String, value: String, colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.sora(9, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(18, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            SystemTimelineChart(
                bars: (0..<24).map { index in
                    colors.enumerated().map { offset, color in
                        let base = 0.08 + Double((index + offset * 3) % 8) * 0.018
                        return SystemTimelineSegment(value: base, color: color)
                    }
                },
                placeholderCount: 24
            )
            .frame(height: 54)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.stxStroke, lineWidth: 1)
        }
    }
}
