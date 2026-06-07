import CoreGraphics
import Foundation
import Testing
@testable import ClaudeStats

@Suite("Gantt timeline viewport")
struct GanttTimelineViewportTests {
    @Test("content width keeps day width and expands week month by day")
    func contentWidthExpandsWeekAndMonthByDay() {
        let weekDomain = DateInterval(
            start: Date(timeIntervalSince1970: 0),
            duration: 7 * 86_400
        )
        let monthDomain = DateInterval(
            start: Date(timeIntervalSince1970: 0),
            duration: 30 * 86_400
        )
        let dayWidth = GanttTimelineViewportMetrics.dayContentWidth(viewportWidth: 940)

        #expect(dayWidth == 992)
        #expect(GanttTimelineViewportMetrics.contentWidth(range: .day, domain: weekDomain, viewportWidth: 940) == dayWidth)
        #expect(GanttTimelineViewportMetrics.contentWidth(range: .week, domain: weekDomain, viewportWidth: 940) == dayWidth * 7)
        #expect(GanttTimelineViewportMetrics.contentWidth(range: .month, domain: monthDomain, viewportWidth: 940) == dayWidth * 30)
    }

    @Test("overview thumb ratios follow viewport dimensions")
    func overviewThumbRatiosFollowViewportDimensions() {
        let viewport = GanttTimelineViewport(contentWidth: 6_860, viewportWidth: 980, offsetX: 1_960)
        let rect = GanttTimelineViewportMetrics.overviewThumbRect(
            viewport: viewport,
            overviewSize: CGSize(width: 700, height: 58)
        )

        #expect(rect.origin.x == 200)
        #expect(rect.width == 100)
        #expect(rect.height == 58)
    }

    @Test("overview thumb hit rect includes horizontal slop")
    func overviewThumbHitRectIncludesHorizontalSlop() {
        let viewport = GanttTimelineViewport(contentWidth: 6_860, viewportWidth: 980, offsetX: 1_960)
        let rect = GanttTimelineViewportMetrics.overviewThumbHitRect(
            viewport: viewport,
            overviewSize: CGSize(width: 700, height: 58)
        )

        #expect(GanttTimelineViewportMetrics.overviewThumbHitSlop == 6)
        #expect(rect.origin.x == 194)
        #expect(rect.width == 112)
        #expect(rect.height == 58)
    }

    @Test("overview thumb hit rect excludes starts outside slop")
    func overviewThumbHitRectExcludesStartsOutsideSlop() {
        let viewport = GanttTimelineViewport(contentWidth: 6_860, viewportWidth: 980, offsetX: 1_960)
        let rect = GanttTimelineViewportMetrics.overviewThumbHitRect(
            viewport: viewport,
            overviewSize: CGSize(width: 700, height: 58)
        )

        #expect(rect.contains(CGPoint(x: 194, y: 20)))
        #expect(rect.contains(CGPoint(x: 305, y: 20)))
        #expect(rect.contains(CGPoint(x: 193, y: 20)) == false)
        #expect(rect.contains(CGPoint(x: 306, y: 20)) == false)
    }

    @Test("overview drag maps to clamped timeline offset")
    func overviewDragMapsToTimelineOffset() {
        let viewport = GanttTimelineViewport(contentWidth: 6_860, viewportWidth: 980, offsetX: 1_960)
        let delta = GanttTimelineViewportMetrics.offsetDeltaForOverviewDrag(
            translationX: 100,
            overviewWidth: 700,
            viewport: viewport
        )

        #expect(delta == 980)
        #expect(viewport.withOffset(viewport.offsetX + delta).offsetX == 2_940)
        #expect(viewport.withOffset(10_000).offsetX == 5_880)
    }

