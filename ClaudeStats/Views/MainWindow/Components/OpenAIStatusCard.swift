import SwiftUI

struct OpenAIStatusCard: View {
    let status: OpenAIStatusViewModel
    var onSwitchStatusProvider: (() -> Void)? = nil
    var switchStatusHelp: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .appSurface(.mainWindowCard)
        .task { await status.refreshIfNeeded() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("OPENAI STATUS")
                .font(.sora(9, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Color.stxMuted)
            if let snapshot = status.snapshot {
                StatusSeverityBadge(
                    label: snapshot.rollup.description,
                    indicatorTint: snapshot.rollup.severity.tint
                )
            } else if status.isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(L10n.string("status.checking", defaultValue: "Checking"))
                        .font(.sora(10, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                }
            }
            Spacer()
            Text(updatedLabel)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
            Button {
                Task { await status.refresh(force: true) }
            } label: {
                Image(systemName: AppIcon.Action.refresh)
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxMuted)
            .help(L10n.string("status.openai.refresh", defaultValue: "Refresh OpenAI Status"))
            if let onSwitchStatusProvider {
                Button(action: onSwitchStatusProvider) {
                    Image(systemName: AppIcon.Settings.features)
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxMuted)
                .help(switchStatusHelp)
            }
            Link(destination: status.statusPageURL) {
                Image(systemName: AppIcon.Action.openExternal)
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxMuted)
            .help(L10n.string("status.openai.open", defaultValue: "Open OpenAI Status"))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = status.snapshot {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(status.visibleUptimeRows) { row in
                    if let history = row.history {
                        OpenAIStatusUptimeChart(group: row.group, history: history)
                            .equatable()
                    } else {
                        groupRow(row.group)
                    }
                }
                if let incident = snapshot.activeIncident {
                    incidentRow(incident)
                }
                if status.isStale, let lastError = status.lastError {
                    cachedStatusRow(L10n.format("status.cached_status",
                                                defaultValue: "Using cached status. %@",
                                                lastError))
                } else if status.isUptimeStale, let uptimeLastError = status.uptimeLastError {
                    cachedStatusRow(L10n.format("status.cached_uptime",
                                                defaultValue: "Using cached uptime. %@",
                                                uptimeLastError))
                }
            }
        } else if let lastError = status.lastError {
            Text(lastError)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(L10n.string("status.openai.checking", defaultValue: "Checking OpenAI Status…"))
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
        }
    }

    private var updatedLabel: String {
        guard let snapshot = status.snapshot else { return "" }
        let date = snapshot.pageUpdatedAt ?? snapshot.fetchedAt
        let stale = status.isStale ? L10n.string("status.stale_suffix", defaultValue: " · stale") : ""
        return L10n.format("status.updated_short", defaultValue: "UPD %@", Format.relativeDate(date)) + stale
    }

    private func groupRow(_ group: OpenAIStatusGroup) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: group.status.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(group.status.tint)
                .frame(width: 16)
            Text(group.name)
                .font(.sora(12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(group.status.displayName)
                .font(.sora(11))
                .foregroundStyle(group.status.tint)
                .lineLimit(1)
        }
    }

    private func incidentRow(_ incident: OpenAIStatusIncident) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: AppIcon.Status.warningFilled)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(incident.impact.tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(incident.name)
                    .font(.sora(11, weight: .medium))
                    .lineLimit(2)
                if let shortlink = incident.shortlink {
                    Link(destination: shortlink) {
                        Text("View incident")
                    }
                        .font(.sora(10))
                }
            }
        }
        .padding(.top, 2)
    }

    private func cachedStatusRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: AppIcon.Status.offline)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 16)
            Text(message)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

private struct OpenAIStatusUptimeChart: View, Equatable {
    let group: OpenAIStatusGroup
    let history: OpenAIStatusUptimeHistory

    private var days: [OpenAIStatusUptimeDay] {
        history.recentDays()
    }

