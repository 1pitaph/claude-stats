import SwiftUI

struct TrackFlowWorkspace: View {
    @Bindable var store: TrackStore

    var body: some View {
        if let run = store.selectedRun {
            HStack(spacing: 0) {
                TrackGraphCanvas(
                    run: run,
                    selectedNodeID: store.selectedNode?.id,
                    onSelectNode: store.selectNode
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                StxRule()
                    .frame(width: 1)

                TrackNodeInspector(run: run, node: store.selectedNode)
                    .frame(width: 310)
            }
        } else {
            TrackEmptyState()
        }
    }
}

private struct TrackGraphCanvas: View {
    let run: TrackRun
    let selectedNodeID: TrackNode.ID?
    var onSelectNode: (TrackNode) -> Void

    @State private var scale: CGFloat = 1

    var body: some View {
        let layout = TrackGraphLayout(run: run)

        VStack(spacing: 0) {
            graphToolbar
            StxRule()
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    TrackEdgeLayer(layout: layout, run: run)

                    ForEach(run.nodes) { node in
                        if let frame = layout.frames[node.id] {
                            TrackGraphNodeButton(
                                node: node,
                                isSelected: selectedNodeID == node.id
                            ) {
                                onSelectNode(node)
                            }
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                        }
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: layout.size.width * scale, height: layout.size.height * scale, alignment: .topLeading)
                .padding(24)
            }
            .background {
                TrackGraphGrid()
            }
        }
    }

    private var graphToolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(run.projectName)
                    .font(.sora(13, weight: .semibold))
                    .lineLimit(1)
                Text("\(run.subagentCount) subagents · \(run.toolCount) tools · \(run.confidence.title)")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            TrackStatusBadge(status: run.status)
            TrackSourceBadge(source: run.events.first?.source ?? .transcript, confidence: run.confidence)

            Stepper(value: $scale, in: 0.72...1.35, step: 0.08) {
                Text("\(Int((scale * 100).rounded()))%")
                    .font(.sora(10, weight: .medium).monospacedDigit())
                    .frame(width: 42, alignment: .trailing)
            }
            .labelsHidden()
            .frame(width: 96)
            .help("Zoom graph")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct TrackGraphNodeButton: View {
    let node: TrackNode
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: node.kind.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(node.status.trackColor)
                        .frame(width: 18)
                    Text(node.kind.title.uppercased())
                        .font(.sora(9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.stxMuted)
                    Spacer(minLength: 6)
                    Circle()
                        .fill(node.status.trackColor)
                        .frame(width: 8, height: 8)
                }

                Text(node.title)
                    .font(.sora(12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(node.subtitle)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(node.status.title)
                        .font(.sora(9, weight: .medium))
                        .foregroundStyle(node.status.trackColor)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(node.confidence.titleShort)
                        .font(.sora(9, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(nodeBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(node.status.trackColor)
                    .frame(width: 3)
                    .clipShape(.rect(cornerRadius: 1.5))
                    .padding(.vertical, 8)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(nodeStroke, lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("\(node.kind.title): \(node.title)")
    }

    private var nodeBackground: Color {
        isSelected ? node.status.trackColor.opacity(0.13) : Color.primary.opacity(0.045)
    }

    private var nodeStroke: Color {
        isSelected ? node.status.trackColor.opacity(0.72) : Color.stxStroke.opacity(node.confidence == .high ? 0.9 : 0.45)
    }
}

private struct TrackEdgeLayer: View {
    let layout: TrackGraphLayout
    let run: TrackRun

    var body: some View {
        Canvas { context, _ in
            for edge in run.edges {
                guard let start = layout.frames[edge.from],
                      let end = layout.frames[edge.to] else { continue }
                var path = Path()
                let from = CGPoint(x: start.maxX, y: start.midY)
                let to = CGPoint(x: end.minX, y: end.midY)
                let midX = (from.x + to.x) / 2
                path.move(to: from)
                path.addCurve(
                    to: to,
                    control1: CGPoint(x: midX, y: from.y),
                    control2: CGPoint(x: midX, y: to.y)
                )
                let color = edge.confidence == .high ? Color.primary.opacity(0.42) : Color.primary.opacity(0.22)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: edge.confidence == .high ? 1.6 : 1, dash: edge.confidence == .high ? [] : [5, 4]))
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .allowsHitTesting(false)
    }
}

private struct TrackGraphGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 32
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(Color.primary.opacity(0.035)), lineWidth: 1)
        }
    }
}

private struct TrackNodeInspector: View {
    let run: TrackRun
    let node: TrackNode?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inspectorHeader
            StxRule()
            AppScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let node {
                        nodeSummary(node)
                        metadata(node)
                        eventTimeline(node)
                    } else {
                        Text("Select a node to inspect its status, source, and related events.")
                            .font(.sora(12))
                            .foregroundStyle(Color.stxMuted)
                            .padding(.top, 4)
                    }
                }
                .padding(16)
            }
        }
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("INSPECTOR")
                .font(.sora(10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.stxMuted)
            Text(node?.title ?? run.title)
                .font(.sora(16, weight: .semibold))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func nodeSummary(_ node: TrackNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TrackStatusBadge(status: node.status)
            TrackSourceBadge(source: node.source, confidence: node.confidence)
            if let startedAt = node.startedAt {
                inspectorRow("Started", Format.shortTime(startedAt))
            }
            if let endedAt = node.endedAt {
                inspectorRow("Ended", Format.shortTime(endedAt))
            }
        }
    }

    private func metadata(_ node: TrackNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Metadata")
            ForEach(node.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                inspectorRow(key, value)
            }
        }
    }

    private func eventTimeline(_ node: TrackNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Events")
            ForEach(run.events.filter { node.eventIDs.contains($0.id) }) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.kind.title)
                        .font(.sora(11, weight: .semibold))
                    Text(event.summary)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                    Text(Format.shortTime(event.timestamp))
                        .font(.sora(9))
                        .foregroundStyle(Color.stxMuted)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.sora(10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Color.stxMuted)
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.sora(9, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(10))
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

