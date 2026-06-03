import Foundation

enum LeaderboardSubmissionMergePolicy {
    static func merge(local: LeaderboardSubmission,
                      remoteScore: Int64?,
                      remoteUpdatedAt: Date?) -> LeaderboardSubmission {
        guard let remoteScore, remoteScore > local.score else {
            return local
        }
        return LeaderboardSubmission(
            metric: local.metric,
            period: local.period,
            periodKey: local.periodKey,
            score: remoteScore,
            nickname: local.nickname,
            periodStartUTC: local.periodStartUTC,
            periodEndUTC: local.periodEndUTC,
            appVersion: local.appVersion,
            updatedAt: remoteUpdatedAt ?? local.updatedAt
        )
    }

    static func merge(local: LeaderboardHistorySubmission,
                      remoteScore: Int64?,
                      remoteUpdatedAt: Date?) -> LeaderboardHistorySubmission {
        guard let remoteScore, remoteScore > local.score else {
            return local
        }
        return LeaderboardHistorySubmission(
            metric: local.metric,
            bucketPeriod: local.bucketPeriod,
            periodKey: local.periodKey,
            score: remoteScore,
            periodStartUTC: local.periodStartUTC,
            periodEndUTC: local.periodEndUTC,
            appVersion: local.appVersion,
            updatedAt: remoteUpdatedAt ?? local.updatedAt
        )
    }
}
