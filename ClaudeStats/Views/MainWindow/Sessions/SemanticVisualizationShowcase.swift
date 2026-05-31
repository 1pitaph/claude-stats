import SwiftUI

private enum SemanticVisualizationMotion {
    static let plotInset: CGFloat = 14
    static let textSwitch = Animation.stxNumericValueChange
}

private enum SemanticVisualizationMode: String, CaseIterable, Identifiable {
    case atlas
    case bubbles
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atlas: "Atlas"
        case .bubbles: "Bubbles"
        case .cloud: "Cloud"
        }
    }

    var symbol: String {
        switch self {
        case .atlas: AppIcon.Session.atlas
        case .bubbles: AppIcon.Session.bubbles
        case .cloud: AppIcon.Session.cloud
        }
    }
}

struct SemanticVisualizationShowcase: View {
    let analysis: TranscriptAnalysisSnapshot
    let sessions: [Session]

    @State private var mode: SemanticVisualizationMode = .atlas
    @State private var selectedTermID: String?
    @State private var hoveredTermID: String?
    @State private var visualization: SemanticVisualizationSnapshot?
    @State private var cacheKey: String?

    private var currentCacheKey: String {
        let latestSessionDate = sessions
            .map { ($0.stats?.lastActivity ?? $0.lastModified).timeIntervalSinceReferenceDate }
            .max() ?? 0
        return [
            analysis.provider.rawValue,
            String(Int(analysis.generatedAt.timeIntervalSinceReferenceDate.rounded())),
            String(analysis.terms.count),
            String(analysis.sessionAnalyses.count),
            String(sessions.count),
            String(Int(latestSessionDate.rounded())),
            analysis.dictionarySignature,
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Group {
                if let visualization, !visualization.isEmpty {
                    chartStage(visualization)
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, minHeight: 420, maxHeight: 420)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.stxStroke.opacity(0.75), lineWidth: 1))

            if let visualization {
                SemanticSelectionSummary(
                    visualization: visualization,
                    selectedTermID: selectedTermID,
                    hoveredTermID: hoveredTermID
                )
            }
        }
        .appSurface(.mainWindowCard, padding: 16)
        .onAppear { rebuildIfNeeded() }
        .onChange(of: currentCacheKey) { _, _ in rebuildIfNeeded() }
        .onChange(of: mode) { _, _ in
            selectedTermID = nil
            hoveredTermID = nil
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SEMANTIC MAP")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.stxMuted)
                Text("Global structure across extracted terms and sessions.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }

            Spacer(minLength: 12)

            PillSegmentedBar(
                SemanticVisualizationMode.allCases,
                selection: $mode,
                style: .toolbarModeSwitch,
                help: { "Show \($0.title) semantic view" },
                accessibilityLabel: { "\($0.title) semantic view" }
            ) { mode, _ in
                Label(mode.title, systemImage: mode.symbol)
                    .labelStyle(.titleAndIcon)
            }
            .frame(width: 304, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func chartStage(_ visualization: SemanticVisualizationSnapshot) -> some View {
        switch mode {
        case .atlas:
            SemanticAtlasView(
                visualization: visualization,
                selectedTermID: $selectedTermID,
                hoveredTermID: $hoveredTermID
            )
        case .bubbles:
            SemanticBubbleAtlasView(
                visualization: visualization,
                selectedTermID: $selectedTermID,
                hoveredTermID: $hoveredTermID
            )
        case .cloud:
            SemanticWordCloudView(
                visualization: visualization,
                selectedTermID: $selectedTermID,
                hoveredTermID: $hoveredTermID
            )
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: AppIcon.Network.webSocket)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.stxMuted.opacity(0.65))
            Text("No semantic terms to visualize yet.")
                .font(.sora(12, weight: .medium))
                .foregroundStyle(Color.stxMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.035))
    }

    private func rebuildIfNeeded() {
        let key = currentCacheKey
        guard cacheKey != key else { return }
        visualization = SemanticVisualizationSnapshot(analysis: analysis, sessions: sessions)
        cacheKey = key
        selectedTermID = nil
        hoveredTermID = nil
    }
}

private struct SemanticSelectionSummary: View {
    let visualization: SemanticVisualizationSnapshot
    let selectedTermID: String?
    let hoveredTermID: String?

    private var activeNode: SemanticTermNode? {
        visualization.node(for: hoveredTermID) ?? visualization.node(for: selectedTermID)
    }

