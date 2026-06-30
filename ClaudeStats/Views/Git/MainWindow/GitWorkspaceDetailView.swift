import SwiftUI

/// Main-window Git surface. Unlike the compact menu-bar pane, this view is a
/// repository-oriented workspace with stable selection and a denser desktop
/// layout.
struct GitWorkspaceDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Binding private var selection: GitWorkspaceSelection
    let repoSelectionToken: UInt64
    private let previewModel: GitActivityViewModel?

    private let isPreview: Bool
    #if DEBUG
    private let previewGraph: GitGraph?
    #endif

    init(selection: Binding<GitWorkspaceSelection>, repoSelectionToken: UInt64 = 0) {
        _selection = selection
        self.repoSelectionToken = repoSelectionToken
        previewModel = nil
        isPreview = false
        #if DEBUG
        previewGraph = nil
        #endif
    }

    #if DEBUG
    init(
        selection: Binding<GitWorkspaceSelection>,
        repoSelectionToken: UInt64 = 0,
        previewModel: GitActivityViewModel,
        graph: GitGraph? = nil
    ) {
        _selection = selection
        self.repoSelectionToken = repoSelectionToken
        self.previewModel = previewModel
        isPreview = true
        previewGraph = graph
    }
    #endif

    private struct ReloadKey: Equatable {
        let token: UInt64
        let lastRefreshed: Date?
        let sourceIDs: String
    }

    private var activityModel: GitActivityViewModel {
        previewModel ?? env.gitActivity
    }

    private var selectedActivity: RepoActivity? {
        guard let repoID = selection.repoID else { return nil }
        return activityModel.repos.first { $0.repo.id == repoID }
    }

    var body: some View {
        let model = activityModel
        @Bindable var vm = model
        let sourceIDs = env.preferences.gitWorkspaceSourceIDs
        let key = ReloadKey(
            token: vm.reloadToken,
            lastRefreshed: env.store.lastRefreshedAt,
            sourceIDs: GitWorkspaceSourceCatalog.storageString(for: sourceIDs)
        )

        return VStack(spacing: 0) {
            header(model: vm)
            StxRule()
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: key) {
            if isPreview { return }
            await vm.reloadIfNeeded(
                sessions: env.store.sessions,
                sourceIDs: sourceIDs,
                lastRefreshedAt: env.store.lastRefreshedAt
            )
            reconcileSelection()
        }
        .onAppear { reconcileSelection() }
        .onChange(of: vm.repos.map(\.id)) { _, _ in reconcileSelection() }
    }

    private func header(model: GitActivityViewModel) -> some View {
        @Bindable var vm = model
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GIT ACTIVITY")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Text("Repository workspace")
                    .font(.sora(24, weight: .semibold))
                    .lineLimit(1)
                Text("Commits from repositories opened or used by configured AI coding tools.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if vm.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .help("Loading git activity")
            }
            MainGitMineToggle(onlyMyCommits: $vm.onlyMyCommits, userEmail: vm.userEmail)
            MainGitRangePicker(range: $vm.range)
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var detailContent: some View {
        let vm = activityModel
        if !vm.gitAvailable {
            GitWorkspaceNotice(
                title: "Git not available",
                message: "Couldn't run the git command. Install the Xcode command-line tools and refresh."
            )
        } else if !vm.hasData {
            GitWorkspaceNotice(
                title: "No git activity",
                message: "No configured Git sources have commits in this range. Try a wider window or disable My Commits."
            )
        } else if let activity = selectedActivity {
            #if DEBUG
            GitRepoWorkspaceView(repo: activity.repo, previewGraph: previewGraph, repoSelectionToken: repoSelectionToken)
            #else
            GitRepoWorkspaceView(repo: activity.repo, repoSelectionToken: repoSelectionToken)
            #endif
        } else {
            GitOverviewContent(snapshot: vm.overviewSnapshot)
        }
    }

    private func reconcileSelection() {
        guard let repoID = selection.repoID else { return }
        if !activityModel.repos.contains(where: { $0.repo.id == repoID }) {
            selection = .all
        }
    }
}

private enum GitOverviewTableLayout: Equatable {
    case wide
    case narrow

    static func forWidth(_ width: CGFloat) -> Self {
        width >= 680 ? .wide : .narrow
    }
}

private enum GitOverviewTableMetrics {
    static let gap: CGFloat = 16
    static let churnMinWidth: CGFloat = 260
    static let churnIdealWidth: CGFloat = 300
    static let recentMinWidth: CGFloat = 320
    static let recentIdealWidth: CGFloat = 420
}