private struct TrackEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "No Track Data",
            systemImage: AppIcon.Workspace.track,
            description: Text("Track will show session flow from transcripts now, and precise subagent/tool/approval events when Codex hooks write to the Track event log.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TrackGraphLayout {
    let frames: [TrackNode.ID: CGRect]
    let size: CGSize

    init(run: TrackRun) {
        let nodeWidth: CGFloat = 190
        let nodeHeight: CGFloat = 112
        let columnGap: CGFloat = 76
        let rowGap: CGFloat = 30
        let origin = CGPoint(x: 30, y: 30)

        let childrenByParent = Dictionary(grouping: run.edges, by: \.from)
        var depthByNode: [TrackNode.ID: Int] = [:]
        var queue: [(TrackNode.ID, Int)] = []
        if let root = run.nodes.first(where: { $0.kind == .session }) {
            queue.append((root.id, 0))
        }
        for node in run.nodes where !depthByNode.keys.contains(node.id) && queue.isEmpty {
            queue.append((node.id, 0))
        }

        while !queue.isEmpty {
            let (id, depth) = queue.removeFirst()
            guard depthByNode[id] == nil || depth < depthByNode[id]! else { continue }
            depthByNode[id] = depth
            for edge in childrenByParent[id] ?? [] {
                queue.append((edge.to, depth + 1))
            }
        }
        for node in run.nodes where depthByNode[node.id] == nil {
            depthByNode[node.id] = 0
        }

        let grouped = Dictionary(grouping: run.nodes) { depthByNode[$0.id] ?? 0 }
        var frames: [TrackNode.ID: CGRect] = [:]
        for depth in grouped.keys.sorted() {
            let nodes = (grouped[depth] ?? []).sorted { lhs, rhs in
                let lhsDate = lhs.startedAt ?? .distantPast
                let rhsDate = rhs.startedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.id < rhs.id
            }
            for (row, node) in nodes.enumerated() {
                frames[node.id] = CGRect(
                    x: origin.x + CGFloat(depth) * (nodeWidth + columnGap),
                    y: origin.y + CGFloat(row) * (nodeHeight + rowGap),
                    width: nodeWidth,
                    height: nodeHeight
                )
            }
        }

        let maxX = frames.values.map(\.maxX).max() ?? 600
        let maxY = frames.values.map(\.maxY).max() ?? 420
        self.frames = frames
        self.size = CGSize(width: max(720, maxX + 40), height: max(460, maxY + 40))
    }
}
