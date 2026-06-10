import AppKit
import SwiftUI

struct TrackFlowWorkspace: View {
    @Bindable var store: TrackStore

    var body: some View {
        if let run = store.selectedRun {
            let selectedNode = store.selectedNode(in: run)
            HStack(spacing: 0) {
                TrackGraphCanvas(
                    run: run,
                    selectedNodeID: selectedNode?.id,
                    onSelectNode: store.selectNode
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                StxRule()
                    .frame(width: 1)

                TrackNodeInspector(run: run, node: selectedNode)
                    .frame(width: 310)
            }
        } else {
            TrackEmptyState()
        }
    }
}

private struct TrackGraphRenderModel: Sendable {
    let cacheKey: String
    let presentation: TrackGraphPresentation
    let layout: TrackGraphLayout

    init(run: TrackRun, cacheKey: String) {
        let presentation = TrackGraphPresentation(run: run)
        self.cacheKey = cacheKey
        self.presentation = presentation
        self.layout = TrackGraphLayout(presentation: presentation)
    }
}

private extension TrackRun {
    var graphRenderCacheKey: String {
        [
            id,
            "\(updatedAt.timeIntervalSinceReferenceDate)",
            "\(nodes.count)",
            "\(edges.count)",
            "\(events.count)",
        ].joined(separator: "::")
    }
}

private struct TrackGraphCanvas: View {
    let run: TrackRun
    let selectedNodeID: TrackNode.ID?
    var onSelectNode: (TrackNode) -> Void

    @State private var scale: CGFloat = 1
    @State private var expandedStackID: TrackToolStack.ID?
    @State private var renderModel: TrackGraphRenderModel?

    var body: some View {
        let cacheKey = run.graphRenderCacheKey

        VStack(spacing: 0) {
            graphToolbar
            StxRule()
            if let renderModel, renderModel.cacheKey == cacheKey {
                graphScrollView(renderModel)
            } else {
                TrackGraphLoadingState()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: cacheKey) {
            await rebuildRenderModel(for: run, cacheKey: cacheKey)
        }
        .onChange(of: cacheKey) { _, _ in
            expandedStackID = nil
        }
    }

    private func graphScrollView(_ model: TrackGraphRenderModel) -> some View {
        let presentation = model.presentation
        let layout = model.layout
        let expandedStack = expandedStackID.flatMap { presentation.stacksByID[$0] }
        let canvasSize = canvasSize(layout: layout, expandedStack: expandedStack)
        let expandedGridFrame: CGRect? = {
            guard let expandedStack,
                  let stackFrame = layout.frames[expandedStack.id] else { return nil }
            return toolStackGridFrame(stackFrame: stackFrame, stack: expandedStack, canvasSize: canvasSize)
        }()

        return ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                TrackEdgeLayer(
                    layout: layout,
                    edges: presentation.edges,
                    size: canvasSize,
                    focusedItemID: expandedStackID
                )

                ForEach(presentation.items) { item in
                    if let frame = layout.frames[item.id] {
                        let isDimmed = expandedStackID != nil && expandedStackID != item.id
                        Group {
                            if let stack = item.stack {
                                TrackToolStackButton(
                                    stack: stack,
                                    isSelected: isStackSelected(stack, presentation: presentation),
                                    isExpanded: expandedStackID == stack.id
                                ) {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        expandedStackID = expandedStackID == stack.id ? nil : stack.id
                                    }
                                }
                            } else if let node = item.node {
                                TrackGraphNodeButton(
                                    node: node,
                                    isSelected: selectedNodeID == node.id
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        expandedStackID = nil
                                    }
                                    onSelectNode(node)
                                }
                            }
                        }
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .opacity(isDimmed ? 0.30 : 1)
                        .blur(radius: isDimmed ? 2.4 : 0)
                        .zIndex(item.id == expandedStackID ? 3 : 1)
                    }
                }

