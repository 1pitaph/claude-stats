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

    private func draft(nickname: String,
                       avatarSeed: String,
                       historyStartMonthKey: String? = nil) -> LeaderboardProfileDraft {
        LeaderboardProfileDraft(
            nickname: nickname,
            avatarSeed: avatarSeed,
            historyStartMonthKey: historyStartMonthKey,
            appVersion: "test",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func profile(nickname: String,
                         avatarSeed: String?,
                         historyStartMonthKey: String? = nil) -> LeaderboardProfile {
        LeaderboardProfile(
            userHash: "userhash",
            nickname: nickname,
            avatarSeed: avatarSeed,
            historyStartMonthKey: historyStartMonthKey,
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }
}
