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

    static func overviewThumbRect(viewport: GanttTimelineViewport, overviewSize: CGSize) -> CGRect {
        let width = max(0, overviewSize.width)
        let height = max(0, overviewSize.height)
        guard width > 0, height > 0 else { return .zero }

        let thumbWidth = min(width, max(0, viewport.visibleWidthRatio * width))
        let maxX = max(0, width - thumbWidth)
        let x = min(max(0, viewport.visibleStartRatio * width), maxX)
        return CGRect(x: x, y: 0, width: thumbWidth, height: height)
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
