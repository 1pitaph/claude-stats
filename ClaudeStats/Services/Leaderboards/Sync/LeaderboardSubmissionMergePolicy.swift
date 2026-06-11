import Foundation

enum LeaderboardSubmissionMergePolicy {
    static func merge(local: LeaderboardSubmission,
                      remoteScore: Int64?,
                      remoteCalculationVersion: Int?,
                      remoteUpdatedAt: Date?) -> LeaderboardSubmission {
        guard shouldPreserveRemote(
            localScore: local.score,
            localCalculationVersion: local.calculationVersion,
            remoteScore: remoteScore,
            remoteCalculationVersion: remoteCalculationVersion
        ), let remoteScore else {
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
            calculationVersion: remoteCalculationVersion ?? LeaderboardScoreCalculation.legacyVersion,
            updatedAt: remoteUpdatedAt ?? local.updatedAt
        )
    }

    static func merge(local: LeaderboardHistorySubmission,
                      remoteScore: Int64?,
                      remoteCalculationVersion: Int?,
                      remoteUpdatedAt: Date?) -> LeaderboardHistorySubmission {
        guard shouldPreserveRemote(
            localScore: local.score,
            localCalculationVersion: local.calculationVersion,
            remoteScore: remoteScore,
            remoteCalculationVersion: remoteCalculationVersion
        ), let remoteScore else {
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
            calculationVersion: remoteCalculationVersion ?? LeaderboardScoreCalculation.legacyVersion,
            updatedAt: remoteUpdatedAt ?? local.updatedAt
        )
    }

    private static func shouldPreserveRemote(localScore: Int64,
                                             localCalculationVersion: Int,
                                             remoteScore: Int64?,
                                             remoteCalculationVersion: Int?) -> Bool {
        guard let remoteScore else { return false }
        let remoteVersion = remoteCalculationVersion ?? LeaderboardScoreCalculation.legacyVersion
        if remoteVersion > localCalculationVersion {
            return true
        }
        if remoteVersion < localCalculationVersion {
            return false
        }
        return remoteScore > localScore
    }
}
