import Foundation
import Testing
@testable import ClaudeStats

@Suite("Usage limit segment layout")
struct UsageLimitSegmentLayoutTests {
    @Test("Zero usage leaves all segments remaining")
    func zeroUsageLeavesAllSegmentsRemaining() {
        let layout = UsageLimitSegmentLayout(usedPercent: 0)

        #expect(layout.usedSegmentCount == 0)
        #expect(layout.remainingSegmentCount == UsageLimitSegmentLayout.defaultSegmentCount)
    }

    @Test("Tiny non-zero usage reserves one used segment")
    func tinyNonZeroUsageReservesOneUsedSegment() {
        let layout = UsageLimitSegmentLayout(usedPercent: 0.1)

        #expect(layout.usedSegmentCount == 1)
        #expect(layout.remainingSegmentCount == UsageLimitSegmentLayout.defaultSegmentCount - 1)
    }

    @Test("Full or greater usage fills all used segments")
    func fullOrGreaterUsageFillsAllUsedSegments() {
        let layout = UsageLimitSegmentLayout(usedPercent: 140)

        #expect(layout.usedSegmentCount == UsageLimitSegmentLayout.defaultSegmentCount)
        #expect(layout.remainingSegmentCount == 0)
    }

    @Test("Negative usage clamps to zero used segments")
    func negativeUsageClampsToZeroUsedSegments() {
        let layout = UsageLimitSegmentLayout(usedPercent: -25)

        #expect(layout.clampedUsedPercent == 0)
        #expect(layout.usedSegmentCount == 0)
        #expect(layout.remainingSegmentCount == UsageLimitSegmentLayout.defaultSegmentCount)
    }

    @Test("Window card model exposes forecast summary")
    func windowCardModelExposesForecastSummary() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let resetAt = now.addingTimeInterval(86_400)
        let window = UsageLimitWindow(
            id: "secondary",
            label: "7d",
            usedPercent: 72,
            resetAt: resetAt,
            windowMinutes: UsageLimitWindowCatalog.sevenDayWindowMinutes
        )
        let forecast = UsageLimitForecast(
            provider: .codex,
            windowID: "secondary",
            label: "7d",
            capturedAt: now,
            currentUsedPercent: 72,
            resetAt: resetAt,
            reachInterval: DateInterval(start: now.addingTimeInterval(3_600), end: now.addingTimeInterval(5_400)),
            medianReachAt: now.addingTimeInterval(4_200),
            confidence: .medium,
            status: .forecast,
            diagnostics: []
        )

        let model = UsageLimitWindowCardModel(window: window, forecast: forecast)

        #expect(model.forecastText?.hasPrefix("ETA ") == true)
        #expect(model.forecastDetailText?.contains("Medium confidence") == true)
        #expect(model.forecastTintLevel == .forecast)
    }

    @Test("Window card model exposes collecting summary")
    func windowCardModelExposesCollectingSummary() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let resetAt = now.addingTimeInterval(86_400)
        let window = UsageLimitWindow(
            id: "secondary",
            label: "7d",
            usedPercent: 72,
            resetAt: resetAt,
            windowMinutes: UsageLimitWindowCatalog.sevenDayWindowMinutes
        )
        let forecast = UsageLimitForecast(
            provider: .codex,
            windowID: "secondary",
            label: "7d",
            capturedAt: now,
            currentUsedPercent: 72,
            resetAt: resetAt,
            reachInterval: nil,
            medianReachAt: nil,
            confidence: .low,
            status: .collecting,
            diagnostics: ["Collecting 7-day usage snapshots."]
        )

        let model = UsageLimitWindowCardModel(window: window, forecast: forecast)

        #expect(model.forecastText == "Prediction collecting data")
        #expect(model.forecastDetailText == "Collecting 7-day usage snapshots.")
        #expect(model.forecastTintLevel == .collecting)
    }
}
