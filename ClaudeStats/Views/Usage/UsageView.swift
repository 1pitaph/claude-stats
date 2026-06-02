import SwiftUI
import Charts

struct UsageView: View {
    /// Frozen chart settings for an exported panel — the share window's choices,
    /// since the export view can't carry the interactive view model's state.
    struct ExportConfig: Hashable {
        var period: PeriodSelection
        var chartStyle: TrendChartStyle = .line
        var useLog: Bool = false
        var stackByType: Bool = false
    }

    /// `interactive` is the normal in-panel view; `export` drives the summary
    /// and chart settings from a fixed ``ExportConfig`` and renders a static
    /// (non-scrolling) body so it can be captured by `ImageRenderer`.
    enum Mode: Hashable { case interactive, export(ExportConfig) }

    @Environment(AppEnvironment.self) private var env
    @State private var vm = UsageViewModel()
    var mode: Mode = .interactive

    private var exportConfig: ExportConfig? {
        if case .export(let config) = mode { return config }
        return nil
    }

    var body: some View {
        @Bindable var vm = vm
        let provider = env.preferences.selectedProvider
        let derivedData = exportConfig == nil
            ? vm.displayedDerivedData(provider: provider, lastRefreshedAt: env.store.lastRefreshedAt)
            : nil
        let summary = exportConfig.map { env.store.summary(for: $0.period, provider: provider) }
            ?? derivedData?.summary
            ?? UsageSummary.empty(period: vm.period)
        let series = exportConfig == nil
            ? (derivedData?.series ?? summary.trendSeries())
            : summary.trendSeries()
        let cacheHitRate = exportConfig == nil
            ? derivedData?.cacheHitRate
            : env.store.cacheHitRate(for: summary.totalUsage, provider: provider)
        let isHourly = series.granularity == .hour
        let style: TrendChartStyle = isHourly ? .line : (exportConfig?.chartStyle ?? vm.chartStyle)
        let stackByType = exportConfig?.stackByType ?? vm.stackByType
        let useLog = style == .line && !stackByType && (exportConfig?.useLog ?? (vm.scaleMode == .log))
        let interactive = exportConfig == nil
        let rangeID = exportConfig.map { rangeIdentifier(for: $0.period) } ?? vm.period.rawValue

        let content = VStack(alignment: .leading, spacing: 16) {
            if interactive {
                HStack(spacing: 0) {
                    ForEach(Array(StatsPeriod.allCases.enumerated()), id: \.element) { idx, p in
                        if idx > 0 { Spacer(minLength: 8) }
                        PeriodTab(period: p, isSelected: vm.period == p) { vm.period = p }
                    }
                }
            }

            statGrid(summary)
            breakdownPanel(summary, series: series, rangeID: rangeID, isHourly: isHourly, style: style, useLog: useLog,
                           stackByType: stackByType,
                           interactive: interactive, exportPeriod: exportConfig?.period)
            cacheStats(summary, cacheHitRate: cacheHitRate)
            modelBreakdown(summary, series: series)
        }
        .padding(14)

        if interactive {
            AppScrollView { content }
                .onAppear { refreshDerivedData() }
                .onChange(of: usageDataKey) { _, _ in refreshDerivedData() }
        } else {
            content
        }
    }

    private func rangeIdentifier(for selection: PeriodSelection) -> String {
        switch selection {
        case .preset(let period):
            return period.rawValue
        case .custom(let start, let end):
            return "custom|\(start.timeIntervalSinceReferenceDate)|\(end.timeIntervalSinceReferenceDate)"
        }
    }