private enum GitOverviewMetricsGridMetrics {
    static let horizontalSpacing: CGFloat = 12
    static let verticalSpacing: CGFloat = 12
    static let statCardHorizontalPadding: CGFloat = 28
}

private struct GitOverviewContent: View {
    let snapshot: GitActivityViewModel.OverviewSnapshot

    @State private var tableLayout: GitOverviewTableLayout = .wide
    @State private var metricsWidth: CGFloat = 0
    @State private var linesValueWidth: CGFloat = 0

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metricsGrid
                GitCorrelationPanel(correlation: snapshot.correlation)
                tables
            }
            .padding(20)
            .onGeometryChange(for: GitOverviewTableLayout.self) { proxy in
                GitOverviewTableLayout.forWidth(proxy.size.width)
            } action: { newLayout in
                if tableLayout != newLayout {
                    tableLayout = newLayout
                }
            }
        }
    }

    private var metricsGrid: some View {
        Grid(
            horizontalSpacing: GitOverviewMetricsGridMetrics.horizontalSpacing,
            verticalSpacing: GitOverviewMetricsGridMetrics.verticalSpacing
        ) {
            if usesTwoRowMetrics {
                GridRow {
                    ForEach(snapshot.stats.prefix(2)) { stat in
                        StatCard(label: stat.label, value: stat.value)
                    }
                }
                GridRow {
                    ForEach(snapshot.stats.dropFirst(2)) { stat in
                        StatCard(label: stat.label, value: stat.value)
                    }
                }
            } else {
                GridRow {
                    ForEach(snapshot.stats) { stat in
                        StatCard(label: stat.label, value: stat.value)
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            metricsWidth = newWidth
        }
        .overlay(alignment: .topLeading) {
            Text(linesStatValue)
                .font(.sora(20, weight: .semibold).monospacedDigit())
                .fixedSize(horizontal: true, vertical: false)
                .hidden()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    linesValueWidth = newWidth
                }
        }
        .animation(.easeOut(duration: 0.18), value: usesTwoRowMetrics)
    }

    private var usesTwoRowMetrics: Bool {
        guard metricsWidth > 0, linesValueWidth > 0 else { return false }
        let cardWidth = (
            metricsWidth - (3 * GitOverviewMetricsGridMetrics.horizontalSpacing)
        ) / 4
        let requiredWidth = linesValueWidth + GitOverviewMetricsGridMetrics.statCardHorizontalPadding
        return requiredWidth > cardWidth
    }

    private var linesStatValue: String {
        snapshot.stats.first { $0.id == "lines" }?.value ?? ""
    }

    @ViewBuilder
    private var tables: some View {
        switch tableLayout {
        case .wide:
            HStack(alignment: .top, spacing: GitOverviewTableMetrics.gap) {
                GitChurnTable(rows: snapshot.churnRows, detail: snapshot.churnRowsDetail)
                    .frame(
                        minWidth: GitOverviewTableMetrics.churnMinWidth,
                        idealWidth: GitOverviewTableMetrics.churnIdealWidth,
                        maxWidth: .infinity
                    )
                GitRecentCommitsTable(rows: snapshot.recentRows)
                    .frame(
                        minWidth: GitOverviewTableMetrics.recentMinWidth,
                        idealWidth: GitOverviewTableMetrics.recentIdealWidth,
                        maxWidth: .infinity
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .narrow:
            VStack(alignment: .leading, spacing: 16) {
                GitChurnTable(rows: snapshot.churnRows, detail: snapshot.churnRowsDetail)
                GitRecentCommitsTable(rows: snapshot.recentRows)
            }
        }
    }
}

private struct GitCorrelationPanel: View {
    let correlation: GitActivityViewModel.OverviewCorrelation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("AI USAGE VS COMMITS")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Text(correlation.commitCountLabel)
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
            if correlation.points.isEmpty {
                GitInlineEmptyState("Nothing to plot for this range.")
            } else {
                Text("AI TOKENS")
                    .font(.sora(9, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                GitTokenOverviewChart(correlation: correlation)
                Text("COMMITS")
                    .font(.sora(9, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                GitCommitOverviewChart(correlation: correlation)
            }
        }
        .appSurface(.mainWindowCard)
    }
}

private struct GitTokenOverviewChart: View {
    let correlation: GitActivityViewModel.OverviewCorrelation

    private var height: CGFloat {
        correlation.hasTokens ? 96 : 44
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            GitOverviewYAxis(ticks: correlation.tokenTicks)
                .frame(height: height)
            Canvas { context, size in
                GitOverviewChartDrawing.drawGrid(
                    context: &context,
                    size: size,
                    tickCount: correlation.tokenTicks.count
                )
                GitOverviewChartDrawing.drawLineArea(
                    context: &context,
                    size: size,
                    values: correlation.tokenValues,
                    maxValue: max(correlation.tokenMax, 1),
                    color: Color.stxAccent
                )
            }
            .frame(height: height)
        }
        .opacity(correlation.hasTokens ? 1 : 0.5)
    }
}

private struct GitCommitOverviewChart: View {
    let correlation: GitActivityViewModel.OverviewCorrelation

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                GitOverviewYAxis(ticks: correlation.commitTicks)
                    .frame(height: 96)
                Canvas { context, size in
                    GitOverviewChartDrawing.drawGrid(
                        context: &context,
                        size: size,
                        tickCount: correlation.commitTicks.count
                    )
                    GitOverviewChartDrawing.drawBars(
                        context: &context,
                        size: size,
                        values: correlation.commitValues,
                        maxValue: max(correlation.commitMax, 1),
                        color: Color.primary.opacity(0.55)
                    )
                }
                .frame(height: 96)
            }
            GitOverviewXAxisLabels(ticks: correlation.dateTicks)
                .padding(.leading, 52)
        }
    }
}

private struct GitOverviewYAxis: View {
    let ticks: [GitActivityViewModel.OverviewAxisTick]

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(Array(ticks.enumerated()), id: \.element.id) { index, tick in
                Text(tick.label)
                    .font(.sora(8).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if index < ticks.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: 44)
    }
}

private struct GitOverviewXAxisLabels: View {
    let ticks: [GitActivityViewModel.OverviewDateTick]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(ticks.enumerated()), id: \.element.id) { index, tick in
                Text(tick.label)
                    .font(.sora(8))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                if index < ticks.count - 1 {
                    Spacer(minLength: 8)
                }
            }
        }
    }
}

