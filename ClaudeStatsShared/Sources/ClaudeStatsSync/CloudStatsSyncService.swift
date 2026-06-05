@preconcurrency import CloudKit
import ClaudeStatsCore
import Foundation

public enum CloudStatsAccountStatus: Equatable, Sendable {
    case unknown
    case available
    case noAccount
    case restricted
    case unavailable(String)

    public var displayText: String {
        switch self {
        case .unknown: "Not checked"
        case .available: "iCloud available"
        case .noAccount: "Sign in to iCloud"
        case .restricted: "iCloud restricted"
        case .unavailable(let reason): reason
        }
    }
}

public enum CloudStatsSyncError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    case noData
    case unsupportedSchema(Int)
    case cloudKit(String)

    public var description: String {
        switch self {
        case .noData:
            "No synced Claude Stats snapshot was found in iCloud."
        case .unsupportedSchema(let version):
            "The synced snapshot schema version \(version) is newer than this app supports."
        case .cloudKit(let reason):
            reason
        }
    }

    public var errorDescription: String? {
        description
    }
}

public struct CloudStatsRemoteMetadata: Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var appVersion: String

    public init(schemaVersion: Int, generatedAt: Date, appVersion: String) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.appVersion = appVersion
    }
}

public protocol CloudStatsRemoteClient: Sendable {
    func saveLatestSnapshotData(_ data: Data, metadata: CloudStatsRemoteMetadata) async throws
    func fetchLatestSnapshotData() async throws -> Data?
    func accountStatus() async -> CloudStatsAccountStatus
}

public struct CloudStatsSyncService: Sendable {
    private let client: any CloudStatsRemoteClient

    public init(client: any CloudStatsRemoteClient = CloudStatsCloudKitClient()) {
        self.client = client
    }

    public func accountStatus() async -> CloudStatsAccountStatus {
        await client.accountStatus()
    }

    public func publish(snapshot: StatsSnapshot) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let metadata = CloudStatsRemoteMetadata(
            schemaVersion: snapshot.schemaVersion,
            generatedAt: snapshot.generatedAt,
            appVersion: snapshot.appVersion
        )
        try await client.saveLatestSnapshotData(data, metadata: metadata)
    }

    public func loadLatestSnapshot() async throws -> StatsSnapshot? {
        guard let data = try await client.fetchLatestSnapshotData() else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(StatsSnapshot.self, from: data)
        guard snapshot.schemaVersion <= StatsSnapshotSchema.currentVersion else {
            throw CloudStatsSyncError.unsupportedSchema(snapshot.schemaVersion)
        }
        return snapshot
    }
}

public struct CloudStatsCloudKitClient: CloudStatsRemoteClient {
    public static let defaultContainerIdentifier = "iCloud.com.claudestats.ClaudeStats"
    public static let recordType = "StatsSnapshotV1"
    public static let latestRecordName = "stats_snapshot_latest_v1"

    private enum Record {
        static let type = CloudStatsCloudKitClient.recordType
        static let latestName = CloudStatsCloudKitClient.latestRecordName
    }

    private enum Field {
        static let payload = "payload"
        static let schemaVersion = "schemaVersion"
        static let generatedAt = "generatedAt"
        static let appVersion = "appVersion"
        static let updatedAt = "updatedAt"
    }

    private let containerIdentifier: String

    public init(containerIdentifier: String = Self.defaultContainerIdentifier) {
        self.containerIdentifier = containerIdentifier
    }

    public func accountStatus() async -> CloudStatsAccountStatus {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .couldNotDetermine:
                return .unknown
            case .temporarilyUnavailable:
                return .unavailable("iCloud is temporarily unavailable.")
            @unknown default:
                return .unknown
            }
        } catch {
            return .unavailable(Self.shortCloudKitMessage(error))
        }
    }

    public func saveLatestSnapshotData(_ data: Data, metadata: CloudStatsRemoteMetadata) async throws {
        let recordID = CKRecord.ID(recordName: Record.latestName)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch {
            if Self.isUnknownItem(error) {
                record = CKRecord(recordType: Record.type, recordID: recordID)
            } else {
                throw CloudStatsSyncError.cloudKit(Self.shortCloudKitMessage(error))
            }
        }

        record[Field.payload] = data as NSData
        record[Field.schemaVersion] = metadata.schemaVersion as NSNumber
        record[Field.generatedAt] = metadata.generatedAt as NSDate
        record[Field.appVersion] = metadata.appVersion as NSString
        record[Field.updatedAt] = Date() as NSDate

        do {
            _ = try await database.save(record)
        } catch {
            throw CloudStatsSyncError.cloudKit(Self.shortCloudKitMessage(error))
        }
    }

    public func fetchLatestSnapshotData() async throws -> Data? {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: Record.latestName))
            if let data = record[Field.payload] as? Data {
                return data
            }
            if let data = record[Field.payload] as? NSData {
                return data as Data
            }
            return nil
        } catch {
            if Self.isUnknownItem(error) { return nil }
            throw CloudStatsSyncError.cloudKit(Self.shortCloudKitMessage(error))
        }
    }

    private var container: CKContainer {
        CKContainer(identifier: containerIdentifier)
    }

    private var database: CKDatabase {
        container.privateCloudDatabase
    }

    private static func isUnknownItem(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        return ckError.code == .unknownItem
    }

    private static func shortCloudKitMessage(_ error: Error) -> String {
        if let syncError = error as? CloudStatsSyncError {
            return syncError.description
        }
        if let ckError = error as? CKError {
            if let message = ckError.errorUserInfo[NSLocalizedDescriptionKey] as? String, !message.isEmpty {
                return message
            }
            return ckError.localizedDescription
        }
        return error.localizedDescription
    }
}