                if let expandedStack,
                   let expandedGridFrame {
                    TrackExpandedToolStackGrid(
                        stack: expandedStack,
                        selectedNodeID: selectedNodeID,
                        onSelectNode: onSelectNode,
                        onCollapse: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedStackID = nil
                            }
                        }
                    )
                    .frame(width: expandedGridFrame.width, height: expandedGridFrame.height)
                    .position(x: expandedGridFrame.midX, y: expandedGridFrame.midY)
                    .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
                    .zIndex(5)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: canvasSize.width * scale, height: canvasSize.height * scale, alignment: .topLeading)
            .padding(24)
            .background(TrackGraphScrollConfigurator())
        }
        .scrollIndicators(.hidden)
        .background {
            TrackGraphGrid()
        }
    }

    @MainActor
    private func rebuildRenderModel(for run: TrackRun, cacheKey: String) async {
        if renderModel?.cacheKey == cacheKey { return }
        let model = await Task.detached(priority: .userInitiated) {
            TrackGraphRenderModel(run: run, cacheKey: cacheKey)
        }.value
        guard !Task.isCancelled else { return }
        renderModel = model
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

    private func isStackSelected(_ stack: TrackToolStack, presentation: TrackGraphPresentation) -> Bool {
        guard let selectedNodeID else { return false }
        return presentation.itemIDByNodeID[selectedNodeID] == stack.id
    }

    private func canvasSize(layout: TrackGraphLayout, expandedStack: TrackToolStack?) -> CGSize {
        guard let expandedStack,
              let stackFrame = layout.frames[expandedStack.id] else { return layout.size }

        let gridSize = TrackExpandedToolStackGrid.size(for: expandedStack.nodes.count)
        return CGSize(
            width: max(layout.size.width, stackFrame.maxX + gridSize.width + 96),
            height: max(layout.size.height, stackFrame.minY + gridSize.height + 72)
        )
    }

    private func toolStackGridFrame(
        stackFrame: CGRect,
        stack: TrackToolStack,
        canvasSize: CGSize
    ) -> CGRect {
        let gridSize = TrackExpandedToolStackGrid.size(for: stack.nodes.count)
        let preferredX = stackFrame.maxX + 26
        let x = min(max(24, preferredX), max(24, canvasSize.width - gridSize.width - 24))
        let preferredY = stackFrame.minY - 10
        let y = min(max(24, preferredY), max(24, canvasSize.height - gridSize.height - 24))
        return CGRect(origin: CGPoint(x: x, y: y), size: gridSize)
    }
}

private struct TrackGraphLoadingState: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Preparing flow")
                .font(.sora(11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
        }
    }
}

