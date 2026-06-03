import Foundation

struct LeaderboardProfileMergeResult: Sendable, Equatable {
    let draft: LeaderboardProfileDraft
    let shouldUpdateLocalNickname: Bool
    let shouldUpdateLocalAvatarSeed: Bool
}

enum LeaderboardProfileMergePolicy {
    static func merge(local: LeaderboardProfileDraft,
                      remote: LeaderboardProfile?,
                      prefersRemoteAvatarSeed: Bool = false) -> LeaderboardProfileMergeResult {
        guard let remote else {
            return LeaderboardProfileMergeResult(
                draft: local,
                shouldUpdateLocalNickname: false,
                shouldUpdateLocalAvatarSeed: false
            )
        }

        let localNickname = local.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteNickname = remote.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname = localNickname.isEmpty ? remoteNickname : localNickname

        let localAvatarSeed = local.avatarSeed.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteAvatarSeed = remote.avatarSeed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shouldUseRemoteAvatarSeed = !remoteAvatarSeed.isEmpty
            && (localAvatarSeed.isEmpty || prefersRemoteAvatarSeed)
        let avatarSeed = shouldUseRemoteAvatarSeed ? remoteAvatarSeed : localAvatarSeed

        let historyStartMonthKey = earliestMonthKey(local.historyStartMonthKey, remote.historyStartMonthKey)
        let favoriteModels = favoriteModels(local: local.favoriteModels, remote: remote.favoriteModels)

        return LeaderboardProfileMergeResult(
            draft: LeaderboardProfileDraft(
                nickname: nickname,
                avatarSeed: avatarSeed,
                historyStartMonthKey: historyStartMonthKey,
                favoriteModels: favoriteModels,
                appVersion: local.appVersion,
                updatedAt: local.updatedAt
            ),
            shouldUpdateLocalNickname: localNickname.isEmpty && !remoteNickname.isEmpty,
            shouldUpdateLocalAvatarSeed: shouldUseRemoteAvatarSeed
        )
    }

    private static func earliestMonthKey(_ lhs: String?, _ rhs: String?) -> String? {
        let values = [lhs, rhs]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.min()
    }

    private static func favoriteModels(local: [LeaderboardFavoriteModel]?,
                                       remote: [LeaderboardFavoriteModel]?) -> [LeaderboardFavoriteModel]? {
        if let local, !local.isEmpty {
            return local
        }
        if let remote, !remote.isEmpty {
            return remote
        }
        return local ?? remote
    }
}
