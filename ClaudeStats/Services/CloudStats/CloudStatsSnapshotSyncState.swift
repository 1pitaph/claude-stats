import ClaudeStatsSync
import Foundation

enum CloudStatsSnapshotSyncPhase: Equatable, Sendable {
    case notChecked
    case missingEntitlement
    case checkingAccount
    case ready
    case publishing
    case published
    case unavailable
    case failed

    var displayText: String {
        switch self {
        case .notChecked:
            "Not checked"
        case .missingEntitlement:
            "CloudKit unavailable in this build"
        case .checkingAccount:
            "Checking iCloud"
        case .ready:
            "Ready"
        case .publishing:
            "Publishing"
        case .published:
            "Published"
        case .unavailable:
            "iCloud unavailable"
        case .failed:
            "Failed"
        }
    }
}

struct CloudStatsSnapshotSyncState: Equatable, Sendable {
    var phase: CloudStatsSnapshotSyncPhase = .notChecked
    var entitlementAvailable = false
    var accountStatus: CloudStatsAccountStatus = .unknown
    var lastCheckedAt: Date?
    var lastPublishedAt: Date?
    var lastSnapshotGeneratedAt: Date?
    var lastError: String?
    var lastPublishReason: String?

    var isBusy: Bool {
        phase == .checkingAccount || phase == .publishing
    }

    var canPublish: Bool {
        entitlementAvailable && phase != .checkingAccount && phase != .publishing
    }
}
