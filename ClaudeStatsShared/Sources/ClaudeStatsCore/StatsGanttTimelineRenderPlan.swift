import CoreGraphics
import Foundation

public struct StatsGanttTimelineRenderPlan: Equatable {
    public struct Tick: Equatable {
        public let date: Date
        public let ratio: CGFloat
        public let label: String
        public let isMajor: Bool
    }

    public struct Segment: Equatable, Identifiable {
        public let id: String
        public let label: String
        public let providerID: String
        public let start: Date
        public let end: Date
        public let startRatio: CGFloat
        public let endRatio: CGFloat
        public let tokenIntensity: Double
        public let tokenCount: Int

        public var duration: TimeInterval {
            end.timeIntervalSince(start)
        }
    }

    public struct Row: Equatable, Identifiable {
        public let id: String
        public let index: Int
        public let displayName: String
        public let providerIDs: [String]
        public let durationText: String
        public let tokenText: String
        public let totalDuration: TimeInterval
        public let totalTokenCount: Int
        public let latestActivity: Date
        public let segments: [Segment]
    }

    public let domain: DateInterval
    public let ticks: [Tick]
    public let rows: [Row]
    public let segmentCount: Int

    public var isEmpty: Bool {
        rows.isEmpty
    }

    public var rangeText: String {
        "\(StatsFormat.day(domain.start)) - \(StatsFormat.day(domain.end.addingTimeInterval(-1)))"
    }

    public init(
        timeline: StatsGanttTimeline,
        rowLimit: Int? = nil,
        calendar: Calendar = .current
    ) {
        let domain = Self.domain(for: timeline, calendar: calendar)
        self.domain = domain
        self.ticks = Self.ticks(for: domain, calendar: calendar)

        let clippedSegments = timeline.segments.compactMap { segment -> MutableSegment? in
            let start = max(segment.start, domain.start)
            let end = min(segment.end, domain.end)
            guard end > start else { return nil }
            return MutableSegment(
                id: segment.id,
                label: Self.displayName(for: segment),
                providerID: segment.providerID,
                start: start,
                end: end,
                tokenCount: max(0, segment.tokenCount)
            )
        }

        let maxSegmentTokens = max(1, clippedSegments.map(\.tokenCount).max() ?? 0)
        var rowsByKey: [String: MutableRow] = [:]

        for (index, segment) in clippedSegments.enumerated() {
            let key = Self.rowKey(for: segment)
            if rowsByKey[key] == nil {
                rowsByKey[key] = MutableRow(
                    id: key,
                    displayName: segment.label,
                    providerIDs: [],
                    firstIndex: index,
                    totalDuration: 0,
                    totalTokenCount: 0,
                    latestActivity: segment.end,
                    segments: []
                )
            }

            var row = rowsByKey[key]!
            row.append(segment)
            rowsByKey[key] = row
        }

        let sortedMutableRows = rowsByKey.values.sorted { lhs, rhs in
            if lhs.totalDuration != rhs.totalDuration {
                return lhs.totalDuration > rhs.totalDuration
            }
            if lhs.latestActivity != rhs.latestActivity {
                return lhs.latestActivity > rhs.latestActivity
            }
            if lhs.firstIndex != rhs.firstIndex {
                return lhs.firstIndex < rhs.firstIndex
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        let limitedRows: ArraySlice<MutableRow>
        if let rowLimit, rowLimit >= 0 {
            limitedRows = sortedMutableRows.prefix(rowLimit)
        } else {
            limitedRows = sortedMutableRows[...]
        }

        self.rows = limitedRows.enumerated().map { rowIndex, row in
            let segments = row.segments
                .sorted { lhs, rhs in
                    if lhs.start != rhs.start { return lhs.start < rhs.start }
                    return lhs.id < rhs.id
                }
                .map { segment in
                    let startRatio = Self.ratio(for: segment.start, domain: domain)
                    let endRatio = Self.ratio(for: segment.end, domain: domain)
                    return Segment(
                        id: segment.id,
                        label: segment.label,
                        providerID: segment.providerID,
                        start: segment.start,
                        end: segment.end,
                        startRatio: startRatio,
                        endRatio: endRatio,
                        tokenIntensity: min(1, max(0.12, Double(segment.tokenCount) / Double(maxSegmentTokens))),
                        tokenCount: segment.tokenCount
                    )
                }

            return Row(
                id: row.id,
                index: rowIndex,
                displayName: row.displayName,
                providerIDs: row.providerIDs,
                durationText: StatsFormat.duration(row.totalDuration),
                tokenText: StatsFormat.tokens(row.totalTokenCount),
                totalDuration: row.totalDuration,
                totalTokenCount: row.totalTokenCount,
                latestActivity: row.latestActivity,
                segments: segments
            )
        }
        self.segmentCount = self.rows.reduce(0) { $0 + $1.segments.count }
    }

    public func ratio(for date: Date) -> CGFloat {
        Self.ratio(for: date, domain: domain)
    }

    private static func domain(for timeline: StatsGanttTimeline, calendar: Calendar) -> DateInterval {
        let now = Date.now
        let fallbackStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(-6 * 86_400)

        let segmentStart = timeline.segments.map(\.start).min()
        let segmentEnd = timeline.segments.map(\.end).max()
        let rawStart = timeline.periodStart ?? segmentStart ?? fallbackStart
        let rawEnd = timeline.periodEnd ?? segmentEnd ?? now
        let boundedEnd = rawEnd > rawStart ? rawEnd : rawStart.addingTimeInterval(3_600)
        let start = calendar.startOfDay(for: rawStart)
        let end = calendarDayEnd(for: boundedEnd, rawStart: rawStart, calendar: calendar)
        return DateInterval(start: start, end: end)
    }

    private static func calendarDayEnd(for rawEnd: Date, rawStart: Date, calendar: Calendar) -> Date {
        let endDayStart = calendar.startOfDay(for: rawEnd)
        let isExclusiveDayBoundary = rawEnd > rawStart && abs(rawEnd.timeIntervalSince(endDayStart)) < 0.001
        if isExclusiveDayBoundary {
            return endDayStart
        }

        return calendar.date(byAdding: .day, value: 1, to: endDayStart)
            ?? rawEnd.addingTimeInterval(86_400)
    }

    private static func displayName(for segment: StatsGanttSegment) -> String {
        let trimmed = segment.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Project" : trimmed
    }

    private static func rowKey(for segment: MutableSegment) -> String {
        let trimmed = segment.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "project|\(segment.id)"
        }
        return "project|\(trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))"
    }

    private static func ratio(for date: Date, domain: DateInterval) -> CGFloat {
        guard domain.duration > 0 else { return 0 }
        let ratio = date.timeIntervalSince(domain.start) / domain.duration
        return min(1, max(0, CGFloat(ratio)))
    }

    private static func ticks(for domain: DateInterval, calendar: Calendar) -> [Tick] {
        let daySpan = StatsGanttTimelineMetrics.calendarDaySpan(domain, calendar: calendar)
        let strideHours = daySpan > 1 ? 6 : 1
        var cursor = calendar.dateInterval(of: .hour, for: domain.start)?.start ?? domain.start
        var out: [Tick] = []

        while cursor < domain.end {
            let hour = calendar.component(.hour, from: cursor)
            if daySpan <= 1 || hour.isMultiple(of: strideHours) {
                let isMajor = daySpan <= 1 ? hour.isMultiple(of: 3) : hour == 0
                out.append(
                    Tick(
                        date: cursor,
                        ratio: ratio(for: cursor, domain: domain),
                        label: isMajor ? tickLabel(for: cursor, daySpan: daySpan, calendar: calendar) : "",
                        isMajor: isMajor
                    )
                )
            }

            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor), next > cursor else {
                break
            }
            cursor = next
        }

        return out
    }

