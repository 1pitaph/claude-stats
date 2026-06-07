import ClaudeStatsCore
import ClaudeStatsSync
import Foundation
import Observation

@MainActor
@Observable
final class CloudStatsSnapshotStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case empty(String)
        case failed(String)
    }

    private let syncService: CloudStatsSyncService
    private(set) var state: LoadState = .idle
    private(set) var accountStatus: CloudStatsAccountStatus = .unknown
    private(set) var snapshot: StatsSnapshot?
    private(set) var usesSampleData = false
    private(set) var lastCheckedAt: Date?
    private(set) var lastLoadedAt: Date?
    private(set) var lastError: String?

    init(syncService: CloudStatsSyncService = CloudStatsSyncService()) {
        self.syncService = syncService
    }

    func load() async {
        state = .loading
        usesSampleData = false
        lastError = nil
        accountStatus = await syncService.accountStatus()
        lastCheckedAt = .now
        if accountStatus == .noAccount {
            snapshot = nil
            state = .empty("Sign in to iCloud on this simulator to read the private stats snapshot.")
            return
        }
        do {
            if let snapshot = try await syncService.loadLatestSnapshot() {
                self.snapshot = snapshot
                lastLoadedAt = .now
                state = .loaded
            } else {
                self.snapshot = nil
                state = .empty("Open Claude Stats Lite on your Mac and let it sync a snapshot to iCloud.")
            }
        } catch CloudStatsSyncError.noData {
            self.snapshot = nil
            state = .empty("Open Claude Stats Lite on your Mac and let it sync a snapshot to iCloud.")
        } catch let error as CloudStatsSyncError {
            self.snapshot = nil
            lastError = error.description
            state = .failed(error.description)
        } catch {
            self.snapshot = nil
            lastError = error.localizedDescription
            state = .failed(error.localizedDescription)
        }
    }

    #if CLAUDE_STATS_DEV_TOOLS
    func loadSampleData() {
        snapshot = DebugSampleStatsSnapshot.make()
        accountStatus = .available
        usesSampleData = true
        lastCheckedAt = .now
        lastLoadedAt = .now
        lastError = nil
        state = .loaded
    }
    #endif
}
