import CoreGraphics
import Foundation

struct GanttTimelineViewport: Equatable, Sendable {
    var contentWidth: CGFloat
    var viewportWidth: CGFloat
    var offsetX: CGFloat

    init(contentWidth: CGFloat = 0, viewportWidth: CGFloat = 0, offsetX: CGFloat = 0) {
        self.contentWidth = Self.sanitized(contentWidth)
        self.viewportWidth = Self.sanitized(viewportWidth)
        self.offsetX = Self.clampedOffset(
            Self.sanitized(offsetX),
            contentWidth: self.contentWidth,
            viewportWidth: self.viewportWidth
        )
    }

    var maxOffsetX: CGFloat {
        max(0, contentWidth - viewportWidth)
    }

    var isScrollable: Bool {
        maxOffsetX > 1
    }

    var visibleStartRatio: CGFloat {
        guard contentWidth > 0 else { return 0 }
        return clampedOffset(offsetX) / contentWidth
    }

    var visibleWidthRatio: CGFloat {
        guard contentWidth > 0, viewportWidth > 0 else { return 0 }
        return min(1, viewportWidth / contentWidth)
    }

    func clampedOffset(_ offset: CGFloat) -> CGFloat {
        Self.clampedOffset(offset, contentWidth: contentWidth, viewportWidth: viewportWidth)
    }

    func withDimensions(contentWidth: CGFloat, viewportWidth: CGFloat) -> GanttTimelineViewport {
        GanttTimelineViewport(
            contentWidth: contentWidth,
            viewportWidth: viewportWidth,
            offsetX: offsetX
        )
    }

    func withOffset(_ offset: CGFloat) -> GanttTimelineViewport {
        GanttTimelineViewport(
            contentWidth: contentWidth,
            viewportWidth: viewportWidth,
            offsetX: offset
        )
    }

    static func clampedOffset(_ offset: CGFloat, contentWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        let maxOffset = max(0, sanitized(contentWidth) - sanitized(viewportWidth))
        return min(max(0, sanitized(offset)), maxOffset)
    }

    private static func sanitized(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return 0 }
        return value
    }
}

enum GanttTimelineViewportMetrics {
    static let widthStep: CGFloat = 16
    static let dayTimelineMinimumWidth: CGFloat = 980
    static let overviewThumbHitSlop: CGFloat = 6

    static func contentWidth(range: GanttRange, domain: DateInterval, viewportWidth: CGFloat) -> CGFloat {
        let dayWidth = dayContentWidth(viewportWidth: viewportWidth)
        switch range {
        case .day:
            return dayWidth
        case .week, .month:
            return CGFloat(calendarDaySpan(domain)) * dayWidth
        }
    }

    static func dayContentWidth(viewportWidth: CGFloat) -> CGFloat {
        bucketedWidth(for: viewportWidth, minimum: dayTimelineMinimumWidth)
    }

    static func bucketedWidth(for rawWidth: CGFloat, minimum: CGFloat) -> CGFloat {
        let width = max(rawWidth, minimum)
        let bucket = (width / widthStep).rounded(.up) * widthStep
        return max(minimum, bucket)
    }

    static func calendarDaySpan(_ interval: DateInterval, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1
        return max(1, days)
    }

    static func overviewIsInteractive(range: GanttRange, viewport: GanttTimelineViewport) -> Bool {
        range != .day && viewport.isScrollable
    }

    static func shouldPublishViewportChange(
        from current: GanttTimelineViewport,
        to next: GanttTimelineViewport
    ) -> Bool {
        guard current != next else { return false }
        guard current.contentWidth > 0, next.contentWidth > 0 else { return true }
        if abs(current.contentWidth - next.contentWidth) > 0.5 { return true }
        if abs(current.offsetX - next.offsetX) > 0.5 { return true }
        if current.isScrollable != next.isScrollable { return true }
        return abs(current.viewportWidth - next.viewportWidth) >= widthStep / 2
    }

    static func overviewThumbRect(viewport: GanttTimelineViewport, overviewSize: CGSize) -> CGRect {
        let width = max(0, overviewSize.width)
        let height = max(0, overviewSize.height)
        guard width > 0, height > 0 else { return .zero }

        let thumbWidth = min(width, max(0, viewport.visibleWidthRatio * width))
        let maxX = max(0, width - thumbWidth)
        let x = min(max(0, viewport.visibleStartRatio * width), maxX)
        return CGRect(x: x, y: 0, width: thumbWidth, height: height)
    }

    static func overviewThumbHitRect(
        viewport: GanttTimelineViewport,
        overviewSize: CGSize,
        horizontalSlop: CGFloat = overviewThumbHitSlop
    ) -> CGRect {
        let rect = overviewThumbRect(viewport: viewport, overviewSize: overviewSize)
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return rect.insetBy(dx: -max(0, horizontalSlop), dy: 0)
    }

    static func offsetDeltaForOverviewDrag(
        translationX: CGFloat,
        overviewWidth: CGFloat,
        viewport: GanttTimelineViewport
    ) -> CGFloat {
        guard overviewWidth > 0, viewport.contentWidth > 0 else { return 0 }
        return translationX * viewport.contentWidth / overviewWidth
    }

    static func offsetForOverviewThumbX(
        _ thumbX: CGFloat,
        overviewWidth: CGFloat,
        viewport: GanttTimelineViewport
    ) -> CGFloat {
        guard overviewWidth > 0, viewport.contentWidth > 0 else { return 0 }
        return viewport.clampedOffset(thumbX * viewport.contentWidth / overviewWidth)
    }
}

enum GanttAdaptiveLayoutMetrics {
    static let compactSwitchHysteresis: CGFloat = 16

    static func isCompact(width: CGFloat, threshold: CGFloat) -> Bool {
        width.isFinite && width > 0 && width < threshold
    }

    static func shouldUpdateCompactState(
        current: Bool,
        width: CGFloat,
        threshold: CGFloat,
        hysteresis: CGFloat = 0
    ) -> Bool {
        current != compactState(
            current: current,
            width: width,
            threshold: threshold,
            hysteresis: hysteresis
        )
    }

    private static func compactState(
        current: Bool,
        width: CGFloat,
        threshold: CGFloat,
        hysteresis: CGFloat
    ) -> Bool {
        guard width.isFinite, width > 0 else { return current }

        let band = max(0, hysteresis)
        if current {
            return width <= threshold + band
        }
        return width < threshold - band
    }
}

enum GanttTimelineHitTargetGeometry {
    static func rect(
        startRatio: CGFloat,
        endRatio: CGFloat,
        rowIndex: Int,
        rowHeight: CGFloat,
        timelineWidth: CGFloat
    ) -> CGRect? {
        guard timelineWidth > 0, rowHeight > 0, rowIndex >= 0 else { return nil }
        let startX = startRatio * timelineWidth
        let endX = endRatio * timelineWidth
        let barWidth = min(timelineWidth - startX, max(3, endX - startX))
        let visibleStartX = min(max(startX, 0), timelineWidth)
        let visibleEndX = min(max(startX + barWidth, 0), timelineWidth)
        let visibleWidth = max(0, visibleEndX - visibleStartX)
        guard visibleWidth > 0 else { return nil }

        let hitWidth = max(8, visibleWidth)
        let rowY = CGFloat(rowIndex) * rowHeight
        return CGRect(
            x: visibleStartX + visibleWidth / 2 - hitWidth / 2,
            y: rowY,
            width: hitWidth,
            height: rowHeight
        )
    }
}