private enum GitOverviewChartDrawing {
    private static let lineStrokeWidth: CGFloat = 2
    private static let lineVerticalInset: CGFloat = lineStrokeWidth / 2 + 1

    static func drawGrid(context: inout GraphicsContext, size: CGSize, tickCount: Int) {
        let count = max(tickCount, 2)
        for index in 0..<count {
            let rawY = size.height * CGFloat(index) / CGFloat(count - 1)
            let y = min(max(rawY, 0.5), max(size.height - 0.5, 0.5))
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(Color.stxStroke), lineWidth: 1)
        }
    }

    static func drawLineArea(
        context: inout GraphicsContext,
        size: CGSize,
        values: [Int],
        maxValue: Int,
        color: Color
    ) {
        let plotRect = linePlotRect(in: size)
        let points = values.enumerated().map { index, value in
            point(index: index, count: values.count, value: value, maxValue: maxValue, plotRect: plotRect)
        }
        guard let first = points.first, let last = points.last else { return }

        var line = Path()
        appendMonotoneCurve(points, to: &line)

        var area = Path()
        area.move(to: CGPoint(x: first.x, y: plotRect.maxY))
        appendMonotoneCurve(points, to: &area, moveToFirst: false)
        area.addLine(to: CGPoint(x: last.x, y: plotRect.maxY))
        area.closeSubpath()

        context.fill(area, with: .color(color.opacity(0.16)))
        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: lineStrokeWidth, lineJoin: .round))
    }

    private static func appendMonotoneCurve(_ points: [CGPoint], to path: inout Path, moveToFirst: Bool = true) {
        guard let first = points.first else { return }
        if moveToFirst {
            path.move(to: first)
        } else {
            path.addLine(to: first)
        }
        guard points.count > 2 else {
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            return
        }

        let tangents = monotoneTangents(for: points)
        for index in 0..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let dx = next.x - current.x
            path.addCurve(
                to: next,
                control1: CGPoint(x: current.x + dx / 3, y: current.y + tangents[index] * dx / 3),
                control2: CGPoint(x: next.x - dx / 3, y: next.y - tangents[index + 1] * dx / 3)
            )
        }
    }

    private static func monotoneTangents(for points: [CGPoint]) -> [CGFloat] {
        let count = points.count
        guard count > 1 else { return Array(repeating: 0, count: count) }

        let slopes = (0..<(count - 1)).map { index -> CGFloat in
            let dx = points[index + 1].x - points[index].x
            guard abs(dx) > CGFloat.ulpOfOne else { return 0 }
            return (points[index + 1].y - points[index].y) / dx
        }

        var tangents = Array(repeating: CGFloat(0), count: count)
        tangents[0] = slopes[0]
        tangents[count - 1] = slopes[count - 2]

        if count > 2 {
            for index in 1..<(count - 1) {
                let previous = slopes[index - 1]
                let next = slopes[index]
                tangents[index] = previous * next <= 0 ? 0 : (previous + next) / 2
            }
        }

        for index in 0..<(count - 1) {
            let slope = slopes[index]
            if abs(slope) <= CGFloat.ulpOfOne {
                tangents[index] = 0
                tangents[index + 1] = 0
                continue
            }

            let a = tangents[index] / slope
            let b = tangents[index + 1] / slope
            let magnitude = sqrt(a * a + b * b)
            if magnitude > 3 {
                let scale = 3 / magnitude
                tangents[index] = scale * a * slope
                tangents[index + 1] = scale * b * slope
            }
        }

        return tangents
    }

    static func drawBars(
        context: inout GraphicsContext,
        size: CGSize,
        values: [Int],
        maxValue: Int,
        color: Color
    ) {
        guard !values.isEmpty else { return }
        let slotWidth = size.width / CGFloat(values.count)
        let barWidth = max(2, min(18, slotWidth * 0.55))

        for (index, value) in values.enumerated() where value > 0 {
            let normalized = CGFloat(value) / CGFloat(max(maxValue, 1))
            let height = max(2, size.height * min(max(normalized, 0), 1))
            let x = CGFloat(index) * slotWidth + (slotWidth - barWidth) / 2
            let rect = CGRect(x: x, y: size.height - height, width: barWidth, height: height)
            var path = Path()
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1))
            context.fill(path, with: .color(color))
        }
    }

    private static func linePlotRect(in size: CGSize) -> CGRect {
        let inset = min(lineVerticalInset, max(size.height / 2, 0))
        return CGRect(
            x: 0,
            y: inset,
            width: size.width,
            height: max(size.height - inset * 2, 0)
        )
    }

    private static func point(index: Int, count: Int, value: Int, maxValue: Int, plotRect: CGRect) -> CGPoint {
        let x = count <= 1 ? plotRect.midX : plotRect.minX + plotRect.width * CGFloat(index) / CGFloat(count - 1)
        let normalized = CGFloat(value) / CGFloat(max(maxValue, 1))
        let y = plotRect.maxY - plotRect.height * min(max(normalized, 0), 1)
        return CGPoint(x: x, y: y)
    }
}

