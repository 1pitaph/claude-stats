import Foundation

enum LeaderboardMetric: String, CaseIterable, Sendable, Identifiable, Codable {
    case tokensWithCache
    case tokensWithoutCacheRead
    case activityMinutes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tokensWithCache: "Tokens incl. cache"
        case .tokensWithoutCacheRead: "Tokens excl. cache"
        case .activityMinutes: "Activity minutes"
        }
    }

    var shortLabel: String {
        switch self {
        case .tokensWithCache: "With cache"
        case .tokensWithoutCacheRead: "No cache"
        case .activityMinutes: "Activity"
        }
    }
}

enum LeaderboardPeriod: String, CaseIterable, Sendable, Identifiable, Codable {
    case day
    case week
    case month
    case allTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: "Daily"
        case .week: "Weekly"
        case .month: "Monthly"
        case .allTime: "All-time"
        }
    }
}

enum LeaderboardRecentStatus: String, CaseIterable, Sendable, Identifiable, Codable {
    case focused
    case shipping
    case debugging
    case reviewing
    case away
    case celebrating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .focused: "Focused"
        case .shipping: "Shipping"
        case .debugging: "Debugging"
        case .reviewing: "Reviewing"
        case .away: "Away"
        case .celebrating: "Celebrating"
        }
    }

    var shortLabel: String {
        switch self {
        case .focused: "Focus"
        case .shipping: "Ship"
        case .debugging: "Debug"
        case .reviewing: "Review"
        case .away: "Away"
        case .celebrating: "Win"
        }
    }

    var symbolName: String {
        switch self {
        case .focused: "target"
        case .shipping: "paperplane.fill"
        case .debugging: "ladybug.fill"
        case .reviewing: "checkmark.seal.fill"
        case .away: "moon.fill"
        case .celebrating: "party.popper.fill"
        }
    }

    static func normalizedID(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty,
              Self(rawValue: rawValue) != nil else {
            return nil
        }
        return rawValue
    }
}

struct LeaderboardScore: Sendable, Hashable, Identifiable, Codable {
    let id: String
    let userHash: String?
    let metric: LeaderboardMetric
    let period: LeaderboardPeriod
    let periodKey: String
    let score: Int64
    let rank: Int?
    let nickname: String
    let avatarSeed: String?
    let historyStartMonthKey: String?
    let favoriteModels: [LeaderboardFavoriteModel]?
    let recentStatusID: String?
    let recentStatusUpdatedAt: Date?
    let updatedAt: Date

    init(id: String,
         userHash: String?,
         metric: LeaderboardMetric,
         period: LeaderboardPeriod,
         periodKey: String,
         score: Int64,
         rank: Int?,
         nickname: String,
         avatarSeed: String?,
         historyStartMonthKey: String? = nil,
         favoriteModels: [LeaderboardFavoriteModel]? = nil,
         recentStatusID: String? = nil,
         recentStatusUpdatedAt: Date? = nil,
         updatedAt: Date) {
        self.id = id
        self.userHash = userHash
        self.metric = metric
        self.period = period
        self.periodKey = periodKey
        self.score = score
        self.rank = rank
        self.nickname = nickname
        self.avatarSeed = avatarSeed
        self.historyStartMonthKey = historyStartMonthKey
        self.favoriteModels = favoriteModels
        self.recentStatusID = LeaderboardRecentStatus.normalizedID(recentStatusID)
        self.recentStatusUpdatedAt = recentStatusUpdatedAt
        self.updatedAt = updatedAt
    }

    func withRank(_ rank: Int?) -> LeaderboardScore {
        LeaderboardScore(
            id: id,
            userHash: userHash,
            metric: metric,
            period: period,
            periodKey: periodKey,
            score: score,
            rank: rank,
            nickname: nickname,
            avatarSeed: avatarSeed,
            historyStartMonthKey: historyStartMonthKey,
            favoriteModels: favoriteModels,
            recentStatusID: recentStatusID,
            recentStatusUpdatedAt: recentStatusUpdatedAt,
            updatedAt: updatedAt
        )
    }
}

