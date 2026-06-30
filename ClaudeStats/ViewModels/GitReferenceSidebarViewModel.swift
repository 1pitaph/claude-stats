import Foundation
import Observation

@MainActor
@Observable
final class GitReferenceSidebarViewModel {
    private(set) var snapshot: GitReferenceSnapshot = .empty
    private(set) var isLoading = false
    private(set) var isOperationRunning = false
    private(set) var lastFailureNotice: GitOperationFailureNotice?
    private(set) var currentRepoID: String?

    var selection: GitReferenceSelection = .none
    var expandedIDs: Set<String> = GitReferenceTreeBuilder.defaultExpandedIDs
    var reflogLimit = 200

    @ObservationIgnored private let referenceService = GitReferenceService()
    @ObservationIgnored private let operationService = GitReferenceOperationService()
    @ObservationIgnored private var loadRequestID: UInt64 = 0

    var rows: [GitReferenceTreeRow] {
        GitReferenceTreeBuilder.rows(
            snapshot: snapshot,
            selection: selection,
            expandedIDs: expandedIDs
        )
    }

    func load(repo: GitRepo, force: Bool = false) async {
        if currentRepoID != repo.id {
            reset(for: repo)
        }
        guard force || snapshot == .empty else { return }

        loadRequestID &+= 1
        let requestID = loadRequestID
        isLoading = true
        defer {
            if loadRequestID == requestID {
                isLoading = false
            }
        }

        let requestedRepoID = repo.id
        let limit = reflogLimit
        let service = referenceService
        let loaded = await Task.detached(priority: .userInitiated) {
            service.snapshot(for: repo, reflogLimit: limit)
        }.value

        guard loadRequestID == requestID, currentRepoID == requestedRepoID else { return }
        snapshot = loaded
        pruneSelectionIfNeeded()
    }

    func reload(repo: GitRepo) async {
        await load(repo: repo, force: true)
    }

    func loadMoreReflogs(repo: GitRepo) async {
        reflogLimit += 200
        await load(repo: repo, force: true)
    }

    func toggle(_ row: GitReferenceTreeRow) {
        guard row.isExpandable else { return }
        if expandedIDs.contains(row.id) {
            expandedIDs.remove(row.id)
        } else {
            expandedIDs.insert(row.id)
        }
    }

    func select(_ row: GitReferenceTreeRow) {
        if let fullName = row.referenceFullName {
            selection = .reference(fullName)
        } else if let selector = row.reflogSelector {
            selection = .reflog(selector)
        }
    }

    func clearFailureNotice() {
        lastFailureNotice = nil
    }

    func checkoutLocalBranch(repo: GitRepo, name: String) async -> Bool {
        await runOperation(repo: repo, title: "Checkout failed") {
            try await operationService.checkoutLocalBranch(repo: repo, name: name)
        }
    }

    func checkoutDetached(repo: GitRepo, target: String) async -> Bool {
        await runOperation(repo: repo, title: "Checkout failed") {
            try await operationService.checkoutDetached(repo: repo, target: target)
        }
    }

    func createBranch(repo: GitRepo, name: String, startPoint: String) async -> Bool {
        await runOperation(repo: repo, title: "Create branch failed") {
            try await operationService.createBranch(repo: repo, name: name, startPoint: startPoint)
        }
    }

    func createTrackingBranch(repo: GitRepo, localName: String, remoteShortName: String) async -> Bool {
        await runOperation(repo: repo, title: "Create branch failed") {
            try await operationService.createTrackingBranch(
                repo: repo,
                localName: localName,
                remoteShortName: remoteShortName
            )
        }
    }

    func renameBranch(repo: GitRepo, oldName: String, newName: String) async -> Bool {
        await runOperation(repo: repo, title: "Rename branch failed") {
            try await operationService.renameBranch(repo: repo, oldName: oldName, newName: newName)
        }
    }

    func deleteBranch(repo: GitRepo, name: String, force: Bool) async -> Bool {
        await runOperation(repo: repo, title: "Delete branch failed") {
            try await operationService.deleteBranch(repo: repo, name: name, force: force)
        }
    }

    func createTag(repo: GitRepo, name: String, target: String) async -> Bool {
        await runOperation(repo: repo, title: "Create tag failed") {
            try await operationService.createTag(repo: repo, name: name, target: target)
        }
    }

    func deleteTag(repo: GitRepo, name: String) async -> Bool {
        await runOperation(repo: repo, title: "Delete tag failed") {
            try await operationService.deleteTag(repo: repo, name: name)
        }
    }

    func fetch(repo: GitRepo, remoteName: String) async -> Bool {
        await runOperation(repo: repo, title: "Fetch failed") {
            try await operationService.fetch(repo: repo, remoteName: remoteName)
        }
    }

    func prune(repo: GitRepo, remoteName: String) async -> Bool {
        await runOperation(repo: repo, title: "Prune failed") {
            try await operationService.prune(repo: repo, remoteName: remoteName)
        }
    }

    private func runOperation(
        repo: GitRepo,
        title: String,
        operation: () async throws -> Void
    ) async -> Bool {
        isOperationRunning = true
        lastFailureNotice = nil
        defer { isOperationRunning = false }

        do {
            try await operation()
            await reload(repo: repo)
            return true
        } catch is CancellationError {
            return false
        } catch {
            lastFailureNotice = GitOperationLog.referenceFailureNotice(
                from: error,
                title: title,
                fallbackMessage: "\(title). View Logs for details."
            )
            return false
        }
    }

    private func reset(for repo: GitRepo) {
        loadRequestID &+= 1
        currentRepoID = repo.id
        snapshot = .empty
        selection = .none
        expandedIDs = GitReferenceTreeBuilder.defaultExpandedIDs
        reflogLimit = 200
        lastFailureNotice = nil
        isLoading = false
        isOperationRunning = false
    }

    private func pruneSelectionIfNeeded() {
        switch selection {
        case .none:
            return
        case .reference(let fullName):
            if snapshot.reference(fullName: fullName) == nil {
                selection = .none
            }
        case .reflog(let selector):
            if snapshot.reflog(id: selector) == nil {
                selection = .none
            }
        }
    }
}

private extension GitOperationLog {
    static func referenceFailureNotice(
        from error: Error,
        title: String,
        fallbackMessage: String
    ) -> GitOperationFailureNotice {
        if let error = error as? GitReferenceOperationError {
            return GitOperationFailureNotice(
                title: title,
                message: error.errorDescription ?? fallbackMessage,
                logEntryID: error.logEntryID
            )
        }
        return failureNotice(from: error, title: title, fallbackMessage: fallbackMessage)
    }
}