private struct TrackGraphScrollConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguratorView {
        ConfiguratorView()
    }

    func updateNSView(_ nsView: ConfiguratorView, context: Context) {
        nsView.configure()
    }

    static func dismantleNSView(_ nsView: ConfiguratorView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    @MainActor
    final class ConfiguratorView: NSView {
        private weak var trackedScrollView: NSScrollView?
        private var eventMonitor: Any?
        private var dragState: DragState?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configure()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configure()
            updateMonitoringState()
        }

        override func layout() {
            super.layout()
            configure()
        }

        func configure() {
            guard let scrollView = enclosingNativeScrollView else { return }
            trackedScrollView = scrollView
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScroller?.isHidden = true
            scrollView.horizontalScroller?.isHidden = true
        }

        func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            dragState = nil
        }

        private func updateMonitoringState() {
            guard window != nil else {
                stopMonitoring()
                return
            }
            guard eventMonitor == nil else { return }

            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let scrollView = trackedScrollView,
                  event.window === scrollView.window else {
                if event.type == .leftMouseUp { dragState = nil }
                return event
            }

            switch event.type {
            case .leftMouseDown:
                guard eventIsInside(scrollView, event: event) else { return event }
                dragState = DragState(
                    startLocation: event.locationInWindow,
                    startOrigin: scrollView.contentView.bounds.origin,
                    didPan: false
                )
                return event

            case .leftMouseDragged:
                guard var dragState else { return event }
                let deltaX = event.locationInWindow.x - dragState.startLocation.x
                let deltaY = event.locationInWindow.y - dragState.startLocation.y
                if !dragState.didPan {
                    dragState.didPan = hypot(deltaX, deltaY) > 3
                }
                guard dragState.didPan else {
                    self.dragState = dragState
                    return event
                }

                scroll(
                    scrollView,
                    to: CGPoint(
                        x: dragState.startOrigin.x - deltaX,
                        y: dragState.startOrigin.y + deltaY
                    )
                )
                self.dragState = dragState
                return nil

            case .leftMouseUp:
                let didPan = dragState?.didPan == true
                dragState = nil
                return didPan ? nil : event

            default:
                return event
            }
        }

        private func eventIsInside(_ scrollView: NSScrollView, event: NSEvent) -> Bool {
            let point = scrollView.convert(event.locationInWindow, from: nil)
            return scrollView.bounds.contains(point)
        }

        private func scroll(_ scrollView: NSScrollView, to proposedOrigin: CGPoint) {
            guard let documentView = scrollView.documentView else { return }
            let clipView = scrollView.contentView
            let maxX = max(0, documentView.frame.width - clipView.bounds.width)
            let maxY = max(0, documentView.frame.height - clipView.bounds.height)
            let clampedOrigin = CGPoint(
                x: min(max(0, proposedOrigin.x), maxX),
                y: min(max(0, proposedOrigin.y), maxY)
            )
            clipView.scroll(to: clampedOrigin)
            scrollView.reflectScrolledClipView(clipView)
        }

        private var enclosingNativeScrollView: NSScrollView? {
            if let scrollView = enclosingScrollView {
                return scrollView
            }

            var candidate = superview
            while let view = candidate {
                if let scrollView = view as? NSScrollView {
                    return scrollView
                }
                candidate = view.superview
            }
            return nil
        }
    }

    private struct DragState {
        let startLocation: CGPoint
        let startOrigin: CGPoint
        var didPan: Bool
    }
}

private struct TrackGraphNodeButton: View {
    let node: TrackNode
    let isSelected: Bool
    var usesSolidBackground = true
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
        if usesSolidBackground { return Color(nsColor: .controlBackgroundColor) }
        return isSelected ? node.status.trackColor.opacity(0.13) : Color.primary.opacity(0.045)
    }

    private var nodeStroke: Color {
        isSelected ? node.status.trackColor.opacity(0.72) : Color.stxStroke.opacity(node.confidence == .high ? 0.9 : 0.45)
    }
}

private struct TrackToolStackButton: View {
    let stack: TrackToolStack
    let isSelected: Bool
    let isExpanded: Bool
    var action: () -> Void

    var body: some View {
        let layerCount = min(3, max(1, stack.nodes.count))
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                ForEach(0..<layerCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: index == layerCount - 1 ? .controlBackgroundColor : .windowBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.30), lineWidth: 1))
                        .offset(x: CGFloat(index) * 4, y: CGFloat(index) * 4)
                        .padding(.trailing, CGFloat(layerCount - 1 - index) * 4)
                        .padding(.bottom, CGFloat(layerCount - 1 - index) * 4)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Image(systemName: AppIcon.Track.tools)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(stack.status.trackColor)
                            .frame(width: 18)
                        Text("TOOL STACK")
                            .font(.sora(9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Color.stxMuted)
                        Spacer(minLength: 6)
                        Text("\(stack.nodes.count)")
                            .font(.sora(10, weight: .bold).monospacedDigit())
                            .foregroundStyle(stack.status.trackColor)
                            .frame(width: 26, height: 20)
                            .background(stack.status.trackColor.opacity(0.12), in: Capsule())
                    }

                    Text(stack.title)
                        .font(.sora(12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(stack.subtitle)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(stack.status.title)
                            .font(.sora(9, weight: .medium))
                            .foregroundStyle(stack.status.trackColor)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(isExpanded ? "open" : stack.confidence.titleShort)
                            .font(.sora(9, weight: .medium))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(stackBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(stack.status.trackColor)
                        .frame(width: 3)
                        .clipShape(.rect(cornerRadius: 1.5))
                        .padding(.vertical, 8)
                }
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(stackStroke, lineWidth: isSelected || isExpanded ? 2 : 1))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("\(stack.nodes.count) \(stack.title) tool uses")
    }

    private var stackBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var stackStroke: Color {
        (isSelected || isExpanded) ? stack.status.trackColor.opacity(0.78) : Color.stxStroke.opacity(0.55)
    }
}