struct LeaderboardFavoriteModel: Sendable, Hashable, Identifiable, Codable {
    let rank: Int
    let model: String
    let tokens: Int64

    var id: String { model }
}

struct LeaderboardScoreHistoryPoint: Sendable, Hashable, Identifiable, Codable {
    let metric: LeaderboardMetric
    let period: LeaderboardPeriod
    let periodKey: String
    let startUTC: Date
    let endUTC: Date?
    let score: Int64
    let updatedAt: Date?

    var id: String { "\(metric.rawValue)-\(period.rawValue)-\(periodKey)" }

    init(metric: LeaderboardMetric,
         period: LeaderboardPeriod,
         window: LeaderboardPeriodWindow,
         score: Int64,
         updatedAt: Date?) {
        self.metric = metric
        self.period = period
        self.periodKey = window.periodKey
        self.startUTC = window.startUTC
        self.endUTC = window.endUTC
        self.score = score
        self.updatedAt = updatedAt
    }
}

enum LeaderboardScoreCalculation {
    static let legacyVersion = 1
    static let currentVersion = 2
}

enum LeaderboardSelectionResolver {
    static func selectedScore(preferredUserHash: String?,
                              currentUserHash: String?,
                              scores: [LeaderboardScore]) -> LeaderboardScore? {
        if let preferredUserHash,
           let score = scores.first(where: { $0.userHash == preferredUserHash }) {
            return score
        }
        if let currentUserHash,
           let score = scores.first(where: { $0.userHash == currentUserHash }) {
            return score
        }
        return scores.first
    }
}

struct LeaderboardSubmission: Sendable, Hashable, Codable {
    let metric: LeaderboardMetric
    let period: LeaderboardPeriod
    let periodKey: String
    let score: Int64
    let nickname: String
    let periodStartUTC: Date
    let periodEndUTC: Date?
    let appVersion: String
    let calculationVersion: Int
    let updatedAt: Date

    var id: String { "\(metric.rawValue)-\(period.rawValue)-\(periodKey)" }

    init(metric: LeaderboardMetric,
         period: LeaderboardPeriod,
         periodKey: String,
         score: Int64,
         nickname: String,
         periodStartUTC: Date,
         periodEndUTC: Date?,
         appVersion: String,
         calculationVersion: Int = LeaderboardScoreCalculation.currentVersion,
         updatedAt: Date) {
        self.metric = metric
        self.period = period
        self.periodKey = periodKey
        self.score = score
        self.nickname = nickname
        self.periodStartUTC = periodStartUTC
        self.periodEndUTC = periodEndUTC
        self.appVersion = appVersion
        self.calculationVersion = calculationVersion
        self.updatedAt = updatedAt
    }
}

struct LeaderboardHistorySubmission: Sendable, Hashable, Codable {
    let metric: LeaderboardMetric
    let bucketPeriod: LeaderboardPeriod
    let periodKey: String
    let score: Int64
    let periodStartUTC: Date
    let periodEndUTC: Date?
    let appVersion: String
    let calculationVersion: Int
    let updatedAt: Date

    var id: String { "\(metric.rawValue)-\(bucketPeriod.rawValue)-\(periodKey)" }

    init(metric: LeaderboardMetric,
         bucketPeriod: LeaderboardPeriod,
         periodKey: String,
         score: Int64,
         periodStartUTC: Date,
         periodEndUTC: Date?,
         appVersion: String,
         calculationVersion: Int = LeaderboardScoreCalculation.currentVersion,
         updatedAt: Date) {
        self.metric = metric
        self.bucketPeriod = bucketPeriod
        self.periodKey = periodKey
        self.score = score
        self.periodStartUTC = periodStartUTC
        self.periodEndUTC = periodEndUTC
        self.appVersion = appVersion
        self.calculationVersion = calculationVersion
        self.updatedAt = updatedAt
    }
}

struct LeaderboardProfile: Sendable, Hashable, Identifiable, Codable {
    let userHash: String
    let nickname: String
    let avatarSeed: String?
    let historyStartMonthKey: String?
    let favoriteModels: [LeaderboardFavoriteModel]?
    let recentStatusID: String?
    let recentStatusUpdatedAt: Date?
    let updatedAt: Date

