import Foundation

enum LeaderboardSyncLeaseVariant: String, Sendable, Codable {
    case full
    case lite
}

struct LeaderboardSyncLease: Sendable, Equatable {
    let userHash: String
    let ownerID: String
    let variant: LeaderboardSyncLeaseVariant
    let priority: Int
    let acquiredAt: Date
    let expiresAt: Date
}

struct LeaderboardSyncLeaseRequest: Sendable, Equatable {
    let userHash: String
    let ownerID: String
    let variant: LeaderboardSyncLeaseVariant
    let priority: Int
    let acquiredAt: Date
    let duration: TimeInterval

    var lease: LeaderboardSyncLease {
        LeaderboardSyncLease(
            userHash: userHash,
            ownerID: ownerID,
            variant: variant,
            priority: priority,
            acquiredAt: acquiredAt,
            expiresAt: acquiredAt.addingTimeInterval(duration)
        )
    }
}

enum LeaderboardSyncLeaseDecision: Sendable, Equatable {
    case acquired(LeaderboardSyncLease)
    case denied(active: LeaderboardSyncLease)
}

protocol LeaderboardSyncLeasing: Sendable {
    func acquire(_ request: LeaderboardSyncLeaseRequest) async throws -> LeaderboardSyncLeaseDecision
}

struct LeaderboardSyncLeasePolicy: Sendable, Equatable {
    let variant: LeaderboardSyncLeaseVariant
    let ownerID: String
    let priority: Int
    let duration: TimeInterval

    static func currentApp(ownerID: String = UUID().uuidString,
                           duration: TimeInterval = 120) -> LeaderboardSyncLeasePolicy {
        LeaderboardSyncLeasePolicy(
            variant: AppVariant.isLite ? .lite : .full,
            ownerID: ownerID,
            priority: AppVariant.isLite ? 10 : 100,
            duration: duration
        )
    }

    func request(userHash: String, now: Date) -> LeaderboardSyncLeaseRequest {
        LeaderboardSyncLeaseRequest(
            userHash: userHash,
            ownerID: ownerID,
            variant: variant,
            priority: priority,
            acquiredAt: now,
            duration: duration
        )
    }
}

enum LeaderboardSyncLeaseResolver {
    static func decision(for request: LeaderboardSyncLeaseRequest,
                         existing: LeaderboardSyncLease?,
                         now: Date) -> LeaderboardSyncLeaseDecision {
        guard let existing else {
            return .acquired(request.lease)
        }
        if existing.ownerID == request.ownerID
            || existing.expiresAt <= now
            || request.priority > existing.priority {
            return .acquired(request.lease)
        }
        return .denied(active: existing)
    }
}
