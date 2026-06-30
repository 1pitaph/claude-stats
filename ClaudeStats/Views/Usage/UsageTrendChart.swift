import SwiftUI
import Charts

enum UsageTrendMotion {
    static let chartMorph: Animation = .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.28)
    static let chartCrossfade: Animation = .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.22)
    static let periodChip: Animation = .easeOut(duration: 0.18)
}

struct UsageTrendChartSnapshot {
    let points: [UsageTrendChartPoint]
    let legendEntries: [UsageTrendLegendEntry]
    let viewport: STXDateChartViewport
    let renderFamilyID: String
    let viewportID: String
    let transitionScopeID: String
    let stageID: String
    let dataID: Int
    let isHourly: Bool
    let style: TrendChartStyle
    let useLog: Bool
    let stackByType: Bool
    let isEmpty: Bool
    let modelColorIndexByID: [String: Int]
    var updateID: String { "\(transitionScopeID)|\(stageID)|\(viewportID)|\(dataID)" }

    init(
        series: TrendSeries,
        rangeID: String,
        transitionScopeID: String = "default",
        style: TrendChartStyle,
        useLog: Bool,
        stackByType: Bool,
        displayName: (String) -> String
    ) {
        let isHourly = series.granularity == .hour
        let points = Self.trendPoints(series, style: style, useLog: useLog, stackByType: stackByType)
        let legendEntries: [UsageTrendLegendEntry]
        var modelColorIndexByID: [String: Int] = [:]
        if stackByType {
            legendEntries = Self.tokenTypeKeys.map { UsageTrendLegendEntry(id: $0.label, label: $0.label, color: $0.color) }
        } else {
            legendEntries = series.models.enumerated().map { index, model in
                modelColorIndexByID[model] = index
                return UsageTrendLegendEntry(id: model, label: displayName(model), color: ModelPalette.color(at: index))
            }
        }

        let isEmpty = series.buckets.isEmpty || series.isEmpty || points.isEmpty
        let yUpperBound = Self.chartUpperBound(points, style: style, useLog: useLog, stackByType: stackByType)
        let viewport = Self.chartViewport(series: series, points: points, yUpperBound: yUpperBound)
        self.points = points
        self.legendEntries = legendEntries
        self.viewport = viewport
        self.isHourly = isHourly
        self.style = style
        self.useLog = useLog
        self.stackByType = stackByType
        self.isEmpty = isEmpty
        self.modelColorIndexByID = modelColorIndexByID
        self.transitionScopeID = transitionScopeID

        let renderFamilyID = [
            isHourly ? "hour" : "day",
            Self.renderFamily(style: style, stackByType: stackByType),
            useLog ? "log" : "linear",
        ].joined(separator: "|")
        self.renderFamilyID = renderFamilyID
        self.stageID = "\(isEmpty ? "empty" : "data")|\(renderFamilyID)"
        self.viewportID = Self.viewportID(rangeID: rangeID, viewport: viewport)
        self.dataID = Self.dataID(points: points, yUpperBound: yUpperBound)
    }

    private static func trendPoints(
        _ series: TrendSeries,
        style: TrendChartStyle,
        useLog: Bool,
        stackByType: Bool
    ) -> [UsageTrendChartPoint] {
        if stackByType {
            var byStart: [Date: TokenUsage] = [:]
            for bucket in series.buckets {
                byStart[bucket.start, default: .zero] += bucket.usage
            }
            let starts = byStart.keys.sorted()
            return tokenTypeKeys.flatMap { key in
                starts.compactMap { date -> UsageTrendChartPoint? in
                    let value = tokenTypeValue(byStart[date] ?? .zero, label: key.label)
                    if style == .bar && value == 0 { return nil }
                    return UsageTrendChartPoint(series: key.label, date: date, value: Double(value))
                }
            }
        }

        switch style {
        case .bar:
            return series.models.flatMap { model in
                series.buckets(for: model)
                    .filter { $0.tokens > 0 }
                    .map { UsageTrendChartPoint(series: model, date: $0.start, value: Double($0.tokens)) }
            }
        case .line:
            let count = series.buckets(for: series.models.first ?? "").count
            let window = Smoothing.adaptiveWindow(count: count, granularity: series.granularity)
            return series.models.flatMap { model in
                let buckets = series.buckets(for: model)
                var values = Smoothing.movingAverage(buckets.map { Double($0.tokens) }, window: window)
                if useLog { values = values.map { log1p($0) } }
                return zip(buckets, values).map { UsageTrendChartPoint(series: model, date: $0.start, value: $1) }
            }
        }
    }