    private static func tickLabel(for date: Date, daySpan: Int, calendar: Calendar) -> String {
        if daySpan > 1 {
            return StatsFormat.day(date)
        }
        return String(format: "%02d", calendar.component(.hour, from: date))
    }

    private struct MutableSegment {
        let id: String
        let label: String
        let providerID: String
        let start: Date
        let end: Date
        let tokenCount: Int
    }

    private struct MutableRow {
        let id: String
        let displayName: String
        var providerIDs: [String]
        let firstIndex: Int
        var totalDuration: TimeInterval
        var totalTokenCount: Int
        var latestActivity: Date
        var segments: [MutableSegment]

        mutating func append(_ segment: MutableSegment) {
            if !segment.providerID.isEmpty && !providerIDs.contains(segment.providerID) {
                providerIDs.append(segment.providerID)
            }
            totalDuration += segment.end.timeIntervalSince(segment.start)
            totalTokenCount += segment.tokenCount
            if segment.end > latestActivity {
                latestActivity = segment.end
            }
            segments.append(segment)
        }
    }
}

public enum StatsGanttTimelineMetrics {
    public static let defaultMinimumDayWidth: CGFloat = 980
    public static let widthStep: CGFloat = 16

    public static func contentWidth(
        domain: DateInterval,
        viewportWidth: CGFloat,
        minimumDayWidth: CGFloat = defaultMinimumDayWidth,
        calendar: Calendar = .current
    ) -> CGFloat {
        let days = calendarDaySpan(domain, calendar: calendar)
        let rawWidth = CGFloat(days) * max(1, minimumDayWidth)
        let minimumWidth = max(0, viewportWidth)
        let width = max(rawWidth, minimumWidth)
        return bucketedWidth(width)
    }

    public static func calendarDaySpan(_ interval: DateInterval, calendar: Calendar = .current) -> Int {
        let startDay = calendar.startOfDay(for: interval.start)
        let endDay = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        let days = calendar.dateComponents([.day], from: startDay, to: max(startDay, endDay)).day ?? 0
        return max(1, days + 1)
    }

    private static func bucketedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return 0 }
        return (width / widthStep).rounded(.up) * widthStep
    }
}