private struct TrackExpandedToolStackGrid: View {
    let stack: TrackToolStack
    let selectedNodeID: TrackNode.ID?
    var onSelectNode: (TrackNode) -> Void
    var onCollapse: () -> Void

    private static let cardWidth: CGFloat = 166
    private static let cardHeight: CGFloat = 106
    private static let gap: CGFloat = 12
    private static let headerHeight: CGFloat = 44
    private static let padding: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: AppIcon.Track.tools)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(stack.status.trackColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stack.title)
                        .font(.sora(12, weight: .semibold))
                        .lineLimit(1)
                    Text(stack.subtitle)
                        .font(.sora(9, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(action: onCollapse) {
                    Image(systemName: AppIcon.Action.close)
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxMuted)
                .background(Color.primary.opacity(0.055), in: Circle())
                .help("Collapse stack")
            }
            .frame(height: Self.headerHeight, alignment: .center)

            LazyVGrid(columns: columns, alignment: .leading, spacing: Self.gap) {
                ForEach(stack.nodes) { node in
                    TrackGraphNodeButton(
                        node: node,
                        isSelected: selectedNodeID == node.id,
                        usesSolidBackground: true
                    ) {
                        onSelectNode(node)
                    }
                    .frame(width: Self.cardWidth, height: Self.cardHeight)
                }
            }
        }
        .padding(Self.padding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(stack.status.trackColor.opacity(0.35), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.13), radius: 18, x: 0, y: 12)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(Self.cardWidth), spacing: Self.gap), count: Self.columnCount(for: stack.nodes.count))
    }

    static func size(for itemCount: Int) -> CGSize {
        let columns = columnCount(for: itemCount)
        let rows = max(1, Int(ceil(Double(max(1, itemCount)) / Double(columns))))
        let width = Self.padding * 2
            + CGFloat(columns) * Self.cardWidth
            + CGFloat(max(0, columns - 1)) * Self.gap
        let height = Self.padding * 2
            + Self.headerHeight
            + 10
            + CGFloat(rows) * Self.cardHeight
            + CGFloat(max(0, rows - 1)) * Self.gap
        return CGSize(width: width, height: height)
    }

    private static func columnCount(for itemCount: Int) -> Int {
        min(3, max(1, itemCount))
    }
}

private struct TrackEdgeLayer: View {
    let layout: TrackGraphLayout
    let edges: [TrackGraphDisplayEdge]
    let size: CGSize
    let focusedItemID: TrackGraphItem.ID?

