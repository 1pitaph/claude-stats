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
            remoteUpdatedAt: updatedAt
        )

        #expect(merged.score == 150)
        #expect(merged.updatedAt == updatedAt)
        #expect(merged.nickname == "Ada")
    }

    @Test("Local higher live score is uploaded")
    func localHigherLiveScoreWins() {
        let local = liveSubmission(score: 200)
        let merged = LeaderboardSubmissionMergePolicy.merge(
            local: local,
            remoteScore: 150,
            remoteUpdatedAt: Date(timeIntervalSince1970: 50)
        )

        #expect(merged == local)
    }

    @Test("Remote higher history score is preserved")
    func remoteHigherHistoryScoreWins() {
        let updatedAt = Date(timeIntervalSince1970: 60)
        let merged = LeaderboardSubmissionMergePolicy.merge(
            local: historySubmission(score: 100),
            remoteScore: 175,
            remoteUpdatedAt: updatedAt
        )

        #expect(merged.score == 175)
        #expect(merged.updatedAt == updatedAt)
    }

    private func liveSubmission(score: Int64) -> LeaderboardSubmission {
        LeaderboardSubmission(
            metric: .tokensWithCache,
            period: .day,
            periodKey: "2026-06-03",
            score: score,
            nickname: "Ada",
            periodStartUTC: Date(timeIntervalSince1970: 0),
            periodEndUTC: Date(timeIntervalSince1970: 86_400),
            appVersion: "test",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
    }

    private func historySubmission(score: Int64) -> LeaderboardHistorySubmission {
        LeaderboardHistorySubmission(
            metric: .tokensWithCache,
            bucketPeriod: .day,
            periodKey: "2026-06-03",
            score: score,
            periodStartUTC: Date(timeIntervalSince1970: 0),
            periodEndUTC: Date(timeIntervalSince1970: 86_400),
            appVersion: "test",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
    }
}
