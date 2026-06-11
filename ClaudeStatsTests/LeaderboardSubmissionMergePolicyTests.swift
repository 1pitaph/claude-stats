import Foundation
import Testing
@testable import ClaudeStats

@Suite("LeaderboardSubmissionMergePolicy")
struct LeaderboardSubmissionMergePolicyTests {
    @Test("Remote higher live score is preserved")
    func remoteHigherLiveScoreWins() {
        let updatedAt = Date(timeIntervalSince1970: 50)
        let merged = LeaderboardSubmissionMergePolicy.merge(
            local: liveSubmission(score: 100),
            remoteScore: 150,
            remoteCalculationVersion: LeaderboardScoreCalculation.currentVersion,
            remoteUpdatedAt: updatedAt
        )

        #expect(merged.score == 150)
        #expect(merged.calculationVersion == LeaderboardScoreCalculation.currentVersion)
        #expect(merged.updatedAt == updatedAt)
        #expect(merged.nickname == "Ada")
    }

    @Test("Local higher live score is uploaded")
    func localHigherLiveScoreWins() {
        let local = liveSubmission(score: 200)
        let merged = LeaderboardSubmissionMergePolicy.merge(
            local: local,
            remoteScore: 150,
            remoteCalculationVersion: LeaderboardScoreCalculation.currentVersion,
            remoteUpdatedAt: Date(timeIntervalSince1970: 50)
        )

        #expect(merged == local)
    }

    @Test("Newer local calculation overwrites legacy higher live score")
    func newerLocalCalculationOverwritesLegacyHigherLiveScore() {
        let local = liveSubmission(score: 100, calculationVersion: LeaderboardScoreCalculation.currentVersion)
        let merged = LeaderboardSubmissionMergePolicy.merge(
            local: local,
            remoteScore: 1_000,
            remoteCalculationVersion: nil,
            remoteUpdatedAt: Date(timeIntervalSince1970: 50)
        )

        #expect(merged == local)
    }

    @Test("Future remote calculation is preserved")
    func futureRemoteCalculationWins() {
        let updatedAt = Date(timeIntervalSince1970: 80)
        let merged = LeaderboardSubmissionMergePolicy.merge(
            local: liveSubmission(score: 1_000, calculationVersion: LeaderboardScoreCalculation.currentVersion),
            remoteScore: 100,
            remoteCalculationVersion: LeaderboardScoreCalculation.currentVersion + 1,
            remoteUpdatedAt: updatedAt
        )

        #expect(merged.score == 100)
        #expect(merged.calculationVersion == LeaderboardScoreCalculation.currentVersion + 1)
        #expect(merged.updatedAt == updatedAt)
    }

    @Test("Remote higher history score is preserved")
    func remoteHigherHistoryScoreWins() {
        let updatedAt = Date(timeIntervalSince1970: 60)
        let merged = LeaderboardSubmissionMergePolicy.merge(
            local: historySubmission(score: 100),
            remoteScore: 175,
            remoteCalculationVersion: LeaderboardScoreCalculation.currentVersion,
            remoteUpdatedAt: updatedAt
        )

        #expect(merged.score == 175)
        #expect(merged.calculationVersion == LeaderboardScoreCalculation.currentVersion)
        #expect(merged.updatedAt == updatedAt)
    }

    @Test("Newer local calculation overwrites legacy higher history score")
    func newerLocalCalculationOverwritesLegacyHigherHistoryScore() {
        let local = historySubmission(score: 100, calculationVersion: LeaderboardScoreCalculation.currentVersion)
        let merged = LeaderboardSubmissionMergePolicy.merge(
            local: local,
            remoteScore: 1_000,
            remoteCalculationVersion: LeaderboardScoreCalculation.legacyVersion,
            remoteUpdatedAt: Date(timeIntervalSince1970: 60)
        )

        #expect(merged == local)
    }

    private func liveSubmission(score: Int64, calculationVersion: Int = LeaderboardScoreCalculation.currentVersion) -> LeaderboardSubmission {
        LeaderboardSubmission(
            metric: .tokensWithCache,
            period: .day,
            periodKey: "2026-06-03",
            score: score,
            nickname: "Ada",
            periodStartUTC: Date(timeIntervalSince1970: 0),
            periodEndUTC: Date(timeIntervalSince1970: 86_400),
            appVersion: "test",
            calculationVersion: calculationVersion,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
    }

    private func historySubmission(score: Int64, calculationVersion: Int = LeaderboardScoreCalculation.currentVersion) -> LeaderboardHistorySubmission {
        LeaderboardHistorySubmission(
            metric: .tokensWithCache,
            bucketPeriod: .day,
            periodKey: "2026-06-03",
            score: score,
            periodStartUTC: Date(timeIntervalSince1970: 0),
            periodEndUTC: Date(timeIntervalSince1970: 86_400),
            appVersion: "test",
            calculationVersion: calculationVersion,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
    }
}
