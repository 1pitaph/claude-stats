import Foundation
import Testing
@testable import ClaudeStats

@Suite("LeaderboardSyncLease")
struct LeaderboardSyncLeaseTests {
    @Test("Full app lease preempts an active Lite lease")
    func fullPreemptsLite() {
        let now = Date(timeIntervalSince1970: 100)
        let lite = lease(ownerID: "lite", variant: .lite, priority: 10, now: now)
        let request = request(ownerID: "full", variant: .full, priority: 100, now: now.addingTimeInterval(1))

        let decision = LeaderboardSyncLeaseResolver.decision(for: request, existing: lite, now: request.acquiredAt)

        #expect(decision == .acquired(request.lease))
    }

    @Test("Lite app cannot preempt an active full app lease")
    func liteCannotPreemptFull() {
        let now = Date(timeIntervalSince1970: 100)
        let full = lease(ownerID: "full", variant: .full, priority: 100, now: now)
        let request = request(ownerID: "lite", variant: .lite, priority: 10, now: now.addingTimeInterval(1))

        let decision = LeaderboardSyncLeaseResolver.decision(for: request, existing: full, now: request.acquiredAt)

        #expect(decision == .denied(active: full))
    }

    @Test("Expired lease can be acquired by any variant")
    func expiredLeaseCanBeAcquired() {
        let now = Date(timeIntervalSince1970: 100)
        let expired = LeaderboardSyncLease(
            userHash: "userhash",
            ownerID: "full",
            variant: .full,
            priority: 100,
            acquiredAt: now,
            expiresAt: now.addingTimeInterval(10)
        )
        let request = request(ownerID: "lite", variant: .lite, priority: 10, now: now.addingTimeInterval(11))

        let decision = LeaderboardSyncLeaseResolver.decision(for: request, existing: expired, now: request.acquiredAt)

        #expect(decision == .acquired(request.lease))
    }

    private func request(ownerID: String,
                         variant: LeaderboardSyncLeaseVariant,
                         priority: Int,
                         now: Date) -> LeaderboardSyncLeaseRequest {
        LeaderboardSyncLeaseRequest(
            userHash: "userhash",
            ownerID: ownerID,
            variant: variant,
            priority: priority,
            acquiredAt: now,
            duration: 120
        )
    }

    private func lease(ownerID: String,
                       variant: LeaderboardSyncLeaseVariant,
                       priority: Int,
                       now: Date) -> LeaderboardSyncLease {
        LeaderboardSyncLease(
            userHash: "userhash",
            ownerID: ownerID,
            variant: variant,
            priority: priority,
            acquiredAt: now,
            expiresAt: now.addingTimeInterval(120)
        )
    }
}