private struct GitChurnTable: View {
    let rows: [GitActivityViewModel.OverviewRepoRow]
    let detail: String

    var body: some View {
        let lastID = rows.last?.id
        LazyVStack(alignment: .leading, spacing: 0) {
            GitTableTitle(title: "CODE CHURN BY REPO", detail: detail)
            StxRule()
            ForEach(rows) { row in
                GitChurnTableRow(row: row)
                    .equatable()
                if row.id != lastID { StxRule() }
            }
        }
        .gitMainCard()
    }
}

private struct GitChurnTableRow: View, Equatable {
    private static let churnColumnWidth: CGFloat = 72
    private static let filesColumnWidth: CGFloat = 72

    let row: GitActivityViewModel.OverviewRepoRow

    var body: some View {
        HStack(spacing: 8) {
            Text(row.name)
                .font(.sora(11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
            Spacer(minLength: 8)
            Text(row.insertionsLabel)
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(GitPalette.add)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: Self.churnColumnWidth, alignment: .trailing)
            Text(row.deletionsLabel)
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(GitPalette.del)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: Self.churnColumnWidth, alignment: .trailing)
            Text(row.filesLabel)
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: Self.filesColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct GitRecentCommitsTable: View {
    private static let collapsedRowCount = 7

    let rows: [GitActivityViewModel.OverviewCommitRow]

    @State private var isExpanded = false

    var body: some View {
        let displayedRows = rows.prefix(displayedRowCount)
        let lastID = displayedRows.last?.id
        LazyVStack(alignment: .leading, spacing: 0) {
            titleRow
            StxRule()
            if rows.isEmpty {
                GitInlineEmptyState("No commits in this range.")
                    .padding(14)
            } else {
                ForEach(displayedRows) { row in
                    GitRecentCommitTableRow(row: row)
                        .equatable()
                    if row.id != lastID { StxRule() }
                }
            }
        }
        .gitMainCard()
        .animation(.easeOut(duration: 0.18), value: displayedRowCount)
        .onChange(of: rows.first?.id) { _, _ in collapse() }
        .onChange(of: rows.count) { _, _ in collapse() }
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("RECENT COMMITS")
                .font(.sora(12, weight: .semibold))
                .tracking(0.8)
            Spacer()
            Text(detailLabel)
                .font(.sora(9).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
            if showsDisclosure {
                disclosureButton
            }
        }
        .padding(12)
    }

    private var disclosureButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Show the latest \(Self.collapsedRowCount) commits" : "Show more recent commits")
        .accessibilityLabel(isExpanded ? "Collapse recent commits" : "Expand recent commits")
        .accessibilityValue("Showing \(displayedRowCount) of \(rows.count) commits")
    }

    private var detailLabel: String {
        guard showsDisclosure else { return "\(rows.count) shown" }
        return "\(displayedRowCount) of \(rows.count) shown"
    }

    private var displayedRowCount: Int {
        isExpanded ? rows.count : min(Self.collapsedRowCount, rows.count)
    }

    private var showsDisclosure: Bool {
        rows.count > Self.collapsedRowCount
    }

    private func collapse() {
        if isExpanded {
            isExpanded = false
        }
    }
}

private struct GitRecentCommitTableRow: View, Equatable {
    let row: GitActivityViewModel.OverviewCommitRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.subject)
                .font(.sora(11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 6) {
                Text(row.repoName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.shortHash)
                    .frame(width: 42, alignment: .leading)
                Text(row.churnLabel)
                    .frame(width: 76, alignment: .leading)
                Spacer(minLength: 6)
                Text(row.dateLabel)
                    .frame(width: 54, alignment: .trailing)
            }
            .font(.sora(9).monospacedDigit())
            .foregroundStyle(Color.stxMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct GitTableTitle: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.sora(12, weight: .semibold))
                .tracking(0.8)
            Spacer()
            Text(detail)
                .font(.sora(9).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
        }
        .padding(12)
    }
}

private struct MainGitRangePicker: View {
    @Binding var range: GitRange