    private static func chartUpperBound(
        _ points: [UsageTrendChartPoint],
        style: TrendChartStyle,
        useLog: Bool,
        stackByType: Bool
    ) -> Double {
        let visibleMax: Double
        if style == .bar || stackByType {
            let sums = Dictionary(grouping: points, by: \.date).mapValues { rows in
                rows.reduce(0) { $0 + $1.value }
            }
            visibleMax = sums.values.max() ?? 1
        } else {
            visibleMax = points.map(\.value).max() ?? 1
        }

        if useLog {
            return log1p(niceTokenCeiling(expm1(max(1, visibleMax))))
        }
        return niceTokenCeiling(max(1, visibleMax))
    }

    private static func chartViewport(
        series: TrendSeries,
        points: [UsageTrendChartPoint],
        yUpperBound: Double
    ) -> STXDateChartViewport {
        let starts = series.buckets.map(\.start).isEmpty
            ? points.map(\.date)
            : series.buckets.map(\.start)
        let xStart = starts.min() ?? Date(timeIntervalSinceReferenceDate: 0)
        let rawXEnd = starts.max() ?? xStart
        let unit: Calendar.Component = series.granularity == .hour ? .hour : .day
        let fallbackInterval: TimeInterval = series.granularity == .hour ? 3_600 : 86_400
        let xEnd = Calendar.current.date(byAdding: unit, value: 1, to: rawXEnd)
            ?? rawXEnd.addingTimeInterval(fallbackInterval)
        return STXDateChartViewport(xStart: xStart, xEnd: xEnd, yStart: 0, yEnd: yUpperBound)
    }

    private static func renderFamily(style: TrendChartStyle, stackByType: Bool) -> String {
        switch (style, stackByType) {
        case (.line, false):
            "model-line"
        case (.line, true):
            "type-area"
        case (.bar, false):
            "model-bar"
        case (.bar, true):
            "type-bar"
        }
    }

    private static func viewportID(rangeID: String, viewport: STXDateChartViewport) -> String {
        [
            rangeID,
            String(Int(viewport.xStart.timeIntervalSinceReferenceDate.rounded())),
            String(Int(viewport.xEnd.timeIntervalSinceReferenceDate.rounded())),
            String(Int((viewport.yStart * 1_000).rounded())),
            String(Int((viewport.yEnd * 1_000).rounded())),
        ].joined(separator: "|")
    }

    private static func niceTokenCeiling(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let magnitude = pow(10.0, floor(log10(value)))
        let normalized = value / magnitude
        let nice: Double
        switch normalized {
        case ...1:
            nice = 1
        case ...2:
            nice = 2
        case ...2.5:
            nice = 2.5
        case ...5:
            nice = 5
        default:
            nice = 10
        }
        return max(1, nice * magnitude)
    }

    private static func dataID(points: [UsageTrendChartPoint], yUpperBound: Double) -> Int {
        var hasher = Hasher()
        hasher.combine(points.count)
        hasher.combine(Int((yUpperBound * 1_000).rounded()))
        for point in points {
            hasher.combine(point.id)
            hasher.combine(Int((point.value * 1_000).rounded()))
        }
        return hasher.finalize()
    }

