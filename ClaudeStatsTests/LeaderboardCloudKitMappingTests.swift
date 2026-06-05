import CloudKit
import Foundation
import Testing
@testable import ClaudeStats

@Suite("CloudKit leaderboard record mapping")
struct LeaderboardCloudKitMappingTests {
    @Test("User hash is deterministic and hides the raw CloudKit record name")
    func userHash() {
        let hash = CloudKitLeaderboardRecordMapper.userHash(forUserRecordName: "_abc123")

        #expect(hash == CloudKitLeaderboardRecordMapper.userHash(forUserRecordName: "_abc123"))
        #expect(hash.count == 64)
        #expect(hash.contains("_abc123") == false)
    }

    @Test("Record name and fields are stable")
    func recordMapping() {
        let submission = LeaderboardSubmission(
            metric: .tokensWithoutCacheRead,
            period: .week,
            periodKey: "2026-W20",
            score: 42_000,
            nickname: "Ada",
            periodStartUTC: Date(timeIntervalSince1970: 1_768_176_000),
            periodEndUTC: Date(timeIntervalSince1970: 1_768_780_800),
            appVersion: "1.2.3",
            updatedAt: Date(timeIntervalSince1970: 1_768_200_000)
        )
        let record = CloudKitLeaderboardRecordMapper.record(from: submission, userHash: "userhash")

        #expect(record.recordID.recordName == "score_v1_userhash_tokensWithoutCacheRead_week_2026-W20")
        #expect(record.recordType == CloudKitLeaderboardConfig.recordType)
        #expect(record[CloudKitLeaderboardRecordMapper.Field.nickname] as? String == "Ada")
        #expect(record[CloudKitLeaderboardRecordMapper.Field.metric] as? String == "tokensWithoutCacheRead")
        #expect(record[CloudKitLeaderboardRecordMapper.Field.period] as? String == "week")
        #expect(record[CloudKitLeaderboardRecordMapper.Field.periodKey] as? String == "2026-W20")
        #expect((record[CloudKitLeaderboardRecordMapper.Field.score] as? NSNumber)?.int64Value == 42_000)
        #expect(record[CloudKitLeaderboardRecordMapper.Field.providerScope] as? String == "all")
    }

    @Test("History record name is separated from score records")
    func historyRecordMapping() {
        let submission = LeaderboardHistorySubmission(
            metric: .tokensWithCache,
            bucketPeriod: .month,
            periodKey: "2026-05",
            score: 123_000,
            periodStartUTC: Date(timeIntervalSince1970: 1_767_916_800),
            periodEndUTC: Date(timeIntervalSince1970: 1_770_595_200),
            appVersion: "1.2.3",
            updatedAt: Date(timeIntervalSince1970: 1_768_200_000)
        )
        let record = CloudKitLeaderboardRecordMapper.historyRecord(from: submission, userHash: "userhash")

        #expect(record.recordID.recordName == "history_v1_userhash_tokensWithCache_month_2026-05")
        #expect(record.recordID.recordName != "score_v1_userhash_tokensWithCache_month_2026-05")
        #expect(record[CloudKitLeaderboardRecordMapper.Field.metric] as? String == "tokensWithCache")
        #expect(record[CloudKitLeaderboardRecordMapper.Field.period] as? String == "month")
        #expect(record[CloudKitLeaderboardRecordMapper.Field.periodKey] as? String == "2026-05")
        #expect((record[CloudKitLeaderboardRecordMapper.Field.score] as? NSNumber)?.int64Value == 123_000)
        #expect(record[CloudKitLeaderboardRecordMapper.Field.providerScope] as? String == "history")
    }

