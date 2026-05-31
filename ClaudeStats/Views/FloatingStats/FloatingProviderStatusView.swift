import SwiftUI

enum FloatingProviderStatusContent: Equatable {
    case summary(FloatingProviderStatusSummary)
    case message(String)
}

struct FloatingProviderStatusView: View {
    let content: FloatingProviderStatusContent

    var body: some View {
        switch content {
        case .summary(let summary):
            summaryView(summary)
        case .message(let message):
            messageView(message)
        }
    }

    private func summaryView(_ summary: FloatingProviderStatusSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                Text("\(summary.title.uppercased()) STATUS")
                    .font(.sora(8, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Circle()
                        .fill(summary.severity.tint)
                        .frame(width: 5, height: 5)
                    Text(statusLabel(for: summary))
                        .font(.sora(8, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(summary.severity.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            if summary.days.isEmpty {
                Text("30-DAY STATUS UNAVAILABLE")
                    .font(.sora(8, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Color.stxMuted)
                    .frame(height: 13, alignment: .leading)
            } else {
                HStack(spacing: 1.5) {
                    ForEach(summary.days) { day in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(day.state.tint)
                            .frame(maxWidth: .infinity)
                            .frame(height: 13)
                            .help(day.helpText)
                    }
                }
                .frame(height: 13)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: summary))
    }

    private func messageView(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: AppIcon.Status.networkWarning)
                .font(.system(size: 9, weight: .semibold))
            Text(message)
                .font(.sora(8, weight: .medium))
                .tracking(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(Color.stxMuted)
        .frame(height: 27, alignment: .leading)
        .accessibilityLabel(message)
    }

    private func statusLabel(for summary: FloatingProviderStatusSummary) -> String {
        var parts: [String] = []
        if let uptimePercent = summary.uptimePercent {
            parts.append(String(format: "%.2f%%", uptimePercent))
        }
        parts.append(summary.statusText.uppercased())
        if summary.isStale {
            parts.append("STALE")
        }
        return parts.joined(separator: " · ")
    }

    private func accessibilityLabel(for summary: FloatingProviderStatusSummary) -> String {
        let uptime = summary.uptimePercent.map { String(format: "%.2f percent uptime", $0) } ?? "uptime unavailable"
        return "\(summary.title) status, \(summary.statusText), \(uptime) over the last 30 days"
    }
}

private extension FloatingStatusSeverity {
    var tint: Color {
        switch self {
        case .operational:
            Color.green
        case .underMaintenance:
            Color.blue
        case .degradedPerformance:
            Color.orange
        case .partialOutage, .majorOutage:
            Color.red
        case .unknown:
            Color.stxMuted
        }
    }
}

private extension FloatingStatusDay.State {
    var tint: Color {
        switch self {
        case .operational:
            Color.green.opacity(0.82)
        case .partialOutage:
            Color.orange.opacity(0.92)
        case .majorOutage:
            Color.red.opacity(0.95)
        case .noData:
            Color.stxMuted.opacity(0.35)
        }
    }
}

#if DEBUG
#Preview("Floating status") {
    FloatingProviderStatusView(
        content: .summary(
            FloatingProviderStatusSummary(
                id: "preview",
                title: "Codex",
                statusText: "Operational",
                severity: .operational,
                days: (0..<30).map { index in
                    FloatingStatusDay(
                        date: Date(timeIntervalSince1970: TimeInterval(index * 86_400)),
                        state: index == 12 ? .partialOutage : .operational,
                        helpText: "Day \(index)"
                    )
                },
                uptimePercent: 99.95,
                isStale: false
            )
        )
    )
    .padding(14)
    .frame(width: 300)
    .background(Color.stxBackground)
}
#endif