    static let tokenTypeKeys: [(label: String, color: Color)] = [
        ("Output", Color.stxRamp[0]),
        ("Input", Color.stxRamp[1]),
        ("Cache Write", Color.stxRamp[2]),
        ("Cache Read", Color.stxRamp[3]),
    ]

    private static func tokenTypeValue(_ usage: TokenUsage, label: String) -> Int {
        switch label {
        case "Output": usage.outputTokens
        case "Input": usage.inputTokens
        case "Cache Write": usage.cacheCreationTotalTokens
        case "Cache Read": usage.cacheReadTokens
        default: 0
        }
    }

    fileprivate func nearestHoverDate(to date: Date) -> Date? {
        var nearest: Date?
        var smallestDistance = TimeInterval.greatestFiniteMagnitude
        var visited: Set<Date> = []

        for point in points where visited.insert(point.date).inserted {
            let distance = abs(point.date.timeIntervalSince(date))
            if distance < smallestDistance {
                nearest = point.date
                smallestDistance = distance
            }
        }

        return nearest
    }

    fileprivate func hoverSelection(for date: Date?) -> UsageTrendHoverSelection? {
        guard let date else { return nil }
        let rows = points
            .filter { $0.date == date }
            .sorted { hoverSortIndex(for: $0.series) < hoverSortIndex(for: $1.series) }
            .map { point in
                UsageTrendHoverRow(
                    id: point.id,
                    label: hoverLabel(for: point.series),
                    value: hoverDisplayValue(for: point),
                    plottedValue: point.value,
                    color: hoverColor(for: point.series)
                )
            }

        guard !rows.isEmpty else { return nil }
        return UsageTrendHoverSelection(
            date: date,
            title: hoverTitle(for: date),
            rows: rows
        )
    }

    private func hoverSortIndex(for series: String) -> Int {
        if stackByType {
            return Self.tokenTypeKeys.firstIndex { $0.label == series } ?? Int.max
        }
        return modelColorIndexByID[series] ?? Int.max
    }

    private func hoverLabel(for series: String) -> String {
        legendEntries.first { $0.id == series }?.label ?? series
    }

    private func hoverColor(for series: String) -> Color {
        legendEntries.first { $0.id == series }?.color ?? Color.stxAccent
    }

    private func hoverDisplayValue(for point: UsageTrendChartPoint) -> Int {
        let value = useLog ? expm1(point.value) : point.value
        return max(0, Int(value.rounded()))
    }

