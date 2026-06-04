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

    init(syncService: CloudStatsSyncService = CloudStatsSyncService()) {
        self.syncService = syncService
    }

    func load() async {
        state = .loading
        accountStatus = await syncService.accountStatus()
        if accountStatus == .noAccount {
            snapshot = nil
            state = .empty("Sign in to iCloud on this simulator to read the private stats snapshot.")
            return
        }
        do {
            if let snapshot = try await syncService.loadLatestSnapshot() {
                self.snapshot = snapshot
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
            state = .failed(error.description)
        } catch {
            self.snapshot = nil
            state = .failed(error.localizedDescription)
        }
    }
}
