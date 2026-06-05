import ClaudeStatsCore
import ClaudeStatsSync
import Foundation
import Testing
@testable import ClaudeStats

@MainActor
@Suite("Cloud stats snapshot sync")
struct CloudStatsSnapshotSyncTests {
    @Test("publishes a stats snapshot when CloudKit entitlement is available")
    func publishesSnapshotWithEntitlement() async throws {
        let client = MockCloudStatsRemoteClient(accountStatus: .available)
        let env = makeEnvironment(client: client, hasEntitlement: true)

        await env.publishCloudStatsSnapshotNow()

        let snapshot = try await client.savedSnapshot()
        #expect(snapshot?.schemaVersion == StatsSnapshotSchema.currentVersion)
        #expect(env.cloudStatsSyncState.phase == .published)
        #expect(env.cloudStatsSyncState.entitlementAvailable)
        #expect(env.cloudStatsSyncState.accountStatus == .available)
        #expect(env.cloudStatsSyncState.lastPublishedAt != nil)
        #expect(env.cloudStatsSyncState.lastError == nil)
    }

    @Test("does not publish when CloudKit entitlement is missing")
    func skipsSnapshotWithoutEntitlement() async {
        let client = MockCloudStatsRemoteClient(accountStatus: .available)
        let env = makeEnvironment(client: client, hasEntitlement: false)

        await env.publishCloudStatsSnapshotNow()

        let saveCount = await client.saveCount()
        #expect(saveCount == 0)
        #expect(env.cloudStatsSyncState.phase == .missingEntitlement)
        #expect(!env.cloudStatsSyncState.entitlementAvailable)
    }

    @Test("explains missing production CloudKit schema")
    func explainsMissingProductionSchema() async {
        let rawMessage = "Error saving record <CKRecordID: 0x1; recordName=stats_snapshot_latest_v1, zoneID=_defaultZone:__defaultOwner__> to server: Cannot create new type StatsSnapshotV1 in production schema"

        let message = CloudStatsCloudKitClient.friendlyCloudKitMessage(rawMessage)

        #expect(message == CloudStatsCloudKitClient.productionSchemaMissingMessage)
    }

    @Test("surfaces missing production schema during publish")
    func surfacesMissingProductionSchemaDuringPublish() async {
        let client = MockCloudStatsRemoteClient(
            accountStatus: .available,
            saveErrorMessage: CloudStatsCloudKitClient.productionSchemaMissingMessage
        )
        let env = makeEnvironment(client: client, hasEntitlement: true)

        await env.publishCloudStatsSnapshotNow()

        #expect(env.cloudStatsSyncState.phase == .failed)
        #expect(env.cloudStatsSyncState.lastError == CloudStatsCloudKitClient.productionSchemaMissingMessage)
    }

    private func makeEnvironment(
        client: MockCloudStatsRemoteClient,
        hasEntitlement: Bool
    ) -> AppEnvironment {
        let pricing = TestPricing.table
        let registry = ProviderRegistry(pricing: pricing)
        let store = SessionStore(registry: registry, pricing: pricing)
        let suiteName = "com.claudestats.tests.cloud-stats-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return AppEnvironment(
            pricing: pricing,
            preferences: Preferences(defaults: defaults),
            providerRegistry: registry,
            store: store,
            cloudStatsSync: CloudStatsSyncService(client: client),
            cloudStatsEntitlementChecker: { _ in hasEntitlement }
        )
    }
}

private actor MockCloudStatsRemoteClient: CloudStatsRemoteClient {
    private var data: Data?
    private var metadata: CloudStatsRemoteMetadata?
    private var saves = 0
    private let status: CloudStatsAccountStatus
    private let saveErrorMessage: String?

    init(accountStatus: CloudStatsAccountStatus, saveErrorMessage: String? = nil) {
        self.status = accountStatus
        self.saveErrorMessage = saveErrorMessage
    }

    func saveLatestSnapshotData(_ data: Data, metadata: CloudStatsRemoteMetadata) async throws {
        if let saveErrorMessage {
            throw CloudStatsSyncError.cloudKit(saveErrorMessage)
        }
        self.data = data
        self.metadata = metadata
        saves += 1
    }

    func fetchLatestSnapshotData() async throws -> Data? {
        data
    }

    func accountStatus() async -> CloudStatsAccountStatus {
        status
    }

    func savedSnapshot() throws -> StatsSnapshot? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StatsSnapshot.self, from: data)
    }

    func savedMetadata() -> CloudStatsRemoteMetadata? {
        metadata
    }

    func saveCount() -> Int {
        saves
    }
}
