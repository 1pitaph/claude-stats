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

    @Test("overview interactivity is limited to scrollable week month views")
    func overviewInteractivityRequiresScrollableWeekOrMonth() {
        let scrollable = GanttTimelineViewport(contentWidth: 6_860, viewportWidth: 980)
        let staticViewport = GanttTimelineViewport(contentWidth: 980, viewportWidth: 980)

        #expect(GanttTimelineViewportMetrics.overviewIsInteractive(range: .day, viewport: scrollable) == false)
        #expect(GanttTimelineViewportMetrics.overviewIsInteractive(range: .week, viewport: scrollable) == true)
        #expect(GanttTimelineViewportMetrics.overviewIsInteractive(range: .month, viewport: scrollable) == true)
        #expect(GanttTimelineViewportMetrics.overviewIsInteractive(range: .week, viewport: staticViewport) == false)
    }
}
