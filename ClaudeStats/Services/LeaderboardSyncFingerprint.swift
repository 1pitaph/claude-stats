import CryptoKit
import Foundation

enum LeaderboardSyncFingerprint {
    private struct Payload: Codable {
        let profile: Profile
        let scores: [Score]
        let history: [History]
    }

    private struct Profile: Codable {
        let nickname: String
        let avatarSeed: String
        let historyStartMonthKey: String?
        let favoriteModels: [LeaderboardFavoriteModel]?
        let recentStatusID: String?
        let recentStatusUpdatedAt: Date?
    }

    private struct Score: Codable, Comparable {
        let metric: LeaderboardMetric
        let period: LeaderboardPeriod
        let periodKey: String
        let score: Int64

        static func < (lhs: Score, rhs: Score) -> Bool {
            [
                lhs.metric.rawValue,
                lhs.period.rawValue,
                lhs.periodKey,
                "\(lhs.score)",
            ].lexicographicallyPrecedes([
                rhs.metric.rawValue,
                rhs.period.rawValue,
                rhs.periodKey,
                "\(rhs.score)",
            ])
        }
    }

    private struct History: Codable, Comparable {
        let metric: LeaderboardMetric
        let bucketPeriod: LeaderboardPeriod
        let periodKey: String
        let score: Int64

        static func < (lhs: History, rhs: History) -> Bool {
            [
                lhs.metric.rawValue,
                lhs.bucketPeriod.rawValue,
                lhs.periodKey,
                "\(lhs.score)",
            ].lexicographicallyPrecedes([
                rhs.metric.rawValue,
                rhs.bucketPeriod.rawValue,
                rhs.periodKey,
                "\(rhs.score)",
            ])
        }
    }

    static func make(profile: LeaderboardProfileDraft,
                     submissions: [LeaderboardSubmission],
                     historySubmissions: [LeaderboardHistorySubmission]) -> String {
        let payload = Payload(
            profile: Profile(
                nickname: profile.nickname,
                avatarSeed: profile.avatarSeed,
                historyStartMonthKey: profile.historyStartMonthKey,
                favoriteModels: profile.favoriteModels,
                recentStatusID: profile.recentStatusID,
                recentStatusUpdatedAt: profile.recentStatusUpdatedAt
            ),
            scores: submissions
                .map { Score(metric: $0.metric, period: $0.period, periodKey: $0.periodKey, score: $0.score) }
                .sorted(),
            history: historySubmissions
                .map { History(metric: $0.metric, bucketPeriod: $0.bucketPeriod, periodKey: $0.periodKey, score: $0.score) }
                .sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(payload)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
