import Foundation
import Testing
@testable import ClaudeStats

@Suite("LeaderboardProfileMergePolicy")
struct LeaderboardProfileMergePolicyTests {
    @Test("Remote nickname fills an empty local nickname")
    func remoteNicknameFillsEmptyLocalNickname() {
        let result = LeaderboardProfileMergePolicy.merge(
            local: draft(nickname: "", avatarSeed: ""),
            remote: profile(nickname: "Remote Ada", avatarSeed: "avatar-remote")
        )

        #expect(result.draft.nickname == "Remote Ada")
        #expect(result.draft.avatarSeed == "avatar-remote")
        #expect(result.shouldUpdateLocalNickname)
        #expect(result.shouldUpdateLocalAvatarSeed)
    }

    @Test("Local nickname is preserved when remote differs")
    func localNicknameWins() {
        let result = LeaderboardProfileMergePolicy.merge(
            local: draft(nickname: "Local Ada", avatarSeed: "avatar-local"),
            remote: profile(nickname: "Remote Ada", avatarSeed: "avatar-remote")
        )

        #expect(result.draft.nickname == "Local Ada")
        #expect(result.draft.avatarSeed == "avatar-local")
        #expect(result.shouldUpdateLocalNickname == false)
        #expect(result.shouldUpdateLocalAvatarSeed == false)
    }

    @Test("Remote avatar can win when rebinding an iCloud profile")
    func remoteAvatarWinsWhenPreferred() {
        let result = LeaderboardProfileMergePolicy.merge(
            local: draft(nickname: "Local Ada", avatarSeed: "avatar-local"),
            remote: profile(nickname: "Remote Ada", avatarSeed: "avatar-remote"),
            prefersRemoteAvatarSeed: true
        )

        #expect(result.draft.nickname == "Local Ada")
        #expect(result.draft.avatarSeed == "avatar-remote")
        #expect(result.shouldUpdateLocalAvatarSeed)
    }

    @Test("Earliest history month is preserved")
    func earliestHistoryMonthWins() {
        let result = LeaderboardProfileMergePolicy.merge(
            local: draft(nickname: "Ada", avatarSeed: "avatar-local", historyStartMonthKey: "2026-05"),
            remote: profile(nickname: "Ada", avatarSeed: "avatar-remote", historyStartMonthKey: "2026-03")
        )

        #expect(result.draft.historyStartMonthKey == "2026-03")
    }

    @Test("Newer recent status wins across devices")
    func newerRecentStatusWins() {
        let older = Date(timeIntervalSince1970: 1)
        let newer = Date(timeIntervalSince1970: 2)

        let localWins = LeaderboardProfileMergePolicy.merge(
            local: draft(
                nickname: "Ada",
                avatarSeed: "avatar-local",
                recentStatusID: .focused,
                recentStatusUpdatedAt: newer
            ),
            remote: profile(
                nickname: "Ada",
                avatarSeed: "avatar-remote",
                recentStatusID: .away,
                recentStatusUpdatedAt: older
            )
        )
        #expect(localWins.draft.recentStatusID == "focused")
        #expect(localWins.shouldUpdateLocalRecentStatus == false)

        let remoteWins = LeaderboardProfileMergePolicy.merge(
            local: draft(
                nickname: "Ada",
                avatarSeed: "avatar-local",
                recentStatusID: .focused,
                recentStatusUpdatedAt: older
            ),
            remote: profile(
                nickname: "Ada",
                avatarSeed: "avatar-remote",
                recentStatusID: .shipping,
                recentStatusUpdatedAt: newer
            )
        )
        #expect(remoteWins.draft.recentStatusID == "shipping")
        #expect(remoteWins.shouldUpdateLocalRecentStatus)
    }

    @Test("Newer remote clear removes local recent status")
    func newerRemoteClearWins() {
        let result = LeaderboardProfileMergePolicy.merge(
            local: draft(
                nickname: "Ada",
                avatarSeed: "avatar-local",
                recentStatusID: .debugging,
                recentStatusUpdatedAt: Date(timeIntervalSince1970: 1)
            ),
            remote: profile(
                nickname: "Ada",
                avatarSeed: "avatar-remote",
                recentStatusID: nil,
                recentStatusUpdatedAt: Date(timeIntervalSince1970: 2)
            )
        )

        #expect(result.draft.recentStatusID == nil)
        #expect(result.shouldUpdateLocalRecentStatus)
    }

    private func draft(nickname: String,
                       avatarSeed: String,
                       historyStartMonthKey: String? = nil,
                       recentStatusID: LeaderboardRecentStatus? = nil,
                       recentStatusUpdatedAt: Date? = nil) -> LeaderboardProfileDraft {
        LeaderboardProfileDraft(
            nickname: nickname,
            avatarSeed: avatarSeed,
            historyStartMonthKey: historyStartMonthKey,
            recentStatusID: recentStatusID?.rawValue,
            recentStatusUpdatedAt: recentStatusUpdatedAt,
            appVersion: "test",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func profile(nickname: String,
                         avatarSeed: String?,
                         historyStartMonthKey: String? = nil,
                         recentStatusID: LeaderboardRecentStatus? = nil,
                         recentStatusUpdatedAt: Date? = nil) -> LeaderboardProfile {
        LeaderboardProfile(
            userHash: "userhash",
            nickname: nickname,
            avatarSeed: avatarSeed,
            historyStartMonthKey: historyStartMonthKey,
            recentStatusID: recentStatusID?.rawValue,
            recentStatusUpdatedAt: recentStatusUpdatedAt,
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }
}