    private func periodReadout(_ selection: PeriodSelection) -> some View {
        BracketBox(spacing: 7) {
            Text("PERIOD:")
                .font(.sora(9))
                .tracking(0.4)
                .foregroundStyle(Color.stxMuted)
            Text(selection.label())
                .font(.sora(11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Stat readouts

    private func statGrid(_ s: UsageSummary) -> some View {
        let includeCache = env.preferences.includeCacheInTokens
        let costMode = env.preferences.costEstimationMode
        return Grid(horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                statCell(L10n.string("usage.stat.tokens", defaultValue: "TOKENS"),
                         Format.tokens(s.totalTokens(includingCacheRead: includeCache)))
                statCell(L10n.string("usage.stat.estimated_cost", defaultValue: "EST. COST"),
                         Format.cost(s.totalCost(for: costMode)))
            }
            GridRow {
                statCell(L10n.string("usage.stat.sessions", defaultValue: "SESSIONS"), "\(s.sessionCount)")
                statCell(L10n.string("usage.stat.messages", defaultValue: "MESSAGES"), Format.tokens(s.messageCount))
            }
        }
    }

    /// Cache-efficiency row shown directly above the BY MODEL list — hit rate
    /// plus the raw cache-read token volume the rate is based on.
    private func cacheStats(_ s: UsageSummary, cacheHitRate: Double?) -> some View {
        let usage = s.totalUsage
        let hitText = cacheHitRate.map(Format.percent) ?? "—"
        return Grid(horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                statCell(L10n.string("usage.stat.cache_hit", defaultValue: "CACHE HIT"), hitText)
                statCell(L10n.string("usage.stat.cached", defaultValue: "CACHED"), Format.tokens(usage.cacheReadTokens))
            }
        }
    }

    private var usageDataKey: UsageDerivedData.Key {
        UsageDerivedData.Key(
            period: vm.period,
            selectedDay: UsageDailyDateNavigator.normalized(vm.selectedDay),
            provider: env.preferences.selectedProvider,
            lastRefreshedAt: env.store.lastRefreshedAt
        )
    }

    private func refreshDerivedData() {
        vm.refreshDerivedData(
            from: env.store,
            provider: env.preferences.selectedProvider,
            lastRefreshedAt: env.store.lastRefreshedAt
        )
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        BracketBox(spacing: 7) {
            Text("\(title):")
                .font(.sora(9))
                .tracking(0.4)
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .layoutPriority(-1)
            Text(value)
                .font(.sora(13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .stxNumericValueTransition(value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }

    // MARK: Trend chart

    @ViewBuilder
    private func breakdownPanel(_ s: UsageSummary, series: TrendSeries, rangeID: String, isHourly: Bool, style: TrendChartStyle, useLog: Bool, stackByType: Bool, interactive: Bool, exportPeriod: PeriodSelection?) -> some View {
        let snapshot = UsageTrendChartSnapshot(
            series: series,
            rangeID: rangeID,
            transitionScopeID: env.preferences.selectedProvider.rawValue,
            style: style,
            useLog: useLog,
            stackByType: stackByType,
            displayName: { $0 }
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("BREAKDOWN")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.primary)
                Spacer()
                if interactive && !snapshot.isEmpty {
                    trendControls(style: style, stackByType: stackByType, showStyleToggle: !isHourly)
                }
            }
            Text(captionText(isHourly: isHourly, style: style, useLog: useLog, stackByType: stackByType, annotate: !interactive))
                .font(.sora(9))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)

            UsageTrendChartView(
                snapshot: snapshot,
                chartHeight: 150,
                emptyMessage: isHourly
                    ? L10n.string("usage.empty.today", defaultValue: "No usage today yet.")
                    : L10n.string("usage.empty.period", defaultValue: "No usage for this period."),
                axisFontSize: 8,
                barCornerRadius: 0
            ) {
                legend(snapshot.legendEntries)
            }

            if let exportPeriod {
                StxRule()
                periodReadout(exportPeriod)
            }
        }
        .stxPanel(12)
    }

    private func captionText(isHourly: Bool, style: TrendChartStyle, useLog: Bool, stackByType: Bool, annotate: Bool) -> String {
        var parts = [
            isHourly
                ? L10n.string("usage.caption.tokens_today_hourly", defaultValue: "TOKENS TODAY · HOURLY")
                : L10n.string("usage.caption.tokens_per_day", defaultValue: "TOKENS PER DAY")
        ]
        if annotate {
            parts.append(style == .bar
                         ? L10n.string("usage.caption.bars", defaultValue: "BARS")
                         : L10n.string("usage.caption.line", defaultValue: "LINE"))
            if stackByType { parts.append(L10n.string("usage.caption.stacked_by_type", defaultValue: "STACKED BY TYPE")) }
            if useLog { parts.append(L10n.string("usage.caption.ln_scale", defaultValue: "LN SCALE")) }
        }
        return parts.joined(separator: L10n.string("separator.dot", defaultValue: " · "))
    }

    private func legend(_ entries: [UsageTrendLegendEntry]) -> some View {
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], alignment: .leading, spacing: 4) {
            ForEach(entries) { entry in
                BracketBox(spacing: 6) {
                    Rectangle().fill(entry.color).frame(width: 7, height: 7)
                    Text(entry.label)
                        .font(.sora(9))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func trendControls(style: TrendChartStyle, stackByType: Bool, showStyleToggle: Bool) -> some View {
        HStack(spacing: 6) {
            if style == .line && !stackByType {
                controlButton(
                    systemName: "function",
                    active: vm.scaleMode == .log,
                    help: "Compress large gaps between models (ln scale)"
                ) {
                    vm.scaleMode = vm.scaleMode == .linear ? .log : .linear
                }
            }
            controlButton(
                systemName: "square.stack.3d.up.fill",
                active: stackByType,
                help: stackByType
                    ? "Stop stacking — show one series per model"
                    : "Stack by token type (Input / Output / Cache)"
            ) {
                vm.stackByType.toggle()
            }
            if showStyleToggle {
                controlButton(
                    systemName: vm.chartStyle == .line ? "chart.xyaxis.line" : "chart.bar.xaxis",
                    active: false,
                    help: vm.chartStyle == .line ? "Switch to bar chart" : "Switch to line chart"
                ) {
                    vm.chartStyle = vm.chartStyle == .line ? .bar : .line
                }
            }
        }
    }

    private struct PeriodTab: View {
        let period: StatsPeriod
        let isSelected: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                VStack(spacing: 4) {
                    Text(period.displayName)
                        .font(.sora(10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                    Rectangle()
                        .fill(Color.stxAccent)
                        .frame(height: 1.5)
                        .scaleEffect(x: isSelected ? 1 : 0, anchor: .leading)
                }
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(UsageTrendMotion.periodChip, value: isSelected)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var textColor: Color {
            if isSelected { return .primary }
            return hovering ? .primary : Color.primary.opacity(0.40)
        }
    }

    private func controlButton(systemName: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BracketBox(spacing: 3) {
                Image(systemName: systemName).font(.system(size: 9, weight: .bold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.stxAccent : Color.stxMuted)
        .help(help)
    }

    // MARK: Per-model breakdown

    @ViewBuilder
    private func modelBreakdown(_ s: UsageSummary, series: TrendSeries) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BY MODEL")
                .font(.sora(11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Color.stxMuted)
            if s.models.isEmpty {
                Text("No usage recorded for this period.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted.opacity(0.7))
            } else {
                let includeCache = env.preferences.includeCacheInTokens
                let costMode = env.preferences.costEstimationMode
                let maxTokens = max(1, s.models.map { $0.usage.total(includingCacheRead: includeCache) }.max() ?? 1)
                ForEach(Array(s.models.enumerated()), id: \.element.id) { idx, model in
                    let color = ModelPalette.color(at: series.models.firstIndex(of: model.model) ?? idx)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Rectangle().fill(color).frame(width: 7, height: 7)
                            Text(model.model)
                                .font(.sora(10))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(Format.tokens(model.usage.total(includingCacheRead: includeCache)))
                                .font(.sora(10).monospacedDigit())
                                .stxNumericValueTransition(value: Format.tokens(model.usage.total(includingCacheRead: includeCache)))
                                .foregroundStyle(.primary)
                            Text(Format.cost(model.estimatedCost(for: costMode)))
                                .font(.sora(10).monospacedDigit())
                                .stxNumericValueTransition(value: Format.cost(model.estimatedCost(for: costMode)))
                                .foregroundStyle(Color.stxMuted)
                        }
                        GeometryReader { geo in
                            let total = CGFloat(model.usage.total)
                            let cached = CGFloat(model.usage.cacheReadTokens)
                            let solid = max(0, total - cached)
                            let max = CGFloat(maxTokens)
                            let solidWidth = geo.size.width * solid / max
                            let cachedWidth = includeCache ? geo.size.width * cached / max : 0
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.primary.opacity(0.09))
                                HStack(spacing: 0) {
                                    if solidWidth > 0 {
                                        Rectangle().fill(color).frame(width: solidWidth)
                                    }
                                    if cachedWidth > 0 {
                                        ZStack {
                                            Rectangle().fill(color)
                                            DiagonalStripes(spacing: 4)
                                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                        }
                                        .frame(width: cachedWidth)
                                        .clipped()
                                    }
                                }
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Light") {
    UsageView()
        .environment(AppEnvironment.preview())
        .frame(width: 380, height: 480)
        .background(Color.stxBackground)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    UsageView()
        .environment(AppEnvironment.preview())
        .frame(width: 380, height: 480)
        .background(Color.stxBackground)
        .preferredColorScheme(.dark)
}
#endif
