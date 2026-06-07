import Foundation
import SwiftUI

struct GanttTimelineOverviewPanel: View {
    let snapshot: GanttTimelineSnapshot
    @Binding var viewport: GanttTimelineViewport

    private var isInteractive: Bool {
        GanttTimelineViewportMetrics.overviewIsInteractive(range: snapshot.range, viewport: viewport)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("OVERVIEW")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer(minLength: 12)
                if isInteractive {
                    Text("Drag to move the visible period.")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    GanttOverviewCanvas(snapshot: snapshot)

                    if isInteractive {
                        GanttOverviewViewportControl(
                            viewport: $viewport,
                            overviewSize: proxy.size,
                            resetID: snapshot.renderRevisionID
                        )
                    }
                }
            }
            .frame(height: 58)
            .clipShape(.rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1)
            }
        }
        .mainWindowPanel(padding: 16)
    }
}

private enum GanttOverviewViewportDragSession: Equatable {
    case active(startOffsetX: CGFloat)
    case ignored
}

private struct GanttOverviewViewportControl: View {
    @Binding var viewport: GanttTimelineViewport
    let overviewSize: CGSize
    let resetID: String
    @State private var dragSession: GanttOverviewViewportDragSession?

    private var rect: CGRect {
        GanttTimelineViewportMetrics.overviewThumbRect(viewport: viewport, overviewSize: overviewSize)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            viewportThumb
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .contentShape(Rectangle())
                .accessibilityLabel(String(localized: "Visible timeline period"))

            Color.clear
                .frame(width: max(0, overviewSize.width), height: max(0, overviewSize.height))
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .accessibilityHidden(true)
        }
        .onChange(of: resetID) { _, _ in
            dragSession = nil
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragSession == nil {
                    let thumbRect = GanttTimelineViewportMetrics.overviewThumbHitRect(
                        viewport: viewport,
                        overviewSize: overviewSize
                    )
                    dragSession = thumbRect.contains(value.startLocation)
                        ? .active(startOffsetX: viewport.offsetX)
                        : .ignored
                }

                guard case .active(let startOffsetX) = dragSession else { return }
                let delta = GanttTimelineViewportMetrics.offsetDeltaForOverviewDrag(
                    translationX: value.translation.width,
                    overviewWidth: overviewSize.width,
                    viewport: viewport
                )
                viewport = viewport.withOffset(startOffsetX + delta)
            }
            .onEnded { _ in
                dragSession = nil
            }
    }

    @ViewBuilder
    private var viewportThumb: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

        shape
            .fill(Color.stxAccent.opacity(0.14))
            .overlay {
                shape.strokeBorder(Color.stxAccent.opacity(0.72), lineWidth: 1)
            }
    }
}

private struct GanttOverviewCanvas: View {
    let snapshot: GanttTimelineSnapshot

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.primary.opacity(0.025)))
            let rowCount = max(1, min(snapshot.projects.count, 8))
            let rowHeight = size.height / CGFloat(rowCount)
            for (index, project) in snapshot.projects.prefix(rowCount).enumerated() {
                let color = project.providerList.first == .codex
                    ? Color.stxAccent
                    : (project.providerList.first?.accentColor ?? Color.stxAccent)
                for segment in project.segments {
                    let startX = GanttTimelineScale.ratio(for: segment.interval.start, domain: snapshot.domain) * size.width
                    let endX = GanttTimelineScale.ratio(for: segment.interval.end, domain: snapshot.domain) * size.width
                    let rect = CGRect(
                        x: startX,
                        y: CGFloat(index) * rowHeight + 8,
                        width: max(2, endX - startX),
                        height: max(3, rowHeight - 14)
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(0.78)))
                }
            }
            if snapshot.domain.contains(Date.now) {
                let x = GanttTimelineScale.ratio(for: .now, domain: snapshot.domain) * size.width
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    path,
                    with: .color(Color.stxAccent.opacity(0.75)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
            }
        }
        .accessibilityLabel(String(localized: "Gantt overview"))
    }
}