    var body: some View {
        PillSegmentedBar(GitRange.allCases, selection: $range) { value, _ in
            Text(value.shortLabel.lowercased())
        }
        .help("Select git activity range")
    }
}

private struct MainGitMineToggle: View {
    @Binding var onlyMyCommits: Bool
    let userEmail: String?

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { onlyMyCommits.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: onlyMyCommits ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(onlyMyCommits ? Color.stxAccent : Color.stxMuted)
                Text("My Commits")
                    .font(.sora(11, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(userEmail.map { "Only count commits authored by \($0)" } ?? "Only count commits by your git user.email")
    }
}

private struct GitWorkspaceNotice: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.sora(18, weight: .semibold))
            Text(message)
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: 520, alignment: .leading)
        .gitMainCard()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

private struct GitInlineEmptyState: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.sora(10))
            .foregroundStyle(Color.stxMuted.opacity(0.8))
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
    }
}

private extension View {
    func gitMainCard() -> some View {
        appSurface(.compactCard(radius: 10, maxWidth: nil))
    }
}

#if DEBUG
#Preview("Git workspace detail - all repos") {
    @Previewable @State var selection = GitWorkspaceSelection.all
    return GitWorkspaceDetailView(
        selection: $selection,
        previewModel: .preview()
    )
    .environment(AppEnvironment.preview())
    .frame(width: 800, height: 620)
    .background(Color.stxBackground)
}

#Preview("Git workspace detail - repo") {
    @Previewable @State var selection = GitWorkspaceSelection.repo(GitGraph.preview().repo.id)
    let previewModel = GitActivityViewModel.preview()
    return GitWorkspaceDetailView(
        selection: $selection,
        previewModel: previewModel,
        graph: .preview()
    )
    .environment(AppEnvironment.preview())
    .frame(width: 900, height: 620)
    .background(Color.stxBackground)
}

#Preview("Git workspace detail - empty") {
    @Previewable @State var selection = GitWorkspaceSelection.all
    return GitWorkspaceDetailView(
        selection: $selection,
        previewModel: .previewEmpty()
    )
    .environment(AppEnvironment.preview(populated: false))
    .frame(width: 800, height: 620)
    .background(Color.stxBackground)
}
#endif
