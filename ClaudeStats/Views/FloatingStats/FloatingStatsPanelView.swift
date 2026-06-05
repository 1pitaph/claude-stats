import SwiftUI

struct FloatingStatsPanelView: View {
    @Environment(AppEnvironment.self) private var env

    let state: FloatingStatsPanelState
    var onHoverChanged: (Bool) -> Void
    var onDragBegan: (CGPoint) -> Void
    var onDragMoved: (CGPoint) -> Void
    var onDragEnded: (CGPoint) -> Void

    var body: some View {
        let edge = state.edge
        GeometryReader { proxy in
            panelSurface(edge: edge, visibleSize: proxy.size)
        }
        .font(.sora(13))
        .tint(.stxAccent)
        .animation(.easeOut(duration: 0.16), value: state.edge)
        .animation(.easeOut(duration: 0.14), value: state.edgeReleaseProgress)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude Stats floating tab")
    }

    private func panelSurface(edge: FloatingPanelEdge, visibleSize: CGSize) -> some View {
        let currentSize = CGSize(
            width: max(visibleSize.width, 1),
            height: max(visibleSize.height, 1)
        )
        let shape = FloatingTabShape(
            edge: edge,
            cornerRadius: state.isExpanded ? 18 : 24,
            edgeReleaseProgress: state.edgeReleaseProgress
        )
        let collapsedSize = FloatingPanelGeometry.size(edge: edge, expanded: false)

        return ZStack(alignment: edge.dockedContentAlignment) {
            if state.expandedContentPhase.mountsExpandedContent {
                expandedContent
                    .opacity(state.expandedContentPhase.expandedContentOpacity)
                    .animation(.easeOut(duration: FloatingStatsContentAnimation.collapseFadeDuration), value: state.expandedContentPhase)
            }

            if state.showsCollapsedContent {
                collapsedContent(edge: edge, size: collapsedSize)
                    .frame(width: collapsedSize.width, height: collapsedSize.height)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.1), value: state.showsCollapsedContent)
        .animation(.easeOut(duration: 0.16), value: state.isExpanded)
        .frame(width: currentSize.width, height: currentSize.height)
        .background {
            shape.fill(.regularMaterial)
        }
        .clipShape(shape)
        .overlay(shape.stroke(Color.stxStroke, lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.dockedContentAlignment)
        .contentShape(Rectangle())
        .overlay(FloatingHoverTracker(onHoverChanged: onHoverChanged).accessibilityHidden(true))
    }

    private func collapsedContent(edge: FloatingPanelEdge, size: CGSize) -> some View {
        let title = env.preferences.selectedProvider.shortName.lowercased()
        return Group {
            if edge.isVertical {
                sideCollapsedTitle(title, edge: edge, size: size)
            } else {
                horizontalCollapsedTitle(title)
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Metrics.collapsedContentPadding)
            .overlay(dragHandle)
            .accessibilityHint("Hover to expand. Drag to snap to another screen edge.")
    }

    private func horizontalCollapsedTitle(_ title: String) -> some View {
        Text(title)
            .font(.sora(13, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func sideCollapsedTitle(_ title: String, edge: FloatingPanelEdge, size: CGSize) -> some View {
        let innerSize = CGSize(
            width: max(size.width - Metrics.collapsedContentPadding * 2, 1),
            height: max(size.height - Metrics.collapsedContentPadding * 2, 1)
        )

        return sideCollapsedTitleText(title)
            .frame(width: innerSize.height, height: innerSize.width)
            .rotationEffect(sideTitleRotation(for: edge))
            .frame(width: innerSize.width, height: innerSize.height)
            .accessibilityLabel(title)
    }

    private func sideCollapsedTitleText(_ title: String) -> some View {
        Text(title)
            .font(.sora(14, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func sideTitleRotation(for edge: FloatingPanelEdge) -> Angle {
        switch edge {
        case .right: .degrees(-90)
        case .left: .degrees(90)
        case .top, .bottom: .zero
        }
    }

    private var expandedContent: some View {
        let prefs = env.preferences
        let provider = prefs.selectedProvider
        let summary = env.store.summary(for: prefs.menuBarPeriod, provider: provider)

        return VStack(alignment: .leading, spacing: 10) {
            animatedExpandedSection(.header) {
                header(provider: provider, period: prefs.menuBarPeriod)
                    .overlay(dragHandle)
            }

            animatedExpandedSection(.rule) {
                StxRule()
            }

            animatedExpandedSection(.metrics) {
                HStack(alignment: .top, spacing: 10) {
                    metricBlock(title: "TOKENS", value: Format.tokens(summary.totalTokens(includingCacheRead: prefs.menuBarIncludesCache)))
                    metricBlock(title: "COST", value: Format.costEstimate(summary.totalCost(for: prefs.costEstimationMode),
                                                                          mode: prefs.costEstimationMode,
                                                                          usesCredits: summary.totalCostUsesCredits(for: prefs.costEstimationMode)))
                    metricBlock(title: "SESSIONS", value: "\(summary.sessionCount)")
                }
            }

            animatedExpandedSection(.status) {
                updatedStatusSection(provider: provider)
            }

            Spacer(minLength: 0)

            animatedExpandedSection(.actions) {
                actionButtons
            }
        }
        .padding(14)
        .task(id: provider) {
            await refreshProviderStatusIfNeeded(provider: provider)
        }
    }

    private func animatedExpandedSection<Content: View>(
        _ section: FloatingStatsContentSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .contentTransition(.opacity)
            .opacity(state.expandedContentPhase.showsSectionContent ? 1 : 0)
            .animation(expandedSectionAnimation(for: section), value: state.expandedContentPhase)
    }

    private func expandedSectionAnimation(for section: FloatingStatsContentSection) -> Animation {
        switch state.expandedContentPhase {
        case .revealing:
            FloatingStatsContentAnimation.revealAnimation(for: section)
        case .hiding:
            .easeOut(duration: FloatingStatsContentAnimation.collapseFadeDuration)
        case .hidden, .waitingToReveal, .visible:
            .easeOut(duration: FloatingStatsContentAnimation.sectionFadeDuration)
        }
    }

    private func updatedStatusSection(provider: ProviderKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            updatedText
            if let statusContent = floatingStatusContent(for: provider) {
                FloatingProviderStatusView(content: statusContent)
            }
        }
    }

    @ViewBuilder
    private var updatedText: some View {
        if let refreshed = env.store.lastRefreshedAt {
            Text("UPDATED \(Format.relativeDate(refreshed).uppercased())")
                .font(.sora(9, weight: .medium))
                .tracking(0.7)
                .foregroundStyle(Color.stxMuted)
        } else {
            Text(env.store.isLoading ? "SCANNING..." : "NOT UPDATED YET")
                .font(.sora(9, weight: .medium))
                .tracking(0.7)
                .foregroundStyle(Color.stxMuted)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 7) {
            FloatingStatsActionButton(symbol: env.store.isLoading ? "hourglass" : "arrow.clockwise", label: "Refresh") {
                Task { await env.store.refresh() }
            }
            .disabled(env.store.isLoading)

            FloatingStatsActionButton(symbol: AppIcon.Window.main, label: "Open main window") {
                NotificationCenter.default.post(name: .openMainWindowFromFloatingStats, object: nil)
            }

            FloatingStatsActionButton(symbol: AppIcon.Workspace.git, label: "Open Git") {
                NotificationCenter.default.post(
                    name: .openMainWindowDestinationFromFloatingStats,
                    object: FloatingStatsMainWindowDestination.page(.git)
                )
            }

            #if !CLAUDE_STATS_LITE
            FloatingStatsActionButton(symbol: AppIcon.Workspace.warp, label: "Open Warp") {
                NotificationCenter.default.post(
                    name: .openMainWindowDestinationFromFloatingStats,
                    object: FloatingStatsMainWindowDestination.warp
                )
            }

            FloatingStatsActionButton(symbol: AppIcon.Workspace.network, label: "Open Network") {
                NotificationCenter.default.post(
                    name: .openMainWindowDestinationFromFloatingStats,
                    object: FloatingStatsMainWindowDestination.network
                )
            }
            #endif

            FloatingStatsActionButton(symbol: AppIcon.Workspace.settings, label: "Open settings") {
                NotificationCenter.default.post(name: .openSettingsFromFloatingStats, object: nil)
            }
        }
    }

    private func header(provider: ProviderKind, period: StatsPeriod) -> some View {
        HStack(spacing: 9) {
            Image(provider.monochromeAssetName)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(providerLogoTint(for: provider))
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.sora(13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(period.displayName.uppercased())
                    .font(.sora(9, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 8)
            Image(systemName: AppIcon.Navigation.move)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityHint("Drag to move the floating tab")
    }

    private func providerLogoTint(for provider: ProviderKind) -> Color {
        switch provider {
        case .codex, .kimi:
            Color.primary
        case .claude, .gemini, .minimax:
            provider.accentColor
        }
    }

    private func floatingStatusContent(for provider: ProviderKind) -> FloatingProviderStatusContent? {
        switch provider {
        case .claude:
            if let summary = ClaudeFloatingStatusAdapter.summary(from: env.claudeStatus) {
                return .summary(summary)
            }
            return floatingStatusMessage(
                isLoading: env.claudeStatus.isLoading,
                primaryError: env.claudeStatus.lastError,
                secondaryError: env.claudeStatus.uptimeLastError,
                fallback: "CLAUDE STATUS UNAVAILABLE"
            )
        case .codex:
            if let summary = OpenAIFloatingStatusAdapter.summary(from: env.openAIStatus) {
                return .summary(summary)
            }
            return floatingStatusMessage(
                isLoading: env.openAIStatus.isLoading,
                primaryError: env.openAIStatus.lastError,
                secondaryError: env.openAIStatus.uptimeLastError,
                fallback: "OPENAI STATUS UNAVAILABLE"
            )
        case .gemini, .kimi, .minimax:
            return nil
        }
    }

    private func floatingStatusMessage(
        isLoading: Bool,
        primaryError: String?,
        secondaryError: String?,
        fallback: String
    ) -> FloatingProviderStatusContent {
        if isLoading {
            return .message("CHECKING STATUS...")
        }
        if let error = primaryError ?? secondaryError {
            return .message(error)
        }
        return .message(fallback)
    }

    private func refreshProviderStatusIfNeeded(provider: ProviderKind) async {
        switch provider {
        case .claude:
            await env.claudeStatus.refreshIfNeeded()
        case .codex:
            await env.openAIStatus.refreshIfNeeded()
        case .gemini, .kimi, .minimax:
            return
        }
    }

    private func metricBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.sora(8, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(15, weight: .semibold))
                .monospacedDigit()
                .stxNumericValueTransition(value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dragHandle: some View {
        FloatingDragHandle(
            onDragBegan: onDragBegan,
            onDragMoved: onDragMoved,
            onDragEnded: onDragEnded
        )
        .accessibilityHidden(true)
    }

    private enum Metrics {
        static let collapsedContentPadding: CGFloat = 8
    }
}

private extension FloatingPanelEdge {
    var dockedContentAlignment: Alignment {
        switch self {
        case .left:
            .leading
        case .right:
            .trailing
        case .top:
            .top
        case .bottom:
            .bottom
        }
    }
}

private struct FloatingTabShape: Shape {
    let edge: FloatingPanelEdge
    let cornerRadius: CGFloat
    var edgeReleaseProgress: CGFloat

    var animatableData: CGFloat {
        get { edgeReleaseProgress }
        set { edgeReleaseProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let dockedRadius = r * min(max(edgeReleaseProgress, 0), 1)
        let radii = cornerRadii(exposedRadius: r, dockedRadius: dockedRadius)
        return roundedRectPath(in: rect, radii: radii)
    }

    private func cornerRadii(exposedRadius: CGFloat, dockedRadius: CGFloat) -> CornerRadii {
        switch edge {
        case .right:
            CornerRadii(
                topLeft: exposedRadius,
                topRight: dockedRadius,
                bottomRight: dockedRadius,
                bottomLeft: exposedRadius
            )
        case .left:
            CornerRadii(
                topLeft: dockedRadius,
                topRight: exposedRadius,
                bottomRight: exposedRadius,
                bottomLeft: dockedRadius
            )
        case .top:
            CornerRadii(
                topLeft: dockedRadius,
                topRight: dockedRadius,
                bottomRight: exposedRadius,
                bottomLeft: exposedRadius
            )
        case .bottom:
            CornerRadii(
                topLeft: exposedRadius,
                topRight: exposedRadius,
                bottomRight: dockedRadius,
                bottomLeft: dockedRadius
            )
        }
    }

    private func roundedRectPath(in rect: CGRect, radii: CornerRadii) -> Path {
        let maximumRadius = min(rect.width, rect.height) / 2
        let topLeft = min(radii.topLeft, maximumRadius)
        let topRight = min(radii.topRight, maximumRadius)
        let bottomRight = min(radii.bottomRight, maximumRadius)
        let bottomLeft = min(radii.bottomLeft, maximumRadius)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + topRight), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addQuadCurve(to: CGPoint(x: rect.minX + topLeft, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))

        path.closeSubpath()
        return path
    }

    private struct CornerRadii {
        var topLeft: CGFloat
        var topRight: CGFloat
        var bottomRight: CGFloat
        var bottomLeft: CGFloat
    }
}

#if DEBUG
#Preview("Floating tab") {
    VStack(spacing: 24) {
        FloatingStatsPanelView(
            state: {
                let state = FloatingStatsPanelState()
                state.edge = .right
                return state
            }(),
            onHoverChanged: { _ in },
            onDragBegan: { _ in },
            onDragMoved: { _ in },
            onDragEnded: { _ in }
        )
        .environment(AppEnvironment.preview())

        FloatingStatsPanelView(
            state: {
                let state = FloatingStatsPanelState()
                state.edge = .right
                state.isExpanded = true
                state.expandedContentPhase = .visible
                state.showsCollapsedContent = false
                return state
            }(),
            onHoverChanged: { _ in },
            onDragBegan: { _ in },
            onDragMoved: { _ in },
            onDragEnded: { _ in }
        )
        .environment(AppEnvironment.preview())
    }
    .padding(40)
}
#endif