    @Test("History records are excluded before assigning leaderboard ranks")
    func rankedScoresExcludeHistoryRecordsBeforeRankAssignment() {
        let highScore = CloudKitLeaderboardRecordMapper.record(
            from: LeaderboardSubmission(
                metric: .tokensWithCache,
                period: .day,
                periodKey: "2026-05-19",
                score: 300,
                nickname: "Ada",
                periodStartUTC: Date(timeIntervalSince1970: 1_768_521_600),
                periodEndUTC: Date(timeIntervalSince1970: 1_768_608_000),
                appVersion: "1.2.3",
                updatedAt: Date(timeIntervalSince1970: 1_768_530_000)
            ),
            userHash: "ada"
        )
        let lowerScore = CloudKitLeaderboardRecordMapper.record(
            from: LeaderboardSubmission(
                metric: .tokensWithCache,
                period: .day,
                periodKey: "2026-05-19",
                score: 200,
                nickname: "Grace",
                periodStartUTC: Date(timeIntervalSince1970: 1_768_521_600),
                periodEndUTC: Date(timeIntervalSince1970: 1_768_608_000),
                appVersion: "1.2.3",
                updatedAt: Date(timeIntervalSince1970: 1_768_540_000)
            ),
            userHash: "grace"
        )
        let history = CloudKitLeaderboardRecordMapper.historyRecord(
            from: LeaderboardHistorySubmission(
                metric: .tokensWithCache,
                bucketPeriod: .day,
                periodKey: "2026-05-19",
                score: 500,
                periodStartUTC: Date(timeIntervalSince1970: 1_768_521_600),
                periodEndUTC: Date(timeIntervalSince1970: 1_768_608_000),
                appVersion: "1.2.3",
                updatedAt: Date(timeIntervalSince1970: 1_768_520_000)
            ),
            userHash: "history"
        )

        let scores = CloudKitLeaderboardRecordMapper.rankedScores(from: [history, highScore, history, lowerScore])

        #expect(scores.map(\.id) == [
            "score_v1_ada_tokensWithCache_day_2026-05-19",
            "score_v1_grace_tokensWithCache_day_2026-05-19",
        ])
        #expect(scores.compactMap(\.rank) == [1, 2])
    }

    @Test("CKRecord maps back to a Sendable score value")
    func scoreMapping() {
        let submission = LeaderboardSubmission(
            metric: .activityMinutes,
            period: .month,
            periodKey: "2026-05",
            score: 90,
            nickname: "Grace",
            periodStartUTC: Date(timeIntervalSince1970: 1_767_916_800),
            periodEndUTC: nil,
            appVersion: "1.2.3",
            updatedAt: Date(timeIntervalSince1970: 1_768_200_000)
        )
        let record = CloudKitLeaderboardRecordMapper.record(from: submission, userHash: "userhash")
        let score = CloudKitLeaderboardRecordMapper.score(from: record, rank: 7)

        #expect(score?.id == "score_v1_userhash_activityMinutes_month_2026-05")
        #expect(score?.userHash == "userhash")
        #expect(score?.metric == .activityMinutes)
        #expect(score?.period == .month)
        #expect(score?.periodKey == "2026-05")
        #expect(score?.score == 90)
        #expect(score?.rank == 7)
        #expect(score?.nickname == "Grace")
        #expect(score?.avatarSeed == nil)
    }

    @Test("Profile data overrides the nickname and avatar stored on older score records")
    func profileOverridesScoreProfileData() {
        let submission = LeaderboardSubmission(
            metric: .tokensWithCache,
            period: .day,
            periodKey: "2026-05-15",
            score: 100,
            nickname: "Old Name",
            periodStartUTC: Date(timeIntervalSince1970: 1_768_176_000),
            periodEndUTC: Date(timeIntervalSince1970: 1_768_262_400),
            appVersion: "1.2.3",
            updatedAt: Date(timeIntervalSince1970: 1_768_200_000)
        )
        let scoreRecord = CloudKitLeaderboardRecordMapper.record(from: submission, userHash: "userhash")
        let profile = CloudKitLeaderboardRecordMapper.profileRecord(
            userHash: "userhash",
            profile: LeaderboardProfileDraft(
                nickname: "New Name",
                avatarSeed: "avatar-seed",
                historyStartMonthKey: "2026-05",
                favoriteModels: [
                    LeaderboardFavoriteModel(rank: 1, model: "sonnet", tokens: 300),
                    LeaderboardFavoriteModel(rank: 2, model: "opus", tokens: 100),
                ],
                recentStatusID: LeaderboardRecentStatus.shipping.rawValue,
                recentStatusUpdatedAt: Date(timeIntervalSince1970: 1_768_205_000),
                appVersion: "1.2.3",
                updatedAt: Date(timeIntervalSince1970: 1_768_210_000)
            )
        )
        let mappedProfile = CloudKitLeaderboardRecordMapper.profile(from: profile)

        #expect(CloudKitLeaderboardRecordMapper.profileRecordName(userHash: "userhash") == "profile_v1_userhash")
        #expect(mappedProfile?.nickname == "New Name")
        #expect(mappedProfile?.avatarSeed == "avatar-seed")
        #expect(mappedProfile?.historyStartMonthKey == "2026-05")
        #expect(mappedProfile?.favoriteModels?.map(\.model) == ["sonnet", "opus"])
        #expect(mappedProfile?.favoriteModels?.map(\.tokens) == [300, 100])
        #expect(mappedProfile?.recentStatusID == "shipping")
        #expect(mappedProfile?.recentStatusUpdatedAt == Date(timeIntervalSince1970: 1_768_205_000))
        #expect(profile[CloudKitLeaderboardRecordMapper.Field.avatarVariant] as? String == "beam")
        #expect(profile[CloudKitLeaderboardRecordMapper.Field.historyStartMonthKey] as? String == "2026-05")
        #expect((profile[CloudKitLeaderboardRecordMapper.Field.favoriteModels] as? String)?.contains("sonnet") == true)
        #expect(profile[CloudKitLeaderboardRecordMapper.Field.recentStatusID] as? String == "shipping")
        #expect(CloudKitLeaderboardRecordMapper.userHash(from: scoreRecord) == "userhash")
        #expect(CloudKitLeaderboardRecordMapper.score(
            from: scoreRecord,
            rank: 1,
            profile: mappedProfile
        )?.nickname == "New Name")
        #expect(CloudKitLeaderboardRecordMapper.score(
            from: scoreRecord,
            rank: 1,
            profile: mappedProfile
        )?.avatarSeed == "avatar-seed")
        #expect(CloudKitLeaderboardRecordMapper.score(
            from: scoreRecord,
            rank: 1,
            profile: mappedProfile
        )?.favoriteModels?.first?.model == "sonnet")
        #expect(CloudKitLeaderboardRecordMapper.score(
            from: scoreRecord,
            rank: 1,
            profile: mappedProfile
        )?.recentStatusID == "shipping")
    }

    @Test("Empty recent status field clears the mapped public status")
    func emptyRecentStatusClearsStatus() {
        let recordID = CKRecord.ID(recordName: CloudKitLeaderboardRecordMapper.profileRecordName(userHash: "userhash"))
        let record = CKRecord(recordType: CloudKitLeaderboardConfig.recordType, recordID: recordID)
        record[CloudKitLeaderboardRecordMapper.Field.userHash] = "userhash"
        record[CloudKitLeaderboardRecordMapper.Field.nickname] = "Ada"
        record[CloudKitLeaderboardRecordMapper.Field.recentStatusID] = ""
        record[CloudKitLeaderboardRecordMapper.Field.recentStatusUpdatedAt] = Date(timeIntervalSince1970: 1_768_205_000) as NSDate
        record[CloudKitLeaderboardRecordMapper.Field.updatedAt] = Date(timeIntervalSince1970: 1_768_210_000) as NSDate

        let profile = CloudKitLeaderboardRecordMapper.profile(from: record)

        #expect(profile?.recentStatusID == nil)
        #expect(profile?.recentStatusUpdatedAt == Date(timeIntervalSince1970: 1_768_205_000))
    }

    @Test("Legacy profile records without avatar fields still map nickname")
    func legacyProfileWithoutAvatarMapsNickname() {
        let recordID = CKRecord.ID(recordName: CloudKitLeaderboardRecordMapper.profileRecordName(userHash: "legacy"))
        let record = CKRecord(recordType: CloudKitLeaderboardConfig.recordType, recordID: recordID)
        record[CloudKitLeaderboardRecordMapper.Field.userHash] = "legacy"
        record[CloudKitLeaderboardRecordMapper.Field.nickname] = "Legacy Name"
        record[CloudKitLeaderboardRecordMapper.Field.metric] = "profile"
        record[CloudKitLeaderboardRecordMapper.Field.period] = "profile"
        record[CloudKitLeaderboardRecordMapper.Field.periodKey] = "profile"
        record[CloudKitLeaderboardRecordMapper.Field.score] = NSNumber(value: 0)
        record[CloudKitLeaderboardRecordMapper.Field.updatedAt] = Date(timeIntervalSince1970: 1_768_210_000) as NSDate

        let profile = CloudKitLeaderboardRecordMapper.profile(from: record)

        #expect(profile?.userHash == "legacy")
        #expect(profile?.nickname == "Legacy Name")
        #expect(profile?.avatarSeed == nil)
    }

    @Test("Missing CloudKit entitlement is reported before touching CKContainer")
    func missingEntitlementShortCircuitsCloudKit() async {
        let client = CloudKitLeaderboardClient(entitlementChecker: { _ in false })
        let accountState = await client.accountState()

        #expect(accountState == .unavailable("CloudKit entitlement is missing or incomplete in this build."))

        do {
            _ = try await client.fetchScores(
                metric: .tokensWithCache,
                period: .day,
                periodKey: "2026-05-15",
                limit: 100
            )
            Issue.record("Expected missing entitlement error")
        } catch let error as LeaderboardCloudError {
            #expect(error.description == "CloudKit entitlement is missing or incomplete in this build.")
        } catch {
            Issue.record("Expected LeaderboardCloudError, got \(error)")
        }
    }
}
