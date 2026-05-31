import SwiftUI

enum LeaderboardLayout {
    static let workspaceMaxWidth: CGFloat = 980
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 52
    static let bottomPadding: CGFloat = 22
    static let columnSpacing: CGFloat = 14
    static let headerContentSpacing: CGFloat = 20
    static let overviewControlSummarySpacing: CGFloat = 12
    static let leftColumnWidth: CGFloat = 390
    static let detailMinWidth: CGFloat = 500
    static let wideMinimumWidth: CGFloat = leftColumnWidth + columnSpacing + detailMinWidth

    static func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        min(workspaceMaxWidth, max(0, availableWidth - horizontalPadding * 2))
    }
}

struct LeaderboardWideWorkspaceLayout: Layout {
    let leftWidth: CGFloat
    let detailMinWidth: CGFloat
    let columnSpacing: CGFloat
    let headerSpacing: CGFloat
    let controlSummarySpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 4 else { return .zero }
        let availableWidth = proposal.width ?? leftWidth + columnSpacing + detailMinWidth
        let detailWidth = max(detailMinWidth, availableWidth - leftWidth - columnSpacing)
        let sizes = measuredSizes(subviews: subviews, availableWidth: availableWidth, detailWidth: detailWidth)
        return CGSize(
            width: leftWidth + columnSpacing + detailWidth,
            height: sizes.headerHeight
                + headerSpacing
                + sizes.controlsHeight
                + sizes.controlSummaryGap
                + sizes.lowerHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 4 else { return }
        let detailWidth = max(detailMinWidth, bounds.width - leftWidth - columnSpacing)
        let sizes = measuredSizes(subviews: subviews, availableWidth: bounds.width, detailWidth: detailWidth)
        let controlsX = bounds.minX + leftWidth + columnSpacing
        let controlsY = bounds.minY + sizes.headerHeight + headerSpacing
        let lowerY = controlsY + sizes.controlsHeight + sizes.controlSummaryGap

        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: sizes.headerHeight)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: controlsY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: sizes.controlsHeight)
        )
        subviews[2].place(
            at: CGPoint(x: bounds.minX, y: lowerY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: leftWidth, height: sizes.lowerHeight)
        )
        subviews[3].place(
            at: CGPoint(x: controlsX, y: lowerY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: detailWidth, height: sizes.lowerHeight)
        )
    }

    private func measuredSizes(
        subviews: Subviews,
        availableWidth: CGFloat,
        detailWidth: CGFloat
    ) -> (headerHeight: CGFloat, controlsHeight: CGFloat, controlSummaryGap: CGFloat, lowerHeight: CGFloat) {
        let headerHeight = subviews[0].sizeThatFits(ProposedViewSize(width: availableWidth, height: nil)).height
        let controlsHeight = subviews[1].sizeThatFits(ProposedViewSize(width: availableWidth, height: nil)).height
        let controlSummaryGap = controlsHeight > 0 ? controlSummarySpacing : 0
        let rightHeight = subviews[3].sizeThatFits(ProposedViewSize(width: detailWidth, height: nil)).height
        return (headerHeight, controlsHeight, controlSummaryGap, rightHeight)
    }
}

enum LeaderboardFormat {
    static func score(_ score: Int64, metric: LeaderboardMetric) -> String {
        switch metric {
        case .tokensWithCache, .tokensWithoutCacheRead:
            return Format.tokens(Int(clamping: score))
        case .activityMinutes:
            return Format.duration(TimeInterval(score) * 60)
        }
    }

    static func delta(_ score: Int64, metric: LeaderboardMetric) -> String {
        score == 0 ? "0" : Self.score(score, metric: metric)
    }

    static func avatarSeed(for score: LeaderboardScore) -> String {
        score.avatarSeed ?? score.userHash ?? score.nickname
    }
}

enum LeaderboardDailyDateNavigator {
    static func todayStartUTC(now: Date = .now) -> Date {
        LeaderboardPeriodCalculator.window(for: .day, now: now).startUTC
    }

    static func normalized(_ date: Date, now: Date = .now) -> Date {
        let day = LeaderboardPeriodCalculator.window(for: .day, now: date).startUTC
        let today = todayStartUTC(now: now)
        return min(day, today)
    }

    static func stepped(from date: Date, by offset: Int, now: Date = .now) -> Date {
        normalized(
            date.addingTimeInterval(TimeInterval(offset * 86_400)),
            now: now
        )
    }

    static func canStepForward(from date: Date, now: Date = .now) -> Bool {
        normalized(date, now: now) < todayStartUTC(now: now)
    }

    static func periodKey(for date: Date) -> String {
        LeaderboardPeriodCalculator.window(for: .day, now: date).periodKey
    }

    static func date(fromPeriodKey periodKey: String) -> Date? {
        guard let window = LeaderboardPeriodCalculator.window(for: .day, periodKey: periodKey) else {
            return nil
        }
        return normalized(window.startUTC)
    }

    static func label(for date: Date, now: Date = .now) -> String {
        let day = normalized(date, now: now)
        let today = todayStartUTC(now: now)
        if day == today { return "Today" }

        let yesterday = stepped(from: today, by: -1, now: now)
        if day == yesterday { return "Yesterday" }

        return Format.day(day)
    }
}

extension LeaderboardMetric {
    var symbolName: String {
        switch self {
        case .tokensWithCache: AppIcon.Leaderboard.tokensWithCache
        case .tokensWithoutCacheRead: AppIcon.Leaderboard.tokensWithoutCacheRead
        case .activityMinutes: AppIcon.Leaderboard.activityMinutes
        }
    }
}

extension LeaderboardPeriod {
    var chipLabel: String {
        switch self {
        case .day: "Daily"
        case .week: "Weekly"
        case .month: "Monthly"
        case .allTime: "All"
        }
    }

    var symbolName: String {
        switch self {
        case .day: AppIcon.Leaderboard.day
        case .week: AppIcon.Leaderboard.week
        case .month: AppIcon.Leaderboard.month
        case .allTime: AppIcon.Leaderboard.allTime
        }
    }
}