    private func hoverTitle(for date: Date) -> String {
        if isHourly {
            return date.formatted(.dateTime.hour())
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct UsageTrendChartPoint: Identifiable {
    let series: String
    let date: Date
    let value: Double

    var id: String { "\(series)|\(date.timeIntervalSinceReferenceDate)" }
}

struct UsageTrendLegendEntry: Identifiable {
    let id: String
    let label: String
    let color: Color
}

fileprivate struct UsageTrendHoverSelection {
    let date: Date
    let title: String
    let rows: [UsageTrendHoverRow]

    var totalTokens: Int {
        rows.reduce(0) { $0 + $1.value }
    }
}

fileprivate struct UsageTrendHoverRow: Identifiable {
    let id: String
    let label: String
    let value: Int
    let plottedValue: Double
    let color: Color
}

struct UsageTrendChartView<Legend: View>: View {
    let snapshot: UsageTrendChartSnapshot
    let chartHeight: CGFloat
    let emptyMessage: String
    var axisFontSize: CGFloat = 8
    var barCornerRadius: CGFloat = 1
    let legend: Legend

    @State private var displayedSnapshot: UsageTrendChartSnapshot?
    @State private var chartStageNonce = 0
    @State private var hoverDate: Date?

    private var hoverTooltipMaxWidth: CGFloat { 220 }

    init(
        snapshot: UsageTrendChartSnapshot,
        chartHeight: CGFloat,
        emptyMessage: String,
        axisFontSize: CGFloat = 8,
        barCornerRadius: CGFloat = 1,
        @ViewBuilder legend: () -> Legend
    ) {
        self.snapshot = snapshot
        self.chartHeight = chartHeight
        self.emptyMessage = emptyMessage
        self.axisFontSize = axisFontSize
        self.barCornerRadius = barCornerRadius
        self.legend = legend()
    }

    var body: some View {
        let displayed = displayedSnapshot ?? snapshot
        VStack(alignment: .leading, spacing: 10) {
            if !displayed.isEmpty {
                legend
                StxRule()
            }
            chartStage(displayed)
        }
        .animation(UsageTrendMotion.chartCrossfade, value: stageAnimationID(displayed))
        .onAppear {
            installSnapshotWithoutAnimation(snapshot)
        }
        .onChange(of: snapshot.updateID) { _, _ in
            hoverDate = nil
            stageSnapshotChange()
        }
    }

    private func chartStage(_ displayed: UsageTrendChartSnapshot) -> some View {
        ZStack {
            if displayed.isEmpty {
                Text(emptyMessage)
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted.opacity(0.72))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .id("empty|\(displayed.stageID)|\(chartStageNonce)")
                    .transition(stageTransition)
            } else {
                chart(displayed)
                    .id("chart|\(displayed.renderFamilyID)|\(chartStageNonce)")
                    .transition(stageTransition)
            }
        }
        .frame(height: chartHeight)
    }

    @ViewBuilder
    private func chart(_ displayed: UsageTrendChartSnapshot) -> some View {
        let hoverSelection = displayed.hoverSelection(for: hoverDate)
        let xUnit: Calendar.Component = displayed.isHourly ? .hour : .day
        let base = Chart {
            ForEach(displayed.points) { point in
                switch displayed.style {
                case .line:
                    if displayed.stackByType {
                        AreaMark(
                            x: .value("Time", point.date, unit: displayed.isHourly ? .hour : .day),
                            y: .value("Tokens", point.value)
                        )
                        .foregroundStyle(by: .value("Type", point.series))
                        .interpolationMethod(.catmullRom)
                    } else {
                        LineMark(
                            x: .value("Time", point.date, unit: displayed.isHourly ? .hour : .day),
                            y: .value("Tokens", point.value)
                        )
                        .foregroundStyle(by: .value("Model", point.series))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                case .bar:
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Tokens", point.value)
                    )
                    .foregroundStyle(by: .value(displayed.stackByType ? "Type" : "Model", point.series))
                    .cornerRadius(barCornerRadius)
                }
            }

            if let hoverSelection {
                RuleMark(x: .value("Selected Time", hoverSelection.date, unit: xUnit))
                    .foregroundStyle(Color.primary.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                if displayed.style == .line && !displayed.stackByType {
                    ForEach(hoverSelection.rows) { row in
                        PointMark(
                            x: .value("Selected Time", hoverSelection.date, unit: xUnit),
                            y: .value("Tokens", row.plottedValue)
                        )
                        .foregroundStyle(row.color)
                        .symbolSize(42)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover(coordinateSpace: .local) { phase in
                            switch phase {
                            case .active(let location):
                                updateHover(at: location, proxy: proxy, geometry: geometry, displayed: displayed)
                            case .ended:
                                setHoverDate(nil)
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updateHover(at: value.location, proxy: proxy, geometry: geometry, displayed: displayed)
                                }
                        )

                    if let hoverSelection,
                       let plotFrame = proxy.plotFrame,
                       let selectedX = proxy.position(forX: hoverSelection.date) {
                        let frame = geometry[plotFrame]
                        let centerX = frame.minX + selectedX
                        let tooltipWidth = min(hoverTooltipMaxWidth, max(160, geometry.size.width - 12))

                        UsageTrendHoverTooltip(selection: hoverSelection)
                            .frame(width: tooltipWidth)
                            .offset(
                                x: clamped(centerX - tooltipWidth / 2,
                                           lowerBound: 0,
                                           upperBound: geometry.size.width - tooltipWidth),
                                y: frame.minY + 8
                            )
                            .allowsHitTesting(false)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .animation(.easeOut(duration: 0.12), value: hoverDate)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(Format.tokens(Int(displayed.useLog ? expm1(raw) : raw)))
                            .font(.sora(axisFontSize))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
            }
        }
        .chartXAxis {
            if displayed.isHourly {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine().foregroundStyle(Color.stxStroke)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour())
                                .font(.sora(axisFontSize))
                                .foregroundStyle(Color.stxMuted)
                        }
                    }
                }
            } else {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Color.stxStroke)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.sora(axisFontSize))
                                .foregroundStyle(Color.stxMuted)
                        }
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .animation(UsageTrendMotion.chartMorph, value: displayed.dataID)
        .stxDateChartViewportTransition(displayed.viewport, value: displayed.viewportID)

        if displayed.stackByType {
            base.chartForegroundStyleScale(
                domain: UsageTrendChartSnapshot.tokenTypeKeys.map(\.label),
                range: UsageTrendChartSnapshot.tokenTypeKeys.map(\.color)
            )
        } else {
            base.chartForegroundStyleScale(mapping: { (key: String) in
                ModelPalette.color(at: displayed.modelColorIndexByID[key] ?? 0)
            })
        }
    }

    @MainActor
    private func updateHover(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        displayed: UsageTrendChartSnapshot
    ) {
        guard let plotFrame = proxy.plotFrame else {
            setHoverDate(nil)
            return
        }

        let frame = geometry[plotFrame]
        guard frame.contains(location) else {
            setHoverDate(nil)
            return
        }

        let plotX = location.x - frame.minX
        guard let rawDate = proxy.value(atX: plotX, as: Date.self),
              let nearestDate = displayed.nearestHoverDate(to: rawDate) else {
            setHoverDate(nil)
            return
        }

        setHoverDate(nearestDate)
    }

    @MainActor
    private func setHoverDate(_ date: Date?) {
        guard hoverDate != date else { return }
        hoverDate = date
    }

    private func clamped(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), max(lowerBound, upperBound))
    }

    private var stageTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.985, anchor: .center))
    }

    private func stageAnimationID(_ displayed: UsageTrendChartSnapshot) -> String {
        "\(displayed.stageID)|\(chartStageNonce)"
    }

    @MainActor
    private func stageSnapshotChange() {
        guard let previous = displayedSnapshot else {
            installSnapshotWithoutAnimation(snapshot)
            return
        }

        let isSameDataStage = previous.renderFamilyID == snapshot.renderFamilyID
            && !previous.isEmpty
            && !snapshot.isEmpty
        let isScopeChange = previous.transitionScopeID != snapshot.transitionScopeID
        let isShrinkingTimeAxis = snapshot.viewport.xDuration < previous.viewport.xDuration - 0.5

        if isScopeChange || (isSameDataStage && isShrinkingTimeAxis) {
            withAnimation(UsageTrendMotion.chartCrossfade) {
                chartStageNonce += 1
                displayedSnapshot = snapshot
            }
            return
        }

        displayedSnapshot = snapshot
    }

    @MainActor
    private func installSnapshotWithoutAnimation(_ snapshot: UsageTrendChartSnapshot) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedSnapshot = snapshot
        }
    }
}

fileprivate struct UsageTrendHoverTooltip: View {
    let selection: UsageTrendHoverSelection

    private var visibleRows: ArraySlice<UsageTrendHoverRow> {
        selection.rows.prefix(6)
    }

    private var hiddenRowCount: Int {
        max(0, selection.rows.count - visibleRows.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(selection.title)
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Format.tokens(selection.totalTokens))
                    .font(.sora(10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(visibleRows) { row in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(row.color)
                            .frame(width: 7, height: 7)
                        Text(row.label)
                            .font(.sora(9))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(Format.tokens(row.value))
                            .font(.sora(9).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                    }
                }

                if hiddenRowCount > 0 {
                    Text("+\(hiddenRowCount)")
                        .font(.sora(9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
    }
}
