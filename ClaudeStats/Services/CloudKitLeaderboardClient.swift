import CloudKit
import CryptoKit
import Foundation
import Security

enum LeaderboardCloudAccountState: Sendable, Equatable {
    case unknown
    case available
    case noAccount
    case restricted
    case unavailable(String)

    var displayText: String {
        switch self {
        case .unknown: "Not checked"
        case .available: "iCloud available"
        case .noAccount: "Sign in to iCloud"
        case .restricted: "iCloud restricted"
        case .unavailable(let reason): reason
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

enum LeaderboardCloudError: Error, Sendable, CustomStringConvertible {
    case missingEntitlement(String)
    case noAccount
    case restricted
    case userRecordUnavailable
    case partialFailure(String)
    case cloudKit(String)

    var description: String {
        switch self {
        case .missingEntitlement(let reason): reason
        case .noAccount: "Sign in to iCloud to use leaderboards."
        case .restricted: "iCloud access is restricted on this Mac."
        case .userRecordUnavailable: "Could not identify the iCloud user."
        case .partialFailure(let reason): reason
        case .cloudKit(let reason): reason
        }
    }
}

protocol LeaderboardCloudServicing: Sendable {
    func accountState() async -> LeaderboardCloudAccountState
    func currentUserHash() async throws -> String
    func saveProfile(_ profile: LeaderboardProfileDraft) async throws -> LeaderboardProfile
    func fetchProfile(userHash: String) async throws -> LeaderboardProfile?
    func submit(_ submissions: [LeaderboardSubmission],
                historySubmissions: [LeaderboardHistorySubmission],
                profile: LeaderboardProfileDraft) async throws -> LeaderboardProfile
    func fetchScores(metric: LeaderboardMetric,
                     period: LeaderboardPeriod,
                     periodKey: String,
                     limit: Int) async throws -> [LeaderboardScore]
    func fetchScoreHistory(userHash: String,
                           metric: LeaderboardMetric,
                           period: LeaderboardPeriod,
                           windows: [LeaderboardPeriodWindow]) async throws -> [LeaderboardScoreHistoryPoint]
}

enum CloudKitLeaderboardConfig {
    static let containerIdentifier = "iCloud.com.claudestats.ClaudeStats"
    static let recordType = "LeaderboardScoreV1"
    static let providerScope = "all"
    static let historyProviderScope = "history"
    static let syncLeaseProviderScope = "syncLease"
}

enum CloudKitRuntimeEntitlements {
    private static let applicationIdentifierKey = "com.apple.application-identifier"
    private static let iCloudServicesKey = "com.apple.developer.icloud-services"
    private static let iCloudContainersKey = "com.apple.developer.icloud-container-identifiers"

    static func hasCloudKitAccess(containerIdentifier: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let applicationIdentifier = entitlementValue(applicationIdentifierKey, task: task) as? String,
              !applicationIdentifier.isEmpty,
              let services = entitlementValue(iCloudServicesKey, task: task) as? [String],
              services.contains("CloudKit"),
              let containers = entitlementValue(iCloudContainersKey, task: task) as? [String],
              containers.contains(containerIdentifier) else {
            return false
        }
        return true
    }

    private static func entitlementValue(_ key: String, task: SecTask) -> Any? {
        SecTaskCopyValueForEntitlement(task, key as CFString, nil)
    }
}

enum CloudKitLeaderboardRecordMapper {
    static let salt = "com.claudestats.leaderboards.v1"
    private static let profileMetric = "profile"
    private static let profilePeriod = "profile"
    private static let profilePeriodKey = "profile"

    enum Field {
        static let userHash = "userHash"
        static let nickname = "nickname"
        static let metric = "metric"
        static let period = "period"
        static let periodKey = "periodKey"
        static let score = "score"
        static let providerScope = "providerScope"
        static let periodStartUTC = "periodStartUTC"
        static let periodEndUTC = "periodEndUTC"
        static let appVersion = "appVersion"
        static let calculationVersion = "calculationVersion"
        static let updatedAt = "updatedAt"
        static let avatarSeed = "avatarSeed"
        static let avatarVariant = "avatarVariant"
        static let historyStartMonthKey = "historyStartMonthKey"
        static let favoriteModels = "favoriteModels"
        static let recentStatusID = "recentStatusID"
        static let recentStatusUpdatedAt = "recentStatusUpdatedAt"
    }

    static let avatarVariant = "beam"

    static let desiredKeys = [
        Field.userHash,
        Field.nickname,
        Field.metric,
        Field.period,
        Field.periodKey,
        Field.score,
        Field.updatedAt,
    ]

    static let profileDesiredKeys = [
        Field.userHash,
        Field.nickname,
        Field.avatarSeed,
        Field.avatarVariant,
        Field.historyStartMonthKey,
        Field.favoriteModels,
        Field.recentStatusID,
        Field.recentStatusUpdatedAt,
        Field.updatedAt,
    ]

    static func userHash(forUserRecordName recordName: String) -> String {
        let digest = SHA256.hash(data: Data("\(recordName):\(salt)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func recordName(userHash: String,
                           metric: LeaderboardMetric,
                           period: LeaderboardPeriod,
                           periodKey: String) -> String {
        "score_v1_\(userHash)_\(metric.rawValue)_\(period.rawValue)_\(periodKey)"
    }

    static func historyRecordName(userHash: String,
                                  metric: LeaderboardMetric,
                                  bucketPeriod: LeaderboardPeriod,
                                  periodKey: String) -> String {
        "history_v1_\(userHash)_\(metric.rawValue)_\(bucketPeriod.rawValue)_\(periodKey)"
    }

    static func isScoreRecord(_ record: CKRecord) -> Bool {
        record.recordID.recordName.hasPrefix("score_v1_")
    }

    static func rankedScores(from records: [CKRecord],
                             profiles: [String: LeaderboardProfile] = [:]) -> [LeaderboardScore] {
        records
            .filter(isScoreRecord)
            .enumerated()
            .compactMap { index, record in
                let userHash = userHash(from: record)
                return score(
                    from: record,
                    rank: index + 1,
                    profile: userHash.flatMap { profiles[$0] }
                )
            }
    }

    static func record(from submission: LeaderboardSubmission, userHash: String) -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName(
            userHash: userHash,
            metric: submission.metric,
            period: submission.period,
            periodKey: submission.periodKey
        ))
        let record = CKRecord(recordType: CloudKitLeaderboardConfig.recordType, recordID: recordID)
        record[Field.userHash] = userHash
        record[Field.nickname] = submission.nickname
        record[Field.metric] = submission.metric.rawValue
        record[Field.period] = submission.period.rawValue
        record[Field.periodKey] = submission.periodKey
        record[Field.score] = NSNumber(value: submission.score)
        record[Field.providerScope] = CloudKitLeaderboardConfig.providerScope
        record[Field.periodStartUTC] = submission.periodStartUTC as NSDate
        if let periodEndUTC = submission.periodEndUTC {
            record[Field.periodEndUTC] = periodEndUTC as NSDate
        }
        record[Field.appVersion] = submission.appVersion
        record[Field.calculationVersion] = NSNumber(value: submission.calculationVersion)
        record[Field.updatedAt] = submission.updatedAt as NSDate
        return record
    }

    static func historyRecord(from submission: LeaderboardHistorySubmission, userHash: String) -> CKRecord {
        let recordID = CKRecord.ID(recordName: historyRecordName(
            userHash: userHash,
            metric: submission.metric,
            bucketPeriod: submission.bucketPeriod,
            periodKey: submission.periodKey
        ))
        let record = CKRecord(recordType: CloudKitLeaderboardConfig.recordType, recordID: recordID)
        record[Field.userHash] = userHash
        record[Field.metric] = submission.metric.rawValue
        record[Field.period] = submission.bucketPeriod.rawValue
        record[Field.periodKey] = submission.periodKey
        record[Field.score] = NSNumber(value: submission.score)
        record[Field.providerScope] = CloudKitLeaderboardConfig.historyProviderScope
        record[Field.periodStartUTC] = submission.periodStartUTC as NSDate
        if let periodEndUTC = submission.periodEndUTC {
            record[Field.periodEndUTC] = periodEndUTC as NSDate
        }
        record[Field.appVersion] = submission.appVersion
        record[Field.calculationVersion] = NSNumber(value: submission.calculationVersion)
        record[Field.updatedAt] = submission.updatedAt as NSDate
        return record
    }

    static func profileRecordName(userHash: String) -> String {
        "profile_v1_\(userHash)"
    }

    static func profileRecord(userHash: String, profile: LeaderboardProfileDraft) -> CKRecord {
        let recordID = CKRecord.ID(recordName: profileRecordName(userHash: userHash))
        let record = CKRecord(recordType: CloudKitLeaderboardConfig.recordType, recordID: recordID)
        record[Field.userHash] = userHash
        record[Field.nickname] = profile.nickname
        record[Field.avatarSeed] = profile.avatarSeed
        record[Field.avatarVariant] = avatarVariant
        if let historyStartMonthKey = profile.historyStartMonthKey {
            record[Field.historyStartMonthKey] = historyStartMonthKey
        }
        if let favoriteModels = profile.favoriteModels,
           let encodedFavoriteModels = encodeFavoriteModels(favoriteModels) {
            record[Field.favoriteModels] = encodedFavoriteModels
        }
        record[Field.recentStatusID] = profile.recentStatusID ?? ""
        if let recentStatusUpdatedAt = profile.recentStatusUpdatedAt {
            record[Field.recentStatusUpdatedAt] = recentStatusUpdatedAt as NSDate
        } else {
            record[Field.recentStatusUpdatedAt] = Date(timeIntervalSince1970: 0) as NSDate
        }
        record[Field.metric] = profileMetric
        record[Field.period] = profilePeriod
        record[Field.periodKey] = profilePeriodKey
        record[Field.score] = NSNumber(value: 0)
        record[Field.providerScope] = CloudKitLeaderboardConfig.providerScope
        record[Field.periodStartUTC] = Date(timeIntervalSince1970: 0) as NSDate
        record[Field.appVersion] = profile.appVersion
        record[Field.updatedAt] = profile.updatedAt as NSDate
        return record
    }

    static func userHash(from record: CKRecord) -> String? {
        record[Field.userHash] as? String
    }

    static func profile(from record: CKRecord) -> LeaderboardProfile? {
        guard let userHash = record[Field.userHash] as? String,
              let nickname = record[Field.nickname] as? String,
              !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let avatarSeed = record[Field.avatarSeed] as? String
        let historyStartMonthKey = record[Field.historyStartMonthKey] as? String
        let favoriteModels = decodeFavoriteModels(from: record)
        let recentStatusID = LeaderboardRecentStatus.normalizedID(record[Field.recentStatusID] as? String)
        let recentStatusUpdatedAt = dateValue(record[Field.recentStatusUpdatedAt])
        let updatedAt = (record[Field.updatedAt] as? Date)
            ?? (record[Field.updatedAt] as? NSDate).map { $0 as Date }
            ?? record.modificationDate
            ?? Date(timeIntervalSince1970: 0)
        return LeaderboardProfile(
            userHash: userHash,
            nickname: nickname,
            avatarSeed: avatarSeed?.isEmpty == false ? avatarSeed : nil,
            historyStartMonthKey: historyStartMonthKey?.isEmpty == false ? historyStartMonthKey : nil,
            favoriteModels: favoriteModels,
            recentStatusID: recentStatusID,
            recentStatusUpdatedAt: recentStatusUpdatedAt,
            updatedAt: updatedAt
        )
    }

    static func profileNickname(from record: CKRecord) -> (userHash: String, nickname: String)? {
        profile(from: record).map { ($0.userHash, $0.nickname) }
    }

    static func score(from record: CKRecord, rank: Int) -> LeaderboardScore? {
        score(from: record, rank: rank, profile: nil)
    }

    static func score(from record: CKRecord, rank: Int, profile: LeaderboardProfile?) -> LeaderboardScore? {
        guard let metricRaw = record[Field.metric] as? String,
              let metric = LeaderboardMetric(rawValue: metricRaw),
              let periodRaw = record[Field.period] as? String,
              let period = LeaderboardPeriod(rawValue: periodRaw),
              let periodKey = record[Field.periodKey] as? String,
              let nickname = record[Field.nickname] as? String,
              let scoreNumber = record[Field.score] as? NSNumber else {
            return nil
        }
        let updatedAt = (record[Field.updatedAt] as? Date)
            ?? (record[Field.updatedAt] as? NSDate).map { $0 as Date }
            ?? record.modificationDate
            ?? Date(timeIntervalSince1970: 0)
        let userHash = userHash(from: record)
        return LeaderboardScore(
            id: record.recordID.recordName,
            userHash: userHash,
            metric: metric,
            period: period,
            periodKey: periodKey,
            score: scoreNumber.int64Value,
            rank: rank,
            nickname: profile?.nickname ?? nickname,
            avatarSeed: profile?.avatarSeed,
            historyStartMonthKey: profile?.historyStartMonthKey,
            favoriteModels: profile?.favoriteModels,
            recentStatusID: profile?.recentStatusID,
            recentStatusUpdatedAt: profile?.recentStatusUpdatedAt,
            updatedAt: updatedAt
        )
    }

    static func historyPoint(from record: CKRecord,
                             metric: LeaderboardMetric,
                             window: LeaderboardPeriodWindow) -> LeaderboardScoreHistoryPoint? {
        guard let score = int64Value(record[Field.score]) else { return nil }
        let updatedAt = dateValue(record[Field.updatedAt])
            ?? record.modificationDate
        return LeaderboardScoreHistoryPoint(
            metric: metric,
            period: window.period,
            window: window,
            score: score,
            updatedAt: updatedAt
        )
    }

    static func int64Value(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    static func intValue(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    static func dateValue(_ value: Any?) -> Date? {
        (value as? Date)
            ?? (value as? NSDate).map { $0 as Date }
    }

    private static func encodeFavoriteModels(_ favoriteModels: [LeaderboardFavoriteModel]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(favoriteModels) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeFavoriteModels(from record: CKRecord) -> [LeaderboardFavoriteModel]? {
        guard let raw = record[Field.favoriteModels] as? String,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([LeaderboardFavoriteModel].self, from: data) else {
            return nil
        }
        return decoded
    }
}

struct CloudKitLeaderboardClient: LeaderboardCloudServicing {
    private let containerIdentifier: String
    private let entitlementChecker: @Sendable (String) -> Bool

    init(containerIdentifier: String = CloudKitLeaderboardConfig.containerIdentifier,
         entitlementChecker: @escaping @Sendable (String) -> Bool = CloudKitRuntimeEntitlements.hasCloudKitAccess) {
        self.containerIdentifier = containerIdentifier
        self.entitlementChecker = entitlementChecker
    }

    func accountState() async -> LeaderboardCloudAccountState {
        guard entitlementChecker(containerIdentifier) else {
            return .unavailable(Self.missingEntitlementMessage)
        }
        do {
            let status = try await container.accountStatus()
            return Self.state(from: status)
        } catch {
            return .unavailable(Self.shortCloudKitMessage(error))
        }
    }

    func currentUserHash() async throws -> String {
        try await availableUserHash()
    }

    func saveProfile(_ profile: LeaderboardProfileDraft) async throws -> LeaderboardProfile {
        let userHash = try await availableUserHash()
        let remoteProfile = try await fetchProfileRecord(userHash: userHash)
            .flatMap(CloudKitLeaderboardRecordMapper.profile(from:))
        let mergedProfile = LeaderboardProfileMergePolicy.merge(local: profile, remote: remoteProfile).draft
        let record = CloudKitLeaderboardRecordMapper.profileRecord(userHash: userHash, profile: mergedProfile)
        let result = try await publicDatabase.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .allKeys,
            atomically: true
        )
        let failures = result.saveResults.compactMap { _, value -> String? in
            if case .failure(let error) = value {
                return Self.shortCloudKitMessage(error)
            }
            return nil
        }
        if let first = failures.first {
            throw LeaderboardCloudError.partialFailure(first)
        }
        return Self.profile(userHash: userHash, draft: mergedProfile)
    }

    func fetchProfile(userHash: String) async throws -> LeaderboardProfile? {
        try ensureCloudKitEntitlement()
        return try await fetchProfileRecord(userHash: userHash)
            .flatMap(CloudKitLeaderboardRecordMapper.profile(from:))
    }

    func submit(_ submissions: [LeaderboardSubmission],
                historySubmissions: [LeaderboardHistorySubmission],
                profile: LeaderboardProfileDraft) async throws -> LeaderboardProfile {
        guard !submissions.isEmpty || !historySubmissions.isEmpty else { return try await saveProfile(profile) }
        let userHash = try await availableUserHash()
        let remoteProfile = try await fetchProfileRecord(userHash: userHash)
            .flatMap(CloudKitLeaderboardRecordMapper.profile(from:))
        let mergedProfile = LeaderboardProfileMergePolicy.merge(local: profile, remote: remoteProfile).draft
        let mergedSubmissions = try await resolveScoreConflicts(submissions, userHash: userHash)
        let mergedHistorySubmissions = try await resolveHistoryConflicts(historySubmissions, userHash: userHash)
        let profileRecord = CloudKitLeaderboardRecordMapper.profileRecord(userHash: userHash, profile: mergedProfile)
        let records = [profileRecord]
            + mergedSubmissions.map { CloudKitLeaderboardRecordMapper.record(from: $0, userHash: userHash) }
            + mergedHistorySubmissions.map { CloudKitLeaderboardRecordMapper.historyRecord(from: $0, userHash: userHash) }
        let result = try await publicDatabase.modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: .allKeys,
            atomically: false
        )
        let failures = result.saveResults.compactMap { _, value -> String? in
            if case .failure(let error) = value {
                return Self.shortCloudKitMessage(error)
            }
            return nil
        }
        if let first = failures.first {
            throw LeaderboardCloudError.partialFailure(first)
        }
        return Self.profile(userHash: userHash, draft: mergedProfile)
    }

    func fetchScores(metric: LeaderboardMetric,
                     period: LeaderboardPeriod,
                     periodKey: String,
                     limit: Int = 100) async throws -> [LeaderboardScore] {
        try ensureCloudKitEntitlement()
        let predicate = NSPredicate(
            format: "%K == %@ AND %K == %@ AND %K == %@ AND %K == %@",
            CloudKitLeaderboardRecordMapper.Field.metric, metric.rawValue,
            CloudKitLeaderboardRecordMapper.Field.period, period.rawValue,
            CloudKitLeaderboardRecordMapper.Field.periodKey, periodKey,
            CloudKitLeaderboardRecordMapper.Field.providerScope, CloudKitLeaderboardConfig.providerScope
        )
        let query = CKQuery(recordType: CloudKitLeaderboardConfig.recordType, predicate: predicate)
        query.sortDescriptors = [
            NSSortDescriptor(key: CloudKitLeaderboardRecordMapper.Field.score, ascending: false),
            NSSortDescriptor(key: CloudKitLeaderboardRecordMapper.Field.updatedAt, ascending: true),
        ]
        do {
            let result = try await publicDatabase.records(
                matching: query,
                desiredKeys: CloudKitLeaderboardRecordMapper.desiredKeys,
                resultsLimit: limit
            )
            let records = result.matchResults
                .compactMap { try? $0.1.get() }
            let profiles = await profiles(for: records)
            return CloudKitLeaderboardRecordMapper.rankedScores(from: records, profiles: profiles)
        } catch {
            throw LeaderboardCloudError.cloudKit(Self.shortCloudKitMessage(error))
        }
    }

    func fetchScoreHistory(userHash: String,
                           metric: LeaderboardMetric,
                           period: LeaderboardPeriod,
                           windows: [LeaderboardPeriodWindow]) async throws -> [LeaderboardScoreHistoryPoint] {
        guard !windows.isEmpty else { return [] }
        try ensureCloudKitEntitlement()
        let ids = windows.map { window in
            CKRecord.ID(recordName: CloudKitLeaderboardRecordMapper.historyRecordName(
                userHash: userHash,
                metric: metric,
                bucketPeriod: window.period,
                periodKey: window.periodKey
            ))
        }
        do {
            let results = try await publicDatabase.records(
                for: ids,
                desiredKeys: CloudKitLeaderboardRecordMapper.desiredKeys
            )
            return zip(windows, ids).map { window, id in
                guard let result = results[id],
                      case .success(let record) = result,
                      let point = CloudKitLeaderboardRecordMapper.historyPoint(from: record, metric: metric, window: window) else {
                    return LeaderboardScoreHistoryPoint(
                        metric: metric,
                        period: window.period,
                        window: window,
                        score: 0,
                        updatedAt: nil
                    )
                }
                return point
            }
        } catch {
            throw LeaderboardCloudError.cloudKit(Self.shortCloudKitMessage(error))
        }
    }

    private var container: CKContainer {
        CKContainer(identifier: containerIdentifier)
    }

    private var publicDatabase: CKDatabase {
        container.publicCloudDatabase
    }

    private func fetchProfileRecord(userHash: String) async throws -> CKRecord? {
        let recordID = CKRecord.ID(recordName: CloudKitLeaderboardRecordMapper.profileRecordName(userHash: userHash))
        do {
            let results = try await publicDatabase.records(
                for: [recordID],
                desiredKeys: CloudKitLeaderboardRecordMapper.profileDesiredKeys
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

    private func resolveScoreConflicts(_ submissions: [LeaderboardSubmission],
                                       userHash: String) async throws -> [LeaderboardSubmission] {
        let pairs = submissions.map { submission in
            (
                submission,
                CKRecord.ID(recordName: CloudKitLeaderboardRecordMapper.recordName(
                    userHash: userHash,
                    metric: submission.metric,
                    period: submission.period,
                    periodKey: submission.periodKey
                ))
            )
        }
        let records = try await existingRecords(
            for: pairs.map { $0.1 },
            desiredKeys: [
                CloudKitLeaderboardRecordMapper.Field.score,
                CloudKitLeaderboardRecordMapper.Field.calculationVersion,
                CloudKitLeaderboardRecordMapper.Field.updatedAt,
            ]
        )
        return pairs.map { submission, recordID in
            let record = records[recordID]
            return LeaderboardSubmissionMergePolicy.merge(
                local: submission,
                remoteScore: record.flatMap { CloudKitLeaderboardRecordMapper.int64Value($0[CloudKitLeaderboardRecordMapper.Field.score]) },
                remoteCalculationVersion: record.flatMap { CloudKitLeaderboardRecordMapper.intValue($0[CloudKitLeaderboardRecordMapper.Field.calculationVersion]) },
                remoteUpdatedAt: record.flatMap { CloudKitLeaderboardRecordMapper.dateValue($0[CloudKitLeaderboardRecordMapper.Field.updatedAt]) }
            )
        }
    }

    private func resolveHistoryConflicts(_ submissions: [LeaderboardHistorySubmission],
                                         userHash: String) async throws -> [LeaderboardHistorySubmission] {
        let pairs = submissions.map { submission in
            (
                submission,
                CKRecord.ID(recordName: CloudKitLeaderboardRecordMapper.historyRecordName(
                    userHash: userHash,
                    metric: submission.metric,
                    bucketPeriod: submission.bucketPeriod,
                    periodKey: submission.periodKey
                ))
            )
        }
        let records = try await existingRecords(
            for: pairs.map { $0.1 },
            desiredKeys: [
                CloudKitLeaderboardRecordMapper.Field.score,
                CloudKitLeaderboardRecordMapper.Field.calculationVersion,
                CloudKitLeaderboardRecordMapper.Field.updatedAt,
            ]
        )
        return pairs.map { submission, recordID in
            let record = records[recordID]
            return LeaderboardSubmissionMergePolicy.merge(
                local: submission,
                remoteScore: record.flatMap { CloudKitLeaderboardRecordMapper.int64Value($0[CloudKitLeaderboardRecordMapper.Field.score]) },
                remoteCalculationVersion: record.flatMap { CloudKitLeaderboardRecordMapper.intValue($0[CloudKitLeaderboardRecordMapper.Field.calculationVersion]) },
                remoteUpdatedAt: record.flatMap { CloudKitLeaderboardRecordMapper.dateValue($0[CloudKitLeaderboardRecordMapper.Field.updatedAt]) }
            )
        }
    }

    private func existingRecords(for recordIDs: [CKRecord.ID],
                                 desiredKeys: [String]) async throws -> [CKRecord.ID: CKRecord] {
        guard !recordIDs.isEmpty else { return [:] }
        do {
            let results = try await publicDatabase.records(
                for: recordIDs,
                desiredKeys: desiredKeys
            )
            return try results.reduce(into: [:]) { partial, entry in
                switch entry.value {
                case .success(let record):
                    partial[entry.key] = record
                case .failure(let error):
                    if !Self.isUnknownItem(error) {
                        throw LeaderboardCloudError.cloudKit(Self.shortCloudKitMessage(error))
                    }
                }
            }
        } catch let error as LeaderboardCloudError {
            throw error
        } catch {
            throw LeaderboardCloudError.cloudKit(Self.shortCloudKitMessage(error))
        }
    }

    private func profiles(for records: [CKRecord]) async -> [String: LeaderboardProfile] {
        let userHashes = records
            .compactMap(CloudKitLeaderboardRecordMapper.userHash(from:))
            .uniqued()
        guard !userHashes.isEmpty else { return [:] }

        let profileIDs = userHashes.map {
            CKRecord.ID(recordName: CloudKitLeaderboardRecordMapper.profileRecordName(userHash: $0))
        }
        do {
            let results = try await publicDatabase.records(
                for: profileIDs,
                desiredKeys: CloudKitLeaderboardRecordMapper.profileDesiredKeys
            )
            return results.values.reduce(into: [:]) { partial, result in
                guard case .success(let record) = result,
                      let profile = CloudKitLeaderboardRecordMapper.profile(from: record) else {
                    return
                }
                partial[profile.userHash] = profile
            }
        } catch {
            Log.network.error("Leaderboard profile lookup failed: \(Self.shortCloudKitMessage(error), privacy: .public)")
            return [:]
        }
    }

    private func ensureCloudKitEntitlement() throws {
        guard entitlementChecker(containerIdentifier) else {
            throw LeaderboardCloudError.missingEntitlement(Self.missingEntitlementMessage)
        }
    }

    private func availableUserHash() async throws -> String {
        try ensureCloudKitEntitlement()
        let status = try await container.accountStatus()
        switch Self.state(from: status) {
        case .available:
            break
        case .noAccount:
            throw LeaderboardCloudError.noAccount
        case .restricted:
            throw LeaderboardCloudError.restricted
        case .unknown, .unavailable:
            throw LeaderboardCloudError.cloudKit("iCloud is not available right now.")
        }

        do {
            let userRecordName = try await container.userRecordID().recordName
            return CloudKitLeaderboardRecordMapper.userHash(forUserRecordName: userRecordName)
        } catch {
            throw LeaderboardCloudError.userRecordUnavailable
        }
    }

    private static let missingEntitlementMessage = "CloudKit entitlement is missing or incomplete in this build."

    private static func profile(userHash: String, draft: LeaderboardProfileDraft) -> LeaderboardProfile {
        LeaderboardProfile(
            userHash: userHash,
            nickname: draft.nickname,
            avatarSeed: draft.avatarSeed,
            historyStartMonthKey: draft.historyStartMonthKey,
            favoriteModels: draft.favoriteModels,
            recentStatusID: draft.recentStatusID,
            recentStatusUpdatedAt: draft.recentStatusUpdatedAt,
            updatedAt: draft.updatedAt
        )
    }

    private static func isUnknownItem(_ error: Error) -> Bool {
        (error as? CKError)?.code == .unknownItem
    }

    private static func state(from status: CKAccountStatus) -> LeaderboardCloudAccountState {
        switch status {
        case .available:
            return .available
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .couldNotDetermine:
            return .unavailable("Could not determine iCloud status.")
        case .temporarilyUnavailable:
            return .unavailable("iCloud is temporarily unavailable.")
        @unknown default:
            return .unavailable("Unsupported iCloud account state.")
        }
    }

    private static func shortCloudKitMessage(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated:
                return LeaderboardCloudError.noAccount.description
            case .networkUnavailable, .networkFailure:
                return "Network unavailable."
            case .serviceUnavailable, .requestRateLimited:
                return "CloudKit is temporarily unavailable."
            case .permissionFailure:
                return "CloudKit permission denied. Check the app's iCloud container."
            case .partialFailure:
                return "Some leaderboard records failed to save."
            case .serverRejectedRequest, .invalidArguments:
                let base = "CloudKit rejected the leaderboard request. Check schema, indexes, and write permissions."
                guard let detail = cloudKitDetail(ck) else { return base }
                return "\(base) \(detail)"
            default:
                return ck.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private static func cloudKitDetail(_ error: CKError) -> String? {
        let nsError = error as NSError
        let details = [
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion,
            nsError.userInfo[NSLocalizedDescriptionKey] as? String,
            nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
            nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String,
            nsError.userInfo["CKErrorDescription"] as? String,
            nsError.userInfo["ServerErrorDescription"] as? String,
            (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.localizedDescription,
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != error.localizedDescription }
            .uniqued()

        guard !details.isEmpty else { return nil }
        return details.joined(separator: " ")
    }
}
