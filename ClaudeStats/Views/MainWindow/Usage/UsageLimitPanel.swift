import SwiftUI

struct UsageLimitPanel: View {
    let provider: ProviderKind
    let report: UsageLimitReport?
    let isLoading: Bool
    let actionMessage: String?
    let visibleWindowIDs: Set<String>?
    let forecasts: [UsageLimitForecast]
    let onRefresh: () -> Void
    let onInstallClaudeBridge: (() -> Void)?
    let onCopyClaudeSettingsSnippet: (() -> Void)?
    let onOpenClaudeSettings: (() -> Void)?
    let claudeDesktopPermissionIssue: ClaudeDesktopUsagePermissionIssue?
    let onReadClaudeDesktop: (() -> Void)?
    let onOpenAccessibilitySettings: (() -> Void)?
    let onOpenScreenRecordingSettings: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .mainUsagePanel(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            L10n.format("usage.limit.accessibility.provider_limits",
                        defaultValue: "%@ usage limits",
                        provider.shortName)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("USAGE LIMITS")
                .font(.sora(13, weight: .semibold))
                .tracking(1.0)
            statusBadge
            Spacer(minLength: 12)
            if let label = updatedLabel {
                Text(label)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
            }
            Button(action: onRefresh) {
                Image(systemName: AppIcon.Action.refresh)
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxMuted)
            .help(L10n.string("usage.limit.refresh", defaultValue: "Refresh usage limits"))
            if provider == .claude, let onReadClaudeDesktop {
                Button(action: onReadClaudeDesktop) {
                    Image(systemName: AppIcon.Text.viewfinder)
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxMuted)
                .disabled(isLoading)
                .help("Read Claude Desktop")
                .accessibilityLabel("Read Claude Desktop")
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let status = report?.status ?? (isLoading ? .waitingForNextResponse : .unsupported)
        HStack(spacing: 5) {
            Circle()
                .fill(tint(for: status))
                .frame(width: 6, height: 6)
            Text(label(for: status))
                .font(.sora(9, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint(for: status))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint(for: status).opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var content: some View {
        if let report {
            switch report.status {
            case .fresh, .cached:
                if let snapshot = report.snapshot {
                    limitWindows(displayedWindows(snapshot.windows))
                    sourceFooter(snapshot: snapshot)
                    if provider == .claude {
                        claudeDesktopPermissionButtons
                    }
                }
            case .setupRequired where provider == .claude:
                setupRequiredContent(message: report.message)
            case .waitingForNextResponse:
                waitingContent(report: report)
            case .unavailable:
                stateContent(
                    systemImage: AppIcon.Status.warningFilled,
                    title: L10n.string("usage.limit.unavailable_title",
                                       defaultValue: "Usage limits unavailable"),
                    message: report.message,
                    lastCapturedAt: report.lastCapturedAt
                )
            case .setupRequired:
                stateContent(
                    systemImage: AppIcon.Status.maintenance,
                    title: L10n.string("usage.limit.setup_required_title",
                                       defaultValue: "Setup required"),
                    message: report.message,
                    lastCapturedAt: report.lastCapturedAt
                )
            case .unsupported:
                EmptyView()
            }
        } else {
            stateContent(
                systemImage: AppIcon.Status.history,
                title: isLoading
                    ? L10n.string("usage.limit.checking_title", defaultValue: "Checking usage limits")
                    : L10n.string("usage.limit.not_loaded_title", defaultValue: "Usage limits not loaded"),
                message: nil,
                lastCapturedAt: nil
            )
        }
        if let actionMessage {
            StxRule()
            Text(actionMessage)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func displayedWindows(_ windows: [UsageLimitWindow]) -> [UsageLimitWindow] {
        guard provider == .claude, let visibleWindowIDs else { return windows }
        return UsageLimitWindowCatalog.visibleClaudeWindows(windows, visibleWindowIDs: visibleWindowIDs)
    }

    private func limitWindows(_ windows: [UsageLimitWindow]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 320), spacing: 24, alignment: .top)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(windows.map { window in
                UsageLimitWindowCardModel(
                    window: window,
                    forecast: forecasts.forecast(for: provider, windowID: window.id)
                )
            }) { model in
                UsageLimitWindowCard(model: model)
                    .equatable()
            }
        }
    }

    private func setupRequiredContent(message: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            stateContent(
                systemImage: AppIcon.Runtime.terminalFilled,
                title: L10n.string("usage.limit.connect_usage_sources",
                                   defaultValue: "Connect Claude usage sources"),
                message: message,
                lastCapturedAt: nil
            )
            claudeDesktopPermissionButtons
            claudeBridgeButtons
        }
    }

    @ViewBuilder
    private func waitingContent(report: UsageLimitReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            stateContent(
                systemImage: AppIcon.Status.history,
                title: L10n.format("usage.limit.waiting_for_response",
                                   defaultValue: "Waiting for the next %@ response",
                                   provider.shortName),
                message: report.message,
                lastCapturedAt: report.lastCapturedAt
            )
            if provider == .claude {
                claudeDesktopPermissionButtons
            }
        }
    }

    @ViewBuilder
    private var claudeBridgeButtons: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            if let onInstallClaudeBridge {
                Button("Install bridge", action: onInstallClaudeBridge)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if let onCopyClaudeSettingsSnippet {
                Button("Copy settings snippet", action: onCopyClaudeSettingsSnippet)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if let onOpenClaudeSettings {
                Button("Open Claude settings", action: onOpenClaudeSettings)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var claudeDesktopPermissionButtons: some View {
        switch claudeDesktopPermissionIssue {
        case .accessibility:
            if let onOpenAccessibilitySettings {
                Button("Open Accessibility settings", action: onOpenAccessibilitySettings)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        case .screenRecording:
            if let onOpenScreenRecordingSettings {
                Button("Open Screen Recording settings", action: onOpenScreenRecordingSettings)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        case nil:
            EmptyView()
        }
    }

    private func stateContent(systemImage: String, title: String, message: String?, lastCapturedAt: Date?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(.sora(12, weight: .semibold))
                    .foregroundStyle(.primary)
                if let message {
                    Text(LocalizedStringKey(message))
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let lastCapturedAt {
                    Text(L10n.format("usage.limit.last_snapshot",
                                     defaultValue: "Last snapshot %@",
                                     Format.relativeDate(lastCapturedAt)))
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func sourceFooter(snapshot: UsageLimitSnapshot) -> some View {
        HStack(spacing: 8) {
            Text(snapshot.sourceLabel)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
            if let planType = snapshot.planType {
                Text(planType)
                    .font(.sora(9, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private var updatedLabel: String? {
        guard let capturedAt = report?.lastCapturedAt else { return nil }
        return L10n.format("usage.limit.updated",
                           defaultValue: "Updated %@",
                           Format.relativeDate(capturedAt))
    }

    private func label(for status: UsageLimitStatus) -> String {
        switch status {
        case .fresh:
            L10n.string("usage.limit.status.fresh", defaultValue: "FRESH")
        case .cached:
            L10n.string("usage.limit.status.cached", defaultValue: "CACHED")
        case .setupRequired:
            L10n.string("usage.limit.status.setup", defaultValue: "SETUP")
        case .waitingForNextResponse:
            L10n.string("usage.limit.status.waiting", defaultValue: "WAITING")
        case .unavailable:
            L10n.string("usage.limit.status.unavailable", defaultValue: "UNAVAILABLE")
        case .unsupported:
            L10n.string("usage.limit.status.unsupported", defaultValue: "UNSUPPORTED")
        }
    }

    private func tint(for status: UsageLimitStatus) -> Color {
        switch status {
        case .fresh:
            Color.green
        case .cached:
            Color.stxMuted
        case .setupRequired:
            Color.blue
        case .waitingForNextResponse:
            Color.orange
        case .unavailable:
            Color.red
        case .unsupported:
            Color.stxMuted
        }
    }
}

struct UsageLimitSegmentLayout: Equatable, Sendable {
    static let defaultSegmentCount = 28

    let usedPercent: Double
    let segmentCount: Int

    init(usedPercent: Double, segmentCount: Int = Self.defaultSegmentCount) {
        self.usedPercent = usedPercent
        self.segmentCount = max(1, segmentCount)
    }

    var clampedUsedPercent: Double {
        min(100, max(0, usedPercent))
    }

    var usedSegmentCount: Int {
        guard clampedUsedPercent > 0 else { return 0 }
        let rawCount = (clampedUsedPercent / 100) * Double(segmentCount)
        return min(segmentCount, max(1, Int(rawCount.rounded(.up))))
    }

    var remainingSegmentCount: Int {
        segmentCount - usedSegmentCount
    }
}

struct UsageLimitWindowCardModel: Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let resetText: String
    let remainingText: String
    let usedText: String
    let accessibilityValue: String
    let segmentLayout: UsageLimitSegmentLayout
    let tintLevel: UsageLimitTintLevel
    let forecastText: String?
    let forecastDetailText: String?
    let forecastTintLevel: UsageLimitForecastTintLevel?

    init(window: UsageLimitWindow, forecast: UsageLimitForecast? = nil) {
        let remainingText = Format.percentPoints(window.remainingPercent)
        let usedText = Format.percentPoints(window.clampedUsedPercent)
        let resetText = window.resetAt.map {
            L10n.format("usage.limit.resets", defaultValue: "Resets %@", Format.relativeDate($0))
        } ?? L10n.string("usage.limit.reset_unknown", defaultValue: "Reset unknown")
        let forecastSummary = forecast.map(Self.forecastSummary)

        self.id = window.id
        self.label = window.label
        self.resetText = resetText
        self.remainingText = remainingText
        self.usedText = L10n.format("usage.limit.used_value", defaultValue: "%@ used", usedText)
        let baseAccessibilityValue = L10n.format("usage.limit.window_accessibility",
                                                 defaultValue: "%@ remaining, %@ used, %@",
                                                 remainingText,
                                                 usedText,
                                                 resetText)
        self.accessibilityValue = [baseAccessibilityValue, forecastSummary?.accessibilityText]
            .compactMap { $0 }
            .joined(separator: ", ")
        self.segmentLayout = UsageLimitSegmentLayout(usedPercent: window.clampedUsedPercent)
        self.tintLevel = UsageLimitTintLevel(remainingPercent: window.remainingPercent)
        self.forecastText = forecastSummary?.title
        self.forecastDetailText = forecastSummary?.detail
        self.forecastTintLevel = forecastSummary?.tintLevel
    }

    private static func forecastSummary(_ forecast: UsageLimitForecast) -> ForecastSummary {
        switch forecast.status {
        case .forecast:
            if let interval = forecast.reachInterval {
                let title = "\(forecast.horizon.displayText) ETA \(Format.shortTime(interval.start))-\(Format.shortTime(interval.end))"
                let median = forecast.medianReachAt.map { "Median \(Format.shortTime($0))" }
                let detail = [median, forecast.confidence.displayText].compactMap { $0 }.joined(separator: " · ")
                return ForecastSummary(title: title, detail: detail, tintLevel: .forecast)
            }
            return ForecastSummary(title: "Prediction unavailable", detail: forecast.diagnostics.first, tintLevel: .unavailable)
        case .collecting:
            return ForecastSummary(
                title: "\(forecast.horizon.displayText) prediction collecting data",
                detail: forecast.diagnostics.first ?? "Needs more \(forecast.horizon.displayText) usage snapshots.",
                tintLevel: .collecting
            )
        case .willNotReachBeforeReset:
            let reset = forecast.resetAt.map { "Before reset \(Format.relativeDate($0))" }
            return ForecastSummary(title: "No \(forecast.horizon.displayText) limit hit expected", detail: reset ?? forecast.diagnostics.first, tintLevel: .safe)
        case .limitReached:
            return ForecastSummary(title: "\(forecast.horizon.displayText) limit reached", detail: forecast.diagnostics.first, tintLevel: .unavailable)
        case .unavailable:
            return ForecastSummary(title: "\(forecast.horizon.displayText) prediction unavailable", detail: forecast.diagnostics.first, tintLevel: .unavailable)
        }
    }

    private struct ForecastSummary {
        let title: String
        let detail: String?
        let tintLevel: UsageLimitForecastTintLevel

        var accessibilityText: String {
            [title, detail].compactMap { $0 }.joined(separator: ", ")
        }
    }
}

enum UsageLimitTintLevel: Equatable, Sendable {
    case healthy
    case warning
    case critical

    init(remainingPercent: Double) {
        switch remainingPercent {
        case let remaining where remaining > 50:
            self = .healthy
        case 20...50:
            self = .warning
        default:
            self = .critical
        }
    }

    var color: Color {
        switch self {
        case .healthy:
            Color.green
        case .warning:
            Color.orange
        case .critical:
            Color.red
        }
    }
}

enum UsageLimitForecastTintLevel: Equatable, Sendable {
    case forecast
    case collecting
    case safe
    case unavailable

    var color: Color {
        switch self {
        case .forecast:
            Color.orange
        case .collecting:
            Color.blue
        case .safe:
            Color.green
        case .unavailable:
            Color.stxMuted
        }
    }
}

extension UsageLimitForecastConfidence {
    var displayText: String {
        switch self {
        case .low:
            "Low confidence"
        case .medium:
            "Medium confidence"
        case .high:
            "High confidence"
        }
    }
}

private struct UsageLimitWindowCard: View, Equatable {
    let model: UsageLimitWindowCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.label)
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                Text(model.resetText)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.remainingText)
                    .font(.sora(24, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .stxNumericValueTransition(value: model.remainingText)
                Text("left")
                    .font(.sora(11, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                Text(model.usedText)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            UsageLimitSegmentStrip(
                layout: model.segmentLayout,
                remainingTint: model.tintLevel.color
            )

            if let forecastText = model.forecastText,
               let forecastTintLevel = model.forecastTintLevel {
                UsageLimitForecastSummaryView(
                    title: forecastText,
                    detail: model.forecastDetailText,
                    tint: forecastTintLevel.color
                )
            }

            HStack(spacing: 10) {
                UsageLimitSegmentLegendItem(label: L10n.string("usage.limit.left", defaultValue: "Left"), tint: model.tintLevel.color, style: .solid)
                UsageLimitSegmentLegendItem(label: L10n.string("usage.limit.used", defaultValue: "Used"), tint: Color.primary.opacity(0.34), style: .hatched)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("usage.limit.window_label",
                                        defaultValue: "%@ usage limit",
                                        model.label))
        .accessibilityValue(model.accessibilityValue)
    }
}

private struct UsageLimitForecastSummaryView: View {
    let title: String
    let detail: String?
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(title)
                .font(.sora(10, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct UsageLimitSegmentStrip: View {
    let layout: UsageLimitSegmentLayout
    let remainingTint: Color

    private let segmentSpacing: CGFloat = 4
    private let segmentHeight: CGFloat = 34
    private let segmentCornerRadius: CGFloat = 1.5
    private let usedBaseTint = Color.primary.opacity(0.12)
    private let usedStripeTint = Color.primary.opacity(0.34)

    var body: some View {
        Canvas { context, size in
            let totalSpacing = CGFloat(layout.segmentCount - 1) * segmentSpacing
            let segmentWidth = (size.width - totalSpacing) / CGFloat(layout.segmentCount)
            guard segmentWidth > 0, size.height > 0 else { return }

            for index in 0..<layout.segmentCount {
                let origin = CGPoint(x: CGFloat(index) * (segmentWidth + segmentSpacing), y: 0)
                let rect = CGRect(origin: origin, size: CGSize(width: segmentWidth, height: size.height))
                let cornerRadius = min(segmentCornerRadius, segmentWidth / 2, size.height / 2)
                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

                if index < layout.remainingSegmentCount {
                    context.fill(path, with: .color(remainingTint))
                } else {
                    context.fill(path, with: .color(usedBaseTint))
                    drawUsedStripes(in: rect, clippedTo: path, context: context)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: segmentHeight)
        .accessibilityHidden(true)
    }

    private func drawUsedStripes(in rect: CGRect, clippedTo clippingPath: Path, context: GraphicsContext) {
        var stripeContext = context
        stripeContext.clip(to: clippingPath)

        var stripePath = Path()
        var startX = rect.minX - rect.height
        while startX < rect.maxX {
            stripePath.move(to: CGPoint(x: startX, y: rect.maxY))
            stripePath.addLine(to: CGPoint(x: startX + rect.height, y: rect.minY))
            startX += 6
        }

        stripeContext.stroke(
            stripePath,
            with: .color(usedStripeTint),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
        )
    }
}

private struct UsageLimitSegmentLegendItem: View {
    enum Style {
        case solid
        case hatched
    }

    let label: String
    let tint: Color
    let style: Style

    var body: some View {
        HStack(spacing: 5) {
            Group {
                switch style {
                case .solid:
                    Rectangle()
                        .fill(tint)
                case .hatched:
                    UsageLimitHatchedSwatch()
                }
            }
            .frame(width: 8, height: 8)
            Text(label)
                .font(.sora(9))
                .foregroundStyle(Color.stxMuted)
        }
        .accessibilityHidden(true)
    }
}

private struct UsageLimitHatchedSwatch: View {
    private let baseTint = Color.primary.opacity(0.12)
    private let stripeTint = Color.primary.opacity(0.34)

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let path = Path(roundedRect: rect, cornerRadius: 1.5)
            context.fill(path, with: .color(baseTint))

            var stripeContext = context
            stripeContext.clip(to: path)

            var stripes = Path()
            var startX = rect.minX - rect.height
            while startX < rect.maxX {
                stripes.move(to: CGPoint(x: startX, y: rect.maxY))
                stripes.addLine(to: CGPoint(x: startX + rect.height, y: rect.minY))
                startX += 5
            }

            stripeContext.stroke(stripes, with: .color(stripeTint), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        }
    }
}

#if DEBUG
#Preview {
    UsageLimitPanel(
        provider: .codex,
        report: .fresh(
            provider: .codex,
            snapshot: UsageLimitSnapshot(
                provider: .codex,
                windows: [
                    UsageLimitWindow(id: "primary", label: "5h", usedPercent: 38, resetAt: Date().addingTimeInterval(2_400), windowMinutes: 300),
                    UsageLimitWindow(id: "secondary", label: "7d", usedPercent: 12, resetAt: Date().addingTimeInterval(400_000), windowMinutes: 10_080),
                ],
                capturedAt: Date().addingTimeInterval(-120),
                sourceLabel: "Codex rollout",
                sourcePath: nil,
                planType: "pro",
                limitID: "codex"
            )
        ),
        isLoading: false,
        actionMessage: nil,
        visibleWindowIDs: nil,
        forecasts: [
            UsageLimitForecast(
                provider: .codex,
                windowID: "secondary",
                label: "7d",
                capturedAt: Date().addingTimeInterval(-120),
                currentUsedPercent: 12,
                resetAt: Date().addingTimeInterval(400_000),
                reachInterval: DateInterval(start: Date().addingTimeInterval(22_000), end: Date().addingTimeInterval(32_000)),
                medianReachAt: Date().addingTimeInterval(26_000),
                confidence: .medium,
                status: .forecast,
                diagnostics: []
            ),
        ],
        onRefresh: {},
        onInstallClaudeBridge: nil,
        onCopyClaudeSettingsSnippet: nil,
        onOpenClaudeSettings: nil,
        claudeDesktopPermissionIssue: nil,
        onReadClaudeDesktop: nil,
        onOpenAccessibilitySettings: nil,
        onOpenScreenRecordingSettings: nil
    )
    .padding(24)
    .frame(width: 760)
    .background(Color.stxBackground)
}
#endif
