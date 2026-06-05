import Foundation

struct LeaderboardProfileMergeResult: Sendable, Equatable {
    let draft: LeaderboardProfileDraft
    let shouldUpdateLocalNickname: Bool
    let shouldUpdateLocalAvatarSeed: Bool
    let shouldUpdateLocalRecentStatus: Bool
}

enum LeaderboardProfileMergePolicy {
    static func merge(local: LeaderboardProfileDraft,
                      remote: LeaderboardProfile?,
                      prefersRemoteAvatarSeed: Bool = false) -> LeaderboardProfileMergeResult {
        guard let remote else {
            return LeaderboardProfileMergeResult(
                draft: local,
                shouldUpdateLocalNickname: false,
                shouldUpdateLocalAvatarSeed: false,
                shouldUpdateLocalRecentStatus: false
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
        let recentStatus = recentStatus(local: local, remote: remote)

        return LeaderboardProfileMergeResult(
            draft: LeaderboardProfileDraft(
                nickname: nickname,
                avatarSeed: avatarSeed,
                historyStartMonthKey: historyStartMonthKey,
                favoriteModels: favoriteModels,
                recentStatusID: recentStatus.id,
                recentStatusUpdatedAt: recentStatus.updatedAt,
                appVersion: local.appVersion,
                updatedAt: local.updatedAt
            ),
            shouldUpdateLocalNickname: localNickname.isEmpty && !remoteNickname.isEmpty,
            shouldUpdateLocalAvatarSeed: shouldUseRemoteAvatarSeed,
            shouldUpdateLocalRecentStatus: recentStatus.shouldUpdateLocal
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

    private static func recentStatus(
        local: LeaderboardProfileDraft,
        remote: LeaderboardProfile
    ) -> (id: String?, updatedAt: Date?, shouldUpdateLocal: Bool) {
        let localID = LeaderboardRecentStatus.normalizedID(local.recentStatusID)
        let remoteID = LeaderboardRecentStatus.normalizedID(remote.recentStatusID)

        let useRemote: Bool
        if let localUpdatedAt = local.recentStatusUpdatedAt,
           let remoteUpdatedAt = remote.recentStatusUpdatedAt {
            useRemote = remoteUpdatedAt > localUpdatedAt
        } else if local.recentStatusUpdatedAt == nil,
                  remote.recentStatusUpdatedAt != nil {
            useRemote = localID == nil
        } else if local.recentStatusUpdatedAt == nil,
                  remoteID != nil {
            useRemote = true
        } else {
            useRemote = false
        }

        if useRemote {
            return (
                remoteID,
                remote.recentStatusUpdatedAt,
                localID != remoteID || local.recentStatusUpdatedAt != remote.recentStatusUpdatedAt
            )
        }
        return (localID, local.recentStatusUpdatedAt, false)
    }
}
