import CloudKit
import Foundation

struct CloudKitLeaderboardSyncLeaseClient: LeaderboardSyncLeasing {
    private let containerIdentifier: String
    private let entitlementChecker: @Sendable (String) -> Bool

    init(containerIdentifier: String = CloudKitLeaderboardConfig.containerIdentifier,
         entitlementChecker: @escaping @Sendable (String) -> Bool = CloudKitRuntimeEntitlements.hasCloudKitAccess) {
        self.containerIdentifier = containerIdentifier
        self.entitlementChecker = entitlementChecker
    }

    func acquire(_ request: LeaderboardSyncLeaseRequest) async throws -> LeaderboardSyncLeaseDecision {
        try ensureCloudKitEntitlement()
        return try await acquire(request, remainingRetries: 1)
    }

    private func acquire(_ request: LeaderboardSyncLeaseRequest,
                         remainingRetries: Int) async throws -> LeaderboardSyncLeaseDecision {
        let recordID = CKRecord.ID(recordName: Self.recordName(userHash: request.userHash))
        let existing = try await fetchLeaseRecord(recordID: recordID)
        let existingLease = existing.flatMap(Self.lease(from:))
        let decision = LeaderboardSyncLeaseResolver.decision(
            for: request,
            existing: existingLease,
            now: request.acquiredAt
        )

        guard case .acquired(let lease) = decision else {
            return decision
        }

        let record = existing ?? CKRecord(recordType: CloudKitLeaderboardConfig.recordType, recordID: recordID)
        Self.apply(lease, to: record)

        do {
            let result = try await publicDatabase.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            if case .failure(let error) = result.saveResults[recordID] {
                if remainingRetries > 0, Self.isServerRecordChanged(error) {
                    return try await acquire(request, remainingRetries: remainingRetries - 1)
                }
                throw LeaderboardCloudError.cloudKit(Self.shortCloudKitMessage(error))
            }
            return .acquired(lease)
        } catch let error as LeaderboardCloudError {
            throw error
        } catch {
            if remainingRetries > 0, Self.isServerRecordChanged(error) {
                return try await acquire(request, remainingRetries: remainingRetries - 1)
            }
            throw LeaderboardCloudError.cloudKit(Self.shortCloudKitMessage(error))
        }
    }

    private var container: CKContainer {
        CKContainer(identifier: containerIdentifier)
    }

    private var publicDatabase: CKDatabase {
        container.publicCloudDatabase
    }

    private func ensureCloudKitEntitlement() throws {
        guard entitlementChecker(containerIdentifier) else {
            throw LeaderboardCloudError.missingEntitlement(Self.missingEntitlementMessage)
        }
    }

    private func fetchLeaseRecord(recordID: CKRecord.ID) async throws -> CKRecord? {
        do {
            let results = try await publicDatabase.records(
                for: [recordID],
                desiredKeys: Self.desiredKeys
            )
            guard let result = results[recordID] else { return nil }
            switch result {
            case .success(let record):
                return record
            case .failure(let error):
                if Self.isUnknownItem(error) {
                    return nil
                }
                throw LeaderboardCloudError.cloudKit(Self.shortCloudKitMessage(error))
            }
        } catch let error as LeaderboardCloudError {
            throw error
        } catch {
            throw LeaderboardCloudError.cloudKit(Self.shortCloudKitMessage(error))
        }
    }

    private static let missingEntitlementMessage = "CloudKit entitlement is missing or incomplete in this build."
    private static let leaseMetric = "syncLease"
    private static let leasePeriod = "global"
    private static let leasePeriodKey = "current"
    private static let desiredKeys = [
        CloudKitLeaderboardRecordMapper.Field.userHash,
        CloudKitLeaderboardRecordMapper.Field.nickname,
        CloudKitLeaderboardRecordMapper.Field.metric,
        CloudKitLeaderboardRecordMapper.Field.period,
        CloudKitLeaderboardRecordMapper.Field.periodKey,
        CloudKitLeaderboardRecordMapper.Field.score,
        CloudKitLeaderboardRecordMapper.Field.providerScope,
        CloudKitLeaderboardRecordMapper.Field.periodStartUTC,
        CloudKitLeaderboardRecordMapper.Field.periodEndUTC,
        CloudKitLeaderboardRecordMapper.Field.avatarVariant,
    ]