    var id: String { userHash }

    init(userHash: String,
         nickname: String,
         avatarSeed: String?,
         historyStartMonthKey: String?,
         favoriteModels: [LeaderboardFavoriteModel]? = nil,
         recentStatusID: String? = nil,
         recentStatusUpdatedAt: Date? = nil,
         updatedAt: Date) {
        self.userHash = userHash
        self.nickname = nickname
        self.avatarSeed = avatarSeed
        self.historyStartMonthKey = historyStartMonthKey
        self.favoriteModels = favoriteModels
        self.recentStatusID = LeaderboardRecentStatus.normalizedID(recentStatusID)
        self.recentStatusUpdatedAt = recentStatusUpdatedAt
        self.updatedAt = updatedAt
    }
}

struct LeaderboardProfileDraft: Sendable, Hashable, Codable {
    let nickname: String
    let avatarSeed: String
    let historyStartMonthKey: String?
    let favoriteModels: [LeaderboardFavoriteModel]?
    let recentStatusID: String?
    let recentStatusUpdatedAt: Date?
    let appVersion: String
    let updatedAt: Date

    init(nickname: String,
         avatarSeed: String,
         historyStartMonthKey: String? = nil,
         favoriteModels: [LeaderboardFavoriteModel]? = nil,
         recentStatusID: String? = nil,
         recentStatusUpdatedAt: Date? = nil,
         appVersion: String = Self.appVersion,
         updatedAt: Date = .now) {
        self.nickname = nickname
        self.avatarSeed = avatarSeed
        self.historyStartMonthKey = historyStartMonthKey
        self.favoriteModels = favoriteModels
        self.recentStatusID = LeaderboardRecentStatus.normalizedID(recentStatusID)
        self.recentStatusUpdatedAt = recentStatusUpdatedAt
        self.appVersion = appVersion
        self.updatedAt = updatedAt
    }

    private static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
}

enum LeaderboardAvatarSeed {
    static let fallback = "leaderboard-avatar-preview"

    static func random() -> String {
        "avatar-\(UUID().uuidString.lowercased())"
    }
}

struct LeaderboardPeriodWindow: Sendable, Hashable, Codable {
    let period: LeaderboardPeriod
    let periodKey: String
    let startUTC: Date
    let endUTC: Date?

    func contains(_ date: Date) -> Bool {
        date >= startUTC && endUTC.map { date < $0 } ?? true
    }
}