    private var activeID: String {
        activeNode?.id ?? "placeholder"
    }

    var body: some View {
        Group {
            if let activeNode {
                termSummary(activeNode)
            } else {
                placeholder
            }
        }
        .id(activeID)
        .transition(.opacity)
        .contentTransition(.opacity)
        .animation(SemanticVisualizationMotion.textSwitch, value: activeID)
        .frame(height: 28, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var placeholder: some View {
        HStack(spacing: 9) {
            Image(systemName: AppIcon.Pointer.motion)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 20, alignment: .leading)
            Text("Select or hover a term to inspect frequency, sessions, and score.")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
    }

    private func termSummary(_ node: SemanticTermNode) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: node.kind.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 20, alignment: .leading)
                    .contentTransition(.opacity)
                Text(node.displayName)
                    .font(.sora(12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
                Text(node.kind.displayName)
                    .font(.sora(9, weight: .medium))
                    .foregroundStyle(SemanticVisualizationPalette.color(for: node.kind))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(SemanticVisualizationPalette.color(for: node.kind).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .contentTransition(.opacity)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            metricSummary(node)
                .layoutPriority(2)
        }
    }

    private func metricSummary(_ node: SemanticTermNode) -> some View {
        HStack(spacing: 0) {
            Text("freq ")
            Text(groupedInteger(node.frequency))
                .stxNumericValueTransition(value: node.frequency)
            Text(" - sessions ")
            Text(groupedInteger(node.documentFrequency))
                .stxNumericValueTransition(value: node.documentFrequency)
            Text(" - score ")
            Text(scoreText(node.tfidf))
                .stxNumericValueTransition(value: scoreText(node.tfidf))
        }
        .font(.sora(10).monospacedDigit())
        .foregroundStyle(Color.stxMuted)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func groupedInteger(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private func scoreText(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private struct SemanticPlotSpace {
    let outerSize: CGSize
    var inset: CGFloat = SemanticVisualizationMotion.plotInset

    var rect: CGRect {
        CGRect(
            x: inset,
            y: inset,
            width: max(1, outerSize.width - inset * 2),
            height: max(1, outerSize.height - inset * 2)
        )
    }

    var size: CGSize { rect.size }
}

private struct SemanticAtlasView: View {
    let visualization: SemanticVisualizationSnapshot
    @Binding var selectedTermID: String?
    @Binding var hoveredTermID: String?

    private var activeID: String? { hoveredTermID ?? selectedTermID }

    var body: some View {
        GeometryReader { geometry in
            let plot = SemanticPlotSpace(outerSize: geometry.size)
            ZStack(alignment: .topLeading) {
                SemanticVisualizationBackground()
                ZStack {
                    SemanticNetworkEdgesCanvas(
                        visualization: visualization,
                        positionedNodes: visualization.atlasNodes,
                        activeTermID: activeID
                    )
                    ForEach(visualization.atlasNodes) { positioned in
                        if let node = visualization.node(for: positioned.nodeID) {
                            SemanticNodeButton(
                                node: node,
                                positioned: positioned,
                                canvasSize: plot.size,
                                selected: selectedTermID == node.id,
                                highlighted: isHighlighted(node.id),
                                alwaysShowsLabel: node.score > 0.78
                            ) {
                                selectedTermID = selectedTermID == node.id ? nil : node.id
                            } hover: { hovering in
                                hoveredTermID = hovering ? node.id : nil
                            }
                        }
                    }
                }
                .frame(width: plot.size.width, height: plot.size.height)
                .position(x: plot.rect.midX, y: plot.rect.midY)
            }
        }
    }

    private func isHighlighted(_ nodeID: String) -> Bool {
        guard let activeID else { return false }
        if activeID == nodeID { return true }
        return visualization.edges.contains { edge in
            (edge.sourceID == activeID && edge.targetID == nodeID) || (edge.targetID == activeID && edge.sourceID == nodeID)
        }
    }
}

private struct SemanticBubbleAtlasView: View {
    let visualization: SemanticVisualizationSnapshot
    @Binding var selectedTermID: String?
    @Binding var hoveredTermID: String?

    var body: some View {
        GeometryReader { geometry in
            let plot = SemanticPlotSpace(outerSize: geometry.size)
            ZStack(alignment: .topLeading) {
                SemanticVisualizationBackground()
                ZStack {
                    bubbleGroupLabels(size: plot.size)

                    ForEach(visualization.bubbleNodes) { positioned in
                        if let node = visualization.node(for: positioned.nodeID) {
                            SemanticNodeButton(
                                node: node,
                                positioned: positioned,
                                canvasSize: plot.size,
                                selected: selectedTermID == node.id,
                                highlighted: hoveredTermID == node.id,
                                alwaysShowsLabel: node.score > 0.62
                            ) {
                                selectedTermID = selectedTermID == node.id ? nil : node.id
                            } hover: { hovering in
                                hoveredTermID = hovering ? node.id : nil
                            }
                        }
                    }
                }
                .frame(width: plot.size.width, height: plot.size.height)
                .position(x: plot.rect.midX, y: plot.rect.midY)
            }
        }
    }

    private func bubbleGroupLabels(size: CGSize) -> some View {
        let groups = Dictionary(grouping: visualization.bubbleNodes, by: { visualization.node(for: $0.nodeID)?.kind ?? .general })
        return ZStack {
            ForEach(TranscriptTermKind.allCases, id: \.self) { kind in
                if let matching = groups[kind], let positioned = matching.first {
                    let x = matching.map(\.x).reduce(0, +) / Double(max(matching.count, 1))
                    let y = max(0.05, (matching.map(\.y).min() ?? positioned.y) - 0.05)
                    Text(kind.displayName.uppercased())
                        .font(.sora(9, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(SemanticVisualizationPalette.color(for: kind).opacity(0.82))
                        .position(x: x * size.width, y: y * size.height)
                }
            }
        }
    }
}

private struct SemanticWordCloudView: View {
    let visualization: SemanticVisualizationSnapshot
    @Binding var selectedTermID: String?
    @Binding var hoveredTermID: String?

    var body: some View {
        ZStack {
            SemanticVisualizationBackground()
            SemanticWordCloudFlowLayout(spacing: 10, rowSpacing: 10) {
                ForEach(visualization.wordCloudItems) { item in
                    Button {
                        selectedTermID = selectedTermID == item.nodeID ? nil : item.nodeID
                    } label: {
                        Text(item.text)
                            .font(.sora(item.fontSize, weight: selectedTermID == item.nodeID ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(SemanticVisualizationPalette.color(for: item.kind).opacity(hoveredTermID == item.nodeID || selectedTermID == item.nodeID ? 1 : 0.78))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background {
                                if selectedTermID == item.nodeID {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(SemanticVisualizationPalette.color(for: item.kind).opacity(0.12))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(visualization.node(for: item.nodeID)?.helpText ?? item.text)
                    .onHover { hovering in
                        hoveredTermID = hovering ? item.nodeID : nil
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct SemanticNetworkEdgesCanvas: View {
    let visualization: SemanticVisualizationSnapshot
    let positionedNodes: [SemanticPositionedNode]
    let activeTermID: String?

    var body: some View {
        Canvas { context, size in
            let positions = Dictionary(uniqueKeysWithValues: positionedNodes.map { ($0.nodeID, $0) })
            for edge in visualization.edges {
                guard let sourcePosition = positions[edge.sourceID],
                      let targetPosition = positions[edge.targetID],
                      let sourceNode = visualization.node(for: edge.sourceID) else {
                    continue
                }
                let source = CGPoint(x: sourcePosition.x * size.width, y: sourcePosition.y * size.height)
                let target = CGPoint(x: targetPosition.x * size.width, y: targetPosition.y * size.height)
                var path = Path()
                path.move(to: source)
                path.addLine(to: target)
                let hasActiveTerm = activeTermID != nil
                let connected = activeTermID == nil || activeTermID == edge.sourceID || activeTermID == edge.targetID
                let lineWidth: CGFloat
                let opacity: Double
                let dash: [CGFloat]
                if !hasActiveTerm {
                    lineWidth = 0.65 + CGFloat(edge.strength) * 1.2
                    opacity = 0.11 + edge.strength * 0.28
                    dash = []
                } else if connected {
                    lineWidth = 1.15 + CGFloat(edge.strength) * 2.0
                    opacity = 0.24 + edge.strength * 0.42
                    dash = []
                } else {
                    lineWidth = 0.55
                    opacity = 0.085
                    dash = [4, 5]
                }
                context.stroke(
                    path,
                    with: .color(SemanticVisualizationPalette.color(for: sourceNode.kind).opacity(opacity)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: dash)
                )
            }
        }
    }
}

private struct SemanticNodeButton: View {
    let node: SemanticTermNode
    let positioned: SemanticPositionedNode
    let canvasSize: CGSize
    let selected: Bool
    let highlighted: Bool
    let alwaysShowsLabel: Bool
    let action: () -> Void
    let hover: (Bool) -> Void

    private var diameter: CGFloat {
        max(10, min(canvasSize.width, canvasSize.height) * CGFloat(positioned.radius) * 2)
    }

    var body: some View {
        ZStack {
            Button(action: action) {
                Circle()
                    .fill(SemanticVisualizationPalette.color(for: node.kind).opacity(highlighted || selected ? 0.92 : 0.66))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(selected ? 0.95 : highlighted ? 0.62 : 0.28), lineWidth: selected ? 2 : 1)
                    }
                    .shadow(color: SemanticVisualizationPalette.color(for: node.kind).opacity(selected ? 0.36 : highlighted ? 0.22 : 0.12), radius: selected ? 10 : 5, y: 2)
            }
            .buttonStyle(.plain)
            .frame(width: diameter, height: diameter)
            .help(node.helpText)
            .accessibilityLabel(node.displayName)
            .accessibilityValue("\(node.kind.displayName), frequency \(node.frequency), sessions \(node.documentFrequency)")
            .onHover(perform: hover)

            if alwaysShowsLabel || selected || highlighted {
                Text(node.displayName)
                    .font(.sora(selected ? 10 : 9, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.stxBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .offset(y: diameter / 2 + 9)
                    .allowsHitTesting(false)
            }
        }
        .position(x: positioned.x * canvasSize.width, y: positioned.y * canvasSize.height)
        .zIndex(selected ? 10 : highlighted ? 8 : alwaysShowsLabel ? 4 : 1)
    }
}

private struct SemanticVisualizationBackground: View {
    var body: some View {
        ZStack {
            Color.primary.opacity(0.032)
            Canvas { context, size in
                let step: CGFloat = 36
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(path, with: .color(Color.stxStroke.opacity(0.34)), lineWidth: 0.5)
            }
        }
    }
}

private struct SemanticWordCloudFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let rows = rows(in: width, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * rowSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(in: bounds.width, subviews: subviews)
        let totalHeight = rows.reduce(CGFloat(0)) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * rowSpacing
        var y = bounds.midY - totalHeight / 2
        for row in rows {
            var x = bounds.midX - row.width / 2
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [FlowRow] {
        var rows: [FlowRow] = []
        var current = FlowRow()
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if nextWidth > width, !current.items.isEmpty {
                rows.append(current)
                current = FlowRow()
            }
            current.append(FlowItem(subview: subview, size: size), spacing: spacing)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }

    private struct FlowItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct FlowRow {
        var items: [FlowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(_ item: FlowItem, spacing: CGFloat) {
            if !items.isEmpty { width += spacing }
            items.append(item)
            width += item.size.width
            height = max(height, item.size.height)
        }
    }
}

private enum SemanticVisualizationPalette {
    static func color(for kind: TranscriptTermKind) -> Color {
        switch kind {
        case .language: aiIro
        case .framework: yamabukiIro
        case .api: sumireIro
        case .typeName: asagiIro
        case .function: moegiIro
        case .filePath: usuasagi
        case .command: daidaiIro
        case .configKey: kakitsubata
        case .error: akaneIro
        case .workflow: tokiwaIro
        case .general: yamabatoIro
        }
    }

    private static let aiIro = rgb(0x004C71)
    private static let asagiIro = rgb(0x00A5BF)
    private static let usuasagi = rgb(0xA2D7DD)
    private static let yamabukiIro = rgb(0xF8B400)
    private static let daidaiIro = rgb(0xEE7800)
    private static let moegiIro = rgb(0x86B81B)
    private static let tokiwaIro = rgb(0x006428)
    private static let sumireIro = rgb(0x7065A3)
    private static let kakitsubata = rgb(0x5E3862)
    private static let akaneIro = rgb(0xB7282E)
    private static let yamabatoIro = rgb(0x767C6B)

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private extension SemanticTermNode {
    var helpText: String {
        "\(displayName) - \(kind.displayName) - freq \(frequency) - sessions \(documentFrequency) - score \(String(format: "%.1f", tfidf))"
    }
}
