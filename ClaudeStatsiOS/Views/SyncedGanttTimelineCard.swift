import ClaudeStatsCore
import SwiftUI

struct SyncedGanttTimelineCard: View {
    let timeline: StatsGanttTimeline

    private let headerHeight: CGFloat = 36
    private let leftColumnWidth: CGFloat = 118
    private let rowHeight: CGFloat = 48

    private var plan: StatsGanttTimelineRenderPlan {
        StatsGanttTimelineRenderPlan(timeline: timeline)
    }

    var body: some View {
        let plan = plan

        VStack(alignment: .leading, spacing: 12) {
            header(plan)

            if plan.isEmpty {
                Text("Timeline frame ready. No synced work blocks yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .center)
            } else {
                chart(plan)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func header(_ plan: StatsGanttTimelineRenderPlan) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titleBlock(plan)
                Spacer(minLength: 12)
                Text(plan.rangeText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                titleBlock(plan)
                Text(plan.rangeText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func titleBlock(_ plan: StatsGanttTimelineRenderPlan) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Gantt Timeline")
                .font(.headline)
            Text("\(plan.rows.count) projects - \(plan.segmentCount) work blocks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chart(_ plan: StatsGanttTimelineRenderPlan) -> some View {
        let rowsHeight = CGFloat(plan.rows.count) * rowHeight
        let totalHeight = headerHeight + rowsHeight

        return GeometryReader { proxy in
            let viewportWidth = max(0, proxy.size.width - leftColumnWidth)
            let timelineWidth = StatsGanttTimelineMetrics.contentWidth(
                domain: plan.domain,
                viewportWidth: viewportWidth
            )

            HStack(alignment: .top, spacing: 0) {
                projectColumn(plan)
                    .frame(width: leftColumnWidth, height: totalHeight, alignment: .top)

                ScrollView(.horizontal) {
                    timelineDocument(plan)
                        .frame(width: timelineWidth, height: totalHeight, alignment: .topLeading)
                }
                .scrollIndicators(.visible)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: totalHeight, maxHeight: totalHeight)
            }
        }
        .frame(height: totalHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.55), lineWidth: 1)
        }
    }

    private func projectColumn(_ plan: StatsGanttTimelineRenderPlan) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Project")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("Active")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: headerHeight)
            .background(Color.primary.opacity(0.035))

            ForEach(plan.rows) { row in
                projectRow(row)
                    .frame(height: rowHeight)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.35))
                            .frame(height: 0.5)
                    }
            }
        }
        .background(Color.primary.opacity(0.02))
    }

    private func projectRow(_ row: StatsGanttTimelineRenderPlan.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 5) {
                ProviderDots(providerIDs: row.providerIDs)
                Text(row.durationText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(row.tokenText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.displayName), \(row.durationText) active, \(row.tokenText) tokens")
    }

    private func timelineDocument(_ plan: StatsGanttTimelineRenderPlan) -> some View {
        VStack(spacing: 0) {
            SyncedGanttTimelineHeader(plan: plan)
                .frame(height: headerHeight)
            SyncedGanttTimelineCanvas(plan: plan, rowHeight: rowHeight)
                .frame(height: CGFloat(plan.rows.count) * rowHeight)
        }
    }
}

private struct ProviderDots: View {
    let providerIDs: [String]

    var body: some View {
        HStack(spacing: -2) {
            ForEach(Array(providerIDs.prefix(3).enumerated()), id: \.offset) { _, providerID in
                Circle()
                    .fill(ganttProviderColor(providerID))
                    .frame(width: 7, height: 7)
                    .overlay {
                        Circle()
                            .stroke(Color(.secondarySystemGroupedBackground), lineWidth: 1)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SyncedGanttTimelineHeader: View {
    let plan: StatsGanttTimelineRenderPlan

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.primary.opacity(0.035)))

            for tick in plan.ticks {
                let x = tick.ratio * size.width
                var line = Path()
                line.move(to: CGPoint(x: x, y: tick.isMajor ? size.height - 12 : size.height - 7))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    line,
                    with: .color(Color(.separator).opacity(tick.isMajor ? 0.72 : 0.32)),
                    lineWidth: tick.isMajor ? 1 : 0.5
                )

                if tick.isMajor, !tick.label.isEmpty {
                    let trailingInset: CGFloat = tick.label.count <= 2 ? 18 : 54
                    context.draw(
                        Text(tick.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary),
                        at: CGPoint(x: min(max(x + 4, 4), max(4, size.width - trailingInset)), y: 13),
                        anchor: .leading
                    )
                }
            }

            var bottom = Path()
            bottom.move(to: CGPoint(x: 0, y: size.height - 0.5))
            bottom.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(bottom, with: .color(Color(.separator).opacity(0.55)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct SyncedGanttTimelineCanvas: View {
    let plan: StatsGanttTimelineRenderPlan
    let rowHeight: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            drawGrid(context: &context, size: size)
            drawBars(context: &context, size: size)
            drawNowLine(context: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        for index in 0...plan.rows.count {
            let y = CGFloat(index) * rowHeight
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(Color(.separator).opacity(0.35)), lineWidth: 0.5)
        }

        for tick in plan.ticks {
            let x = tick.ratio * size.width
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(
                line,
                with: .color(Color(.separator).opacity(tick.isMajor ? 0.58 : 0.22)),
                lineWidth: tick.isMajor ? 1 : 0.5
            )
        }
    }

    private func drawBars(context: inout GraphicsContext, size: CGSize) {
        for row in plan.rows {
            for segment in row.segments {
                let startX = segment.startRatio * size.width
                let endX = segment.endRatio * size.width
                let visibleStartX = min(max(startX, 0), size.width)
                let visibleEndX = min(max(endX, 0), size.width)
                let width = max(3, visibleEndX - visibleStartX)
                guard visibleStartX < size.width, visibleEndX > 0 else { continue }

                let color = ganttProviderColor(segment.providerID)
                let height = 10 + CGFloat(segment.tokenIntensity) * 6
                let y = CGFloat(row.index) * rowHeight + (rowHeight - height) / 2
                let rect = CGRect(x: visibleStartX, y: y, width: width, height: height)
                let fillOpacity = 0.48 + min(0.44, segment.tokenIntensity * 0.44)
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(color.opacity(fillOpacity)))
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3.5),
                    with: .color(color),
                    lineWidth: 1
                )
            }
        }
    }

    private func drawNowLine(context: inout GraphicsContext, size: CGSize) {
        let now = Date.now
        guard plan.domain.contains(now) else { return }

        let x = plan.ratio(for: now) * size.width
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(
            line,
            with: .color(Color.accentColor.opacity(0.72)),
            style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])
        )
    }
}

private func ganttProviderColor(_ providerID: String) -> Color {
    switch providerID {
    case "claude":
        Color(red: 0.85, green: 0.45, blue: 0.20)
    case "codex":
        Color.accentColor
    case "gemini":
        Color(red: 0.19, green: 0.53, blue: 1.0)
    case "kimi":
        Color(red: 0.20, green: 0.20, blue: 0.22)
    case "minimax":
        Color(red: 0.92, green: 0.30, blue: 0.26)
    default:
        Color.teal
    }
}
