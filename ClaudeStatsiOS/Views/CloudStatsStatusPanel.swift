import ClaudeStatsCore
import SwiftUI

struct CloudStatsStatusPanel: View {
    let summary: StatsStatusSummary
    let preferences: StatsStatusDisplayPreferencesStore

    private var provider: StatsStatusProviderSnapshot? {
        summary.provider(preferences.selectedProviderID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let provider {
                header(provider)
                statusContent(provider)
            } else {
                missingStatusContent
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func header(_ provider: StatsStatusProviderSnapshot) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(provider.providerID.statusTitle.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            StatusBadge(
                label: provider.rollup.description,
                severity: provider.rollup.severity
            )
            Spacer(minLength: 8)
            Text(updatedLabel(for: provider))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let statusPageURL = provider.statusPageURL {
                Link(destination: statusPageURL) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("Open \(provider.providerID.statusTitle)")
            }
        }
    }

    @ViewBuilder
    private func statusContent(_ provider: StatsStatusProviderSnapshot) -> some View {
        let visibleItems = preferences.visibleItems(for: provider)
        if visibleItems.isEmpty {
            Text("Choose status items in Settings after the next Mac sync.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(visibleItems) { item in
                    CloudStatsStatusUptimeRow(
                        item: item,
                        history: provider.uptimeHistory(for: item)
                    )
                }
            }
        }

        if let incident = provider.incidents.first {
            StatusMessageRow(
                symbol: "exclamationmark.triangle.fill",
                tint: statusColor(for: incident.impact),
                text: incident.name
            )
        }

        if provider.isSummaryStale, let error = provider.summaryError {
            StatusMessageRow(symbol: "wifi.slash", tint: .secondary, text: "Using cached status. \(error)")
        } else if provider.isUptimeStale, let error = provider.uptimeError {
            StatusMessageRow(symbol: "wifi.slash", tint: .secondary, text: "Using cached uptime. \(error)")
        }
    }

    private var missingStatusContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(preferences.selectedProviderID.statusTitle.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text("\(preferences.selectedProviderID.statusTitle) will appear here after Claude Stats on Mac syncs status data.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func updatedLabel(for provider: StatsStatusProviderSnapshot) -> String {
        "UPD \(Self.relativeFormatter.localizedString(for: provider.updatedAt, relativeTo: .now))"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

private struct CloudStatsStatusUptimeRow: View {
    let item: StatsStatusItem
    let history: StatsStatusUptimeHistory?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(item.status.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(for: item.status))
                    .lineLimit(1)
            }

            if let history {
                CloudStatsStatusUptimeStrip(days: history.recentDays())
                uptimeFooter(history)
            } else {
                Text("90-day uptime sync pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func uptimeFooter(_ history: StatsStatusUptimeHistory) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("90 days ago")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
            Text(uptimeText(history))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
            Text("Today")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private var accessibilityLabel: String {
        if let history {
            return "\(item.name), \(item.status.displayName), \(uptimeText(history)) over the last 90 days"
        }
        return "\(item.name), \(item.status.displayName), uptime history pending"
    }

    private func uptimeText(_ history: StatsStatusUptimeHistory) -> String {
        guard let percent = history.uptimePercent() else { return "No data" }
        return String(format: "%.2f %% uptime", percent)
    }
}

private struct CloudStatsStatusUptimeStrip: View {
    let days: [StatsStatusUptimeDay]

    private let spacing: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: spacing) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(color(for: day))
                        .frame(width: barWidth(in: proxy.size.width))
                }
            }
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }

    private func barWidth(in width: CGFloat) -> CGFloat {
        guard !days.isEmpty else { return 0 }
        let totalSpacing = spacing * CGFloat(max(0, days.count - 1))
        return max(1, (width - totalSpacing) / CGFloat(days.count))
    }

    private func color(for day: StatsStatusUptimeDay) -> Color {
        if let hex = day.barFillHex, let color = Color(statusHex: hex) {
            return color
        }
        if day.fullOutageSeconds > 0 || day.majorOutageSeconds > 0 {
            return .red
        }
        if day.partialOutageSeconds > 0 {
            return .orange
        }
        if day.degradedPerformanceSeconds > 0 {
            return .yellow
        }
        return .green
    }
}

private struct StatusBadge: View {
    let label: String
    let severity: StatsStatusSeverity

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor(for: severity))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
    }
}

private struct StatusMessageRow: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

private func statusColor(for severity: StatsStatusSeverity) -> Color {
    switch severity {
    case .operational:
        Color(red: 0.12, green: 0.70, blue: 0.36)
    case .degradedPerformance:
        Color(red: 0.95, green: 0.70, blue: 0.10)
    case .partialOutage, .underMaintenance:
        .orange
    case .majorOutage, .fullOutage:
        .red
    case .unknown:
        .secondary
    }
}

private extension Color {
    init?(statusHex: String) {
        let trimmed = statusHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6,
              let value = Int(trimmed, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