    var body: some View {
        let drawableEdges = self.visibleEdges
        let ports = edgePorts(for: drawableEdges)
        Canvas { context, _ in
            for edge in drawableEdges {
                guard let start = layout.frames[edge.from],
                      let end = layout.frames[edge.to] else { continue }
                let route = routedPath(
                    for: edge,
                    start: start,
                    end: end,
                    fromY: ports.outgoingYByEdgeID[edge.id] ?? start.midY,
                    toY: ports.incomingYByEdgeID[edge.id] ?? end.midY
                )
                let isDimmed = focusedItemID != nil && edge.from != focusedItemID && edge.to != focusedItemID
                let baseOpacity = edge.role == .flow
                    ? (edge.confidence == .high ? 0.36 : 0.24)
                    : (edge.confidence == .high ? 0.22 : 0.14)
                let color = Color.primary.opacity(isDimmed ? 0.075 : baseOpacity)
                context.stroke(
                    route,
                    with: .color(color),
                    style: StrokeStyle(
                        lineWidth: isDimmed ? 0.8 : (edge.role == .flow ? 1.6 : 1),
                        lineCap: .round,
                        lineJoin: .round,
                        dash: edge.role == .flow ? [] : [4, 5]
                    )
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private var visibleEdges: [TrackGraphDisplayEdge] {
        edges.filter { edge in
            switch edge.visibility {
            case .overview:
                return true
            case .focusOnly:
                guard let focusedItemID else { return false }
                return edge.from == focusedItemID || edge.to == focusedItemID
            }
        }
    }

    private func edgePorts(for edges: [TrackGraphDisplayEdge]) -> TrackEdgePortLayout {
        var outgoing: [TrackGraphDisplayEdge.ID: CGFloat] = [:]
        var incoming: [TrackGraphDisplayEdge.ID: CGFloat] = [:]

        for (_, group) in Dictionary(grouping: edges, by: \.from) {
            guard let frame = group.first.flatMap({ layout.frames[$0.from] }) else { continue }
            let sorted = group.sorted { lhs, rhs in
                let lhsY = layout.frames[lhs.to]?.midY ?? 0
                let rhsY = layout.frames[rhs.to]?.midY ?? 0
                if lhsY != rhsY { return lhsY < rhsY }
                return lhs.id < rhs.id
            }
            for (index, edge) in sorted.enumerated() {
                outgoing[edge.id] = distributedPortY(in: frame, count: sorted.count, index: index)
            }
        }

        for (_, group) in Dictionary(grouping: edges, by: \.to) {
            guard let frame = group.first.flatMap({ layout.frames[$0.to] }) else { continue }
            let sorted = group.sorted { lhs, rhs in
                let lhsY = layout.frames[lhs.from]?.midY ?? 0
                let rhsY = layout.frames[rhs.from]?.midY ?? 0
                if lhsY != rhsY { return lhsY < rhsY }
                return lhs.id < rhs.id
            }
            for (index, edge) in sorted.enumerated() {
                incoming[edge.id] = distributedPortY(in: frame, count: sorted.count, index: index)
            }
        }

        return TrackEdgePortLayout(outgoingYByEdgeID: outgoing, incomingYByEdgeID: incoming)
    }

    private func distributedPortY(in frame: CGRect, count: Int, index: Int) -> CGFloat {
        guard count > 1 else { return frame.midY }
        let inset: CGFloat = min(22, frame.height * 0.22)
        let usableHeight = max(1, frame.height - inset * 2)
        return frame.minY + inset + usableHeight * CGFloat(index) / CGFloat(count - 1)
    }

    private func routedPath(
        for edge: TrackGraphDisplayEdge,
        start: CGRect,
        end: CGRect,
        fromY: CGFloat,
        toY: CGFloat
    ) -> Path {
        let fromColumn = layout.columns[edge.from] ?? 0
        let toColumn = layout.columns[edge.to] ?? 0
        let forward = toColumn > fromColumn || end.minX >= start.maxX

        let from = CGPoint(x: start.maxX, y: fromY)
        let to = CGPoint(x: forward ? end.minX : end.maxX, y: toY)
        let railX = forward
            ? (start.maxX + end.minX) / 2
            : max(start.maxX, end.maxX) + 30

        var path = Path()
        path.move(to: from)
        path.addLine(to: CGPoint(x: railX, y: from.y))
        path.addLine(to: CGPoint(x: railX, y: to.y))
        path.addLine(to: to)
        return path
    }
}

private struct TrackEdgePortLayout {
    let outgoingYByEdgeID: [TrackGraphDisplayEdge.ID: CGFloat]
    let incomingYByEdgeID: [TrackGraphDisplayEdge.ID: CGFloat]
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
                LazyVStack(alignment: .leading, spacing: 16) {
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
        let events = timelineEvents(for: node)
        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Events")
            ForEach(events) { event in
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

    private func timelineEvents(for node: TrackNode) -> [TrackEvent] {
        let eventIDs = Set(node.eventIDs)
        return Array(run.events.lazy.filter { eventIDs.contains($0.id) }.prefix(24))
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
