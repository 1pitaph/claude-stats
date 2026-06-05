import ClaudeStatsCore
import XCTest

final class StatsGanttTimelineRenderPlanTests: XCTestCase {
    func testGroupsSegmentsIntoProjectRowsAndUsesTimeRatios() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(24 * 60 * 60)
        let timeline = StatsGanttTimeline(
            periodStart: start,
            periodEnd: end,
            segments: [
                segment(id: "a1", label: "Project A", start: start, end: start.addingTimeInterval(60 * 60), tokens: 100),
                segment(id: "b1", label: "Project B", start: start.addingTimeInterval(2 * 60 * 60), end: start.addingTimeInterval(6 * 60 * 60), tokens: 200),
                segment(id: "a2", label: "Project A", start: start.addingTimeInterval(8 * 60 * 60), end: start.addingTimeInterval(9 * 60 * 60), tokens: 300),
            ]
        )

        let plan = StatsGanttTimelineRenderPlan(timeline: timeline, calendar: utcCalendar)

        XCTAssertEqual(plan.domain.start, start)
        XCTAssertEqual(plan.domain.end, end)
        XCTAssertEqual(plan.segmentCount, 3)
        XCTAssertEqual(plan.rows.map(\.displayName), ["Project B", "Project A"])
        XCTAssertEqual(plan.rows[0].durationText, "4h")
        XCTAssertEqual(plan.rows[1].totalTokenCount, 400)
        XCTAssertEqual(plan.rows[1].segments.map(\.id), ["a1", "a2"])
        XCTAssertEqual(plan.rows[1].segments[0].startRatio, 0, accuracy: 0.0001)
        XCTAssertEqual(plan.rows[1].segments[0].endRatio, 1.0 / 24.0, accuracy: 0.0001)
    }

    func testClipsSegmentsToTimelineDomain() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(24 * 60 * 60)
        let timeline = StatsGanttTimeline(
            periodStart: start,
            periodEnd: end,
            segments: [
                segment(
                    id: "wide",
                    label: "Wide",
                    start: start.addingTimeInterval(-60 * 60),
                    end: end.addingTimeInterval(60 * 60),
                    tokens: 50
                ),
            ]
        )

        let plan = StatsGanttTimelineRenderPlan(timeline: timeline, calendar: utcCalendar)

        XCTAssertEqual(plan.rows.count, 1)
        XCTAssertEqual(plan.rows[0].segments[0].start, start)
        XCTAssertEqual(plan.rows[0].segments[0].end, end)
        XCTAssertEqual(plan.rows[0].segments[0].startRatio, 0, accuracy: 0.0001)
        XCTAssertEqual(plan.rows[0].segments[0].endRatio, 1, accuracy: 0.0001)
    }

    func testExpandsPartialDayDomainToFullCalendarDay() {
        let dayStart = Date(timeIntervalSince1970: 0)
        let periodStart = dayStart.addingTimeInterval(8 * 60 * 60)
        let periodEnd = dayStart.addingTimeInterval(13 * 60 * 60)
        let timeline = StatsGanttTimeline(
            periodStart: periodStart,
            periodEnd: periodEnd,
            segments: [
                segment(
                    id: "morning",
                    label: "Morning",
                    start: dayStart.addingTimeInterval(9 * 60 * 60),
                    end: dayStart.addingTimeInterval(10 * 60 * 60),
                    tokens: 50
                ),
            ]
        )

        let plan = StatsGanttTimelineRenderPlan(timeline: timeline, calendar: utcCalendar)

        XCTAssertEqual(plan.domain.start, dayStart)
        XCTAssertEqual(plan.domain.end, dayStart.addingTimeInterval(24 * 60 * 60))
        XCTAssertEqual(plan.rows[0].segments[0].startRatio, 9.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(plan.rows[0].segments[0].endRatio, 10.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(plan.ticks.filter(\.isMajor).prefix(3).map(\.label), ["00", "03", "06"])
        XCTAssertEqual(plan.ticks.filter(\.isMajor).last?.label, "21")
    }

    func testTimelineContentWidthExpandsForMultipleDays() {
        let start = Date(timeIntervalSince1970: 0)
        let domain = DateInterval(start: start, end: start.addingTimeInterval((6 * 24 + 12) * 60 * 60))

        let width = StatsGanttTimelineMetrics.contentWidth(
            domain: domain,
            viewportWidth: 320,
            minimumDayWidth: 156,
            calendar: utcCalendar
        )

        XCTAssertEqual(StatsGanttTimelineMetrics.calendarDaySpan(domain, calendar: utcCalendar), 7)
        XCTAssertGreaterThan(width, 1_000)
        XCTAssertEqual(width.truncatingRemainder(dividingBy: StatsGanttTimelineMetrics.widthStep), 0)
    }

    func testDefaultTimelineContentWidthKeepsSingleDayScrollable() {
        let start = Date(timeIntervalSince1970: 0)
        let domain = DateInterval(start: start, duration: 24 * 60 * 60)

        let width = StatsGanttTimelineMetrics.contentWidth(
            domain: domain,
            viewportWidth: 320,
            calendar: utcCalendar
        )

        XCTAssertEqual(width, 992)
        XCTAssertGreaterThan(width, 3 * 320)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func segment(
        id: String,
        label: String,
        providerID: String = "claude",
        start: Date,
        end: Date,
        tokens: Int
    ) -> StatsGanttSegment {
        StatsGanttSegment(
            id: id,
            label: label,
            providerID: providerID,
            start: start,
            end: end,
            tokenCount: tokens
        )
    }
}