enum LeaderboardPeriodCalculator {
    static func window(for period: LeaderboardPeriod, now: Date = .now) -> LeaderboardPeriodWindow {
        switch period {
        case .day:
            let calendar = utcGregorianCalendar
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            let comps = calendar.dateComponents([.year, .month, .day], from: start)
            return LeaderboardPeriodWindow(
                period: period,
                periodKey: String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0),
                startUTC: start,
                endUTC: end
            )
        case .week:
            let calendar = utcISOCalendar
            let interval = calendar.dateInterval(of: .weekOfYear, for: now)
                ?? DateInterval(start: now, duration: 7 * 86_400)
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: interval.start)
            return LeaderboardPeriodWindow(
                period: period,
                periodKey: String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0),
                startUTC: interval.start,
                endUTC: interval.end
            )
        case .month:
            let calendar = utcGregorianCalendar
            let interval = calendar.dateInterval(of: .month, for: now)
                ?? DateInterval(start: now, duration: 30 * 86_400)
            let comps = calendar.dateComponents([.year, .month], from: interval.start)
            return LeaderboardPeriodWindow(
                period: period,
                periodKey: String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0),
                startUTC: interval.start,
                endUTC: interval.end
            )
        case .allTime:
            return LeaderboardPeriodWindow(
                period: period,
                periodKey: "all",
                startUTC: Date(timeIntervalSince1970: 0),
                endUTC: nil
            )
        }
    }

    static func window(for period: LeaderboardPeriod, periodKey: String) -> LeaderboardPeriodWindow? {
        switch period {
        case .day:
            let parts = periodKey.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let start = utcGregorianCalendar.date(from: DateComponents(
                    timeZone: utcGregorianCalendar.timeZone,
                    year: parts[0],
                    month: parts[1],
                    day: parts[2]
                  )) else {
                return nil
            }
            let end = utcGregorianCalendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            return LeaderboardPeriodWindow(period: period, periodKey: periodKey, startUTC: start, endUTC: end)
        case .week:
            let pieces = periodKey.components(separatedBy: "-W").compactMap { Int($0) }
            guard pieces.count == 2,
                  let start = utcISOCalendar.date(from: DateComponents(
                    calendar: utcISOCalendar,
                    timeZone: utcISOCalendar.timeZone,
                    weekday: 2,
                    weekOfYear: pieces[1],
                    yearForWeekOfYear: pieces[0]
                  )) else {
                return nil
            }
            let end = utcISOCalendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start.addingTimeInterval(7 * 86_400)
            return LeaderboardPeriodWindow(period: period, periodKey: periodKey, startUTC: start, endUTC: end)
        case .month:
            let parts = periodKey.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2,
                  let start = utcGregorianCalendar.date(from: DateComponents(
                    timeZone: utcGregorianCalendar.timeZone,
                    year: parts[0],
                    month: parts[1],
                    day: 1
                  )) else {
                return nil
            }
            let end = utcGregorianCalendar.date(byAdding: .month, value: 1, to: start)
                ?? start.addingTimeInterval(31 * 86_400)
            return LeaderboardPeriodWindow(period: period, periodKey: periodKey, startUTC: start, endUTC: end)
        case .allTime:
            return periodKey == "all" ? window(for: .allTime) : nil
        }
    }

    static func historyWindows(for period: LeaderboardPeriod, anchorWindow: LeaderboardPeriodWindow) -> [LeaderboardPeriodWindow] {
        historyScope(for: period, now: anchorWindow.startUTC, historyStart: nil)
    }

    static func historyScope(for period: LeaderboardPeriod,
                             now: Date = .now,
                             historyStart: Date? = nil) -> [LeaderboardPeriodWindow] {
        switch period {
        case .day:
            return historyWindows(period: period, anchorDate: window(for: .day, now: now).startUTC, count: 7) { date, offset in
                date.addingTimeInterval(TimeInterval(-offset * 86_400))
            }
        case .week:
            return historyWindows(period: period, anchorDate: window(for: .week, now: now).startUTC, count: 4) { date, offset in
                utcISOCalendar.date(byAdding: .weekOfYear, value: -offset, to: date) ?? date
            }
        case .month:
            return historyWindows(period: period, anchorDate: window(for: .month, now: now).startUTC, count: 3) { date, offset in
                utcGregorianCalendar.date(byAdding: .month, value: -offset, to: date) ?? date
            }
        case .allTime:
            guard let historyStart else { return [] }
            let firstMonth = window(for: .month, now: historyStart).startUTC
            let currentMonth = window(for: .month, now: now).startUTC
            guard firstMonth <= currentMonth else { return [window(for: .month, now: currentMonth)] }

            var windows: [LeaderboardPeriodWindow] = []
            var cursor = firstMonth
            while cursor <= currentMonth {
                windows.append(window(for: .month, now: cursor))
                guard let next = utcGregorianCalendar.date(byAdding: .month, value: 1, to: cursor) else {
                    break
                }
                cursor = next
            }
            return windows
        }
    }

    static func windows(now: Date = .now) -> [LeaderboardPeriodWindow] {
        LeaderboardPeriod.allCases.map { window(for: $0, now: now) }
    }

    private static func historyWindows(period: LeaderboardPeriod,
                                       anchorDate: Date,
                                       count: Int,
                                       dateForOffset: (Date, Int) -> Date) -> [LeaderboardPeriodWindow] {
        stride(from: count - 1, through: 0, by: -1).map { offset in
            window(for: period, now: dateForOffset(anchorDate, offset))
        }
    }

    private static var utcGregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static var utcISOCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