    private static func recordName(userHash: String) -> String {
        "sync_lease_v1_\(userHash)"
    }

    private static func apply(_ lease: LeaderboardSyncLease, to record: CKRecord) {
        record[CloudKitLeaderboardRecordMapper.Field.userHash] = lease.userHash
        record[CloudKitLeaderboardRecordMapper.Field.nickname] = lease.ownerID
        record[CloudKitLeaderboardRecordMapper.Field.metric] = leaseMetric
        record[CloudKitLeaderboardRecordMapper.Field.period] = leasePeriod
        record[CloudKitLeaderboardRecordMapper.Field.periodKey] = leasePeriodKey
        record[CloudKitLeaderboardRecordMapper.Field.score] = NSNumber(value: lease.priority)
        record[CloudKitLeaderboardRecordMapper.Field.providerScope] = CloudKitLeaderboardConfig.syncLeaseProviderScope
        record[CloudKitLeaderboardRecordMapper.Field.periodStartUTC] = lease.acquiredAt as NSDate
        record[CloudKitLeaderboardRecordMapper.Field.periodEndUTC] = lease.expiresAt as NSDate
        record[CloudKitLeaderboardRecordMapper.Field.avatarVariant] = lease.variant.rawValue
        record[CloudKitLeaderboardRecordMapper.Field.updatedAt] = lease.acquiredAt as NSDate
    }

    private static func lease(from record: CKRecord) -> LeaderboardSyncLease? {
        guard (record[CloudKitLeaderboardRecordMapper.Field.metric] as? String) == leaseMetric,
              (record[CloudKitLeaderboardRecordMapper.Field.providerScope] as? String) == CloudKitLeaderboardConfig.syncLeaseProviderScope,
              let userHash = record[CloudKitLeaderboardRecordMapper.Field.userHash] as? String,
              let ownerID = record[CloudKitLeaderboardRecordMapper.Field.nickname] as? String,
              let variantRaw = record[CloudKitLeaderboardRecordMapper.Field.avatarVariant] as? String,
              let variant = LeaderboardSyncLeaseVariant(rawValue: variantRaw),
              let priority = CloudKitLeaderboardRecordMapper.int64Value(record[CloudKitLeaderboardRecordMapper.Field.score]),
              let acquiredAt = CloudKitLeaderboardRecordMapper.dateValue(record[CloudKitLeaderboardRecordMapper.Field.periodStartUTC]),
              let expiresAt = CloudKitLeaderboardRecordMapper.dateValue(record[CloudKitLeaderboardRecordMapper.Field.periodEndUTC]) else {
            return nil
        }
        return LeaderboardSyncLease(
            userHash: userHash,
            ownerID: ownerID,
            variant: variant,
            priority: Int(priority),
            acquiredAt: acquiredAt,
            expiresAt: expiresAt
        )
    }

    private static func isUnknownItem(_ error: Error) -> Bool {
        (error as? CKError)?.code == .unknownItem
    }

    private static func isServerRecordChanged(_ error: Error) -> Bool {
        (error as? CKError)?.code == .serverRecordChanged
    }

    private static func shortCloudKitMessage(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated:
                return LeaderboardCloudError.noAccount.description
            case .networkUnavailable, .networkFailure:
                return "Network unavailable."
            case .serviceUnavailable:
                return "CloudKit service unavailable."
            case .quotaExceeded:
                return "CloudKit quota exceeded."
            case .permissionFailure:
                return "CloudKit permission denied."
            case .serverRejectedRequest:
                return "CloudKit rejected the request."
            case .serverRecordChanged:
                return "CloudKit sync lease changed. Try again shortly."
            default:
                return ck.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