    private var uptimeText: String {
        guard let percent = history.uptimePercent() else {
            return L10n.string("status.uptime.no_data", defaultValue: "No data")
        }
        return L10n.format("status.uptime.percent", defaultValue: "%.2f %% uptime", percent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(group.name)
                    .font(.sora(13, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(group.status.displayName)
                    .font(.sora(12, weight: .medium))
                    .foregroundStyle(group.status.tint)
                    .lineLimit(1)
            }

            StatusUptimeStrip(bars: bars)

            footer
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("status.uptime.accessibility",
                                        defaultValue: "%@, %@, %@ over the last 90 days",
                                        group.name,
                                        group.status.displayName,
                                        uptimeText))
    }

    private var bars: [StatusUptimeBar] {
        days.map { day in
            StatusUptimeBar(
                id: day.id,
                color: day.chartColor(startDate: history.startDate),
                tooltip: dayHelp(day)
            )
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("90 days ago")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize()
            Rectangle()
                .fill(Color.stxStroke)
                .frame(height: 1)
            Text(uptimeText)
                .font(.sora(11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .fixedSize()
            Rectangle()
                .fill(Color.stxStroke)
                .frame(height: 1)
            Text("Today")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize()
        }
    }

    private func dayHelp(_ day: OpenAIStatusUptimeDay) -> String {
        let date = Format.day(day.date)
        guard day.hasOutage else {
            return L10n.format("status.uptime.no_downtime",
                               defaultValue: "%@: no downtime recorded",
                               date)
        }
        var parts: [String] = []
        if day.degradedPerformanceSeconds > 0 {
            parts.append(L10n.format("status.uptime.degraded_duration",
                                     defaultValue: "degraded performance %@",
                                     Format.duration(TimeInterval(day.degradedPerformanceSeconds))))
        }
        if day.partialOutageSeconds > 0 {
            parts.append(L10n.format("status.uptime.partial_outage_duration",
                                     defaultValue: "partial outage %@",
                                     Format.duration(TimeInterval(day.partialOutageSeconds))))
        }
        if day.fullOutageSeconds > 0 {
            parts.append(L10n.format("status.uptime.full_outage_duration",
                                     defaultValue: "full outage %@",
                                     Format.duration(TimeInterval(day.fullOutageSeconds))))
        }
        if parts.isEmpty, !day.displaySeverity.isOperational {
            parts.append(day.displaySeverity.displayName)
        }
        return "\(date): \(parts.joined(separator: ", "))"
    }
}

private extension OpenAIStatusSeverity {
    var tint: Color {
        switch self {
        case .operational: Color.green
        case .underMaintenance: Color.blue
        case .degradedPerformance: Color.orange
        case .partialOutage, .fullOutage: Color.red
        case .unknown: Color.stxMuted
        }
    }

    var symbolName: String {
        switch self {
        case .operational: AppIcon.Status.successFilled
        case .underMaintenance: AppIcon.Status.maintenance
        case .degradedPerformance: AppIcon.Status.errorFilled
        case .partialOutage, .fullOutage: AppIcon.Status.failureFilled
        case .unknown: AppIcon.Status.unknown
        }
    }
}

private extension OpenAIStatusUptimeDay {
    func chartColor(startDate: Date?) -> Color {
        if let startDate, date < startDate {
            return OpenAIStatusUptimeChartPalette.noData
        }
        if let hex = barFillHex, let color = Color(statusHex: hex) {
            return color
        }
        if fullOutageSeconds > 0 {
            return OpenAIStatusUptimeChartPalette.majorOutage
        }
        if partialOutageSeconds > 0 || degradedPerformanceSeconds > 0 {
            return OpenAIStatusUptimeChartPalette.partialOutage
        }
        return OpenAIStatusUptimeChartPalette.operational
    }
}

private enum OpenAIStatusUptimeChartPalette {
    static let operational = Color.openAIStatusDynamic(
        light: (93, 172, 129),
        dark: (59, 122, 87)
    )
    static let partialOutage = Color.openAIStatusDynamic(
        light: (248, 181, 0),
        dark: (195, 128, 58)
    )
    static let majorOutage = Color.openAIStatusDynamic(
        light: (232, 48, 21),
        dark: (203, 27, 69)
    )
    static let noData = Color.openAIStatusDynamic(
        light: (189, 192, 186),
        dark: (54, 58, 50)
    )
}

private extension Color {
    static func openAIStatusDynamic(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        stxDynamic(
            light: (light.0 / 255, light.1 / 255, light.2 / 255),
            dark: (dark.0 / 255, dark.1 / 255, dark.2 / 255)
        )
    }

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

#if DEBUG
#Preview("OpenAI Status Card") {
    let env = AppEnvironment.preview()
    return OpenAIStatusCard(status: env.openAIStatus)
        .padding()
        .frame(width: 720)
        .background(Color.stxBackground)
}
#endif