    @Test("overview geometry handles zero dimensions and clamps offsets")
    func overviewGeometryHandlesZeroDimensionsAndClampsOffsets() {
        let viewport = GanttTimelineViewport(contentWidth: 6_860, viewportWidth: 980, offsetX: 1_960)
        let emptyViewport = GanttTimelineViewport(contentWidth: 0, viewportWidth: 980, offsetX: 320)

        #expect(GanttTimelineViewportMetrics.overviewThumbRect(
            viewport: viewport,
            overviewSize: .zero
        ) == .zero)
        #expect(GanttTimelineViewportMetrics.overviewThumbHitRect(
            viewport: viewport,
            overviewSize: .zero
        ) == .zero)
        #expect(GanttTimelineViewportMetrics.offsetDeltaForOverviewDrag(
            translationX: 100,
            overviewWidth: 0,
            viewport: viewport
        ) == 0)
        #expect(GanttTimelineViewportMetrics.offsetForOverviewThumbX(
            100,
            overviewWidth: 0,
            viewport: viewport
        ) == 0)
        #expect(emptyViewport.offsetX == 0)
        #expect(viewport.withOffset(-100).offsetX == 0)
        #expect(viewport.withOffset(10_000).offsetX == viewport.maxOffsetX)
    }

    @Test("overview interactivity is limited to scrollable week month views")
    func overviewInteractivityRequiresScrollableWeekOrMonth() {
        let scrollable = GanttTimelineViewport(contentWidth: 6_860, viewportWidth: 980)
        let staticViewport = GanttTimelineViewport(contentWidth: 980, viewportWidth: 980)

        #expect(GanttTimelineViewportMetrics.overviewIsInteractive(range: .day, viewport: scrollable) == false)
        #expect(GanttTimelineViewportMetrics.overviewIsInteractive(range: .week, viewport: scrollable) == true)
        #expect(GanttTimelineViewportMetrics.overviewIsInteractive(range: .month, viewport: scrollable) == true)
        #expect(GanttTimelineViewportMetrics.overviewIsInteractive(range: .week, viewport: staticViewport) == false)
    }

    @Test("viewport publish threshold ignores small resize noise but preserves semantic changes")
    func viewportPublishThresholdKeepsSemanticChanges() {
        let base = GanttTimelineViewport(contentWidth: 6_860, viewportWidth: 980, offsetX: 320)

        #expect(GanttTimelineViewportMetrics.shouldPublishViewportChange(
            from: base,
            to: GanttTimelineViewport(contentWidth: 6_860, viewportWidth: 983, offsetX: 320)
        ) == false)
        #expect(GanttTimelineViewportMetrics.shouldPublishViewportChange(
            from: base,
            to: GanttTimelineViewport(contentWidth: 6_860, viewportWidth: 988, offsetX: 320)
        ) == true)
        #expect(GanttTimelineViewportMetrics.shouldPublishViewportChange(
            from: base,
            to: GanttTimelineViewport(contentWidth: 6_876, viewportWidth: 980, offsetX: 320)
        ) == true)
        #expect(GanttTimelineViewportMetrics.shouldPublishViewportChange(
            from: base,
            to: GanttTimelineViewport(contentWidth: 6_860, viewportWidth: 980, offsetX: 321)
        ) == true)
        #expect(GanttTimelineViewportMetrics.shouldPublishViewportChange(
            from: GanttTimelineViewport(contentWidth: 980, viewportWidth: 980),
            to: GanttTimelineViewport(contentWidth: 981, viewportWidth: 980)
        ) == true)
    }

    @Test("hit target geometry preserves row position and minimum tap width")
    func hitTargetGeometryPreservesRowAndMinimumWidth() {
        let normal = GanttTimelineHitTargetGeometry.rect(
            startRatio: 0.10,
            endRatio: 0.20,
            rowIndex: 2,
            rowHeight: 46,
            timelineWidth: 1_000
        )
        let tiny = GanttTimelineHitTargetGeometry.rect(
            startRatio: 0.50,
            endRatio: 0.501,
            rowIndex: 1,
            rowHeight: 46,
            timelineWidth: 1_000
        )

        #expect(normal == CGRect(x: 100, y: 92, width: 100, height: 46))
        #expect(tiny == CGRect(x: 497.5, y: 46, width: 8, height: 46))
    }

    @Test("adaptive compact metrics only update when crossing the threshold")
    func adaptiveCompactMetricsGateResizeNoise() {
        #expect(GanttAdaptiveLayoutMetrics.isCompact(width: 720, threshold: 760) == true)
        #expect(GanttAdaptiveLayoutMetrics.isCompact(width: 760, threshold: 760) == false)
        #expect(GanttAdaptiveLayoutMetrics.isCompact(width: 820, threshold: 760) == false)
        #expect(GanttAdaptiveLayoutMetrics.isCompact(width: 0, threshold: 760) == false)

        #expect(GanttAdaptiveLayoutMetrics.shouldUpdateCompactState(current: false, width: 820, threshold: 760) == false)
        #expect(GanttAdaptiveLayoutMetrics.shouldUpdateCompactState(current: false, width: 720, threshold: 760) == true)
        #expect(GanttAdaptiveLayoutMetrics.shouldUpdateCompactState(current: true, width: 720, threshold: 760) == false)
        #expect(GanttAdaptiveLayoutMetrics.shouldUpdateCompactState(current: true, width: 820, threshold: 760) == true)
    }

    @Test("adaptive compact metrics can keep a hysteresis band around threshold")
    func adaptiveCompactMetricsKeepHysteresisBand() {
        let hysteresis: CGFloat = 16

        #expect(GanttAdaptiveLayoutMetrics.shouldUpdateCompactState(
            current: false,
            width: 752,
            threshold: 760,
            hysteresis: hysteresis
        ) == false)
        #expect(GanttAdaptiveLayoutMetrics.shouldUpdateCompactState(
            current: false,
            width: 743,
            threshold: 760,
            hysteresis: hysteresis
        ) == true)
        #expect(GanttAdaptiveLayoutMetrics.shouldUpdateCompactState(
            current: true,
            width: 768,
            threshold: 760,
            hysteresis: hysteresis
        ) == false)
        #expect(GanttAdaptiveLayoutMetrics.shouldUpdateCompactState(
            current: true,
            width: 777,
            threshold: 760,
            hysteresis: hysteresis
        ) == true)
    }
}
