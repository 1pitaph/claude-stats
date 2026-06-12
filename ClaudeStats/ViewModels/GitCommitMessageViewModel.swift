import Foundation
import Observation

@MainActor
@Observable
final class GitCommitMessageViewModel {
    private(set) var state: GitCommitMessageLoadState = .idle
    private(set) var commitState: GitCommitActionState = .idle

    @ObservationIgnored private let service: GitCommitMessageService
    @ObservationIgnored private let commitService: GitCommitCommandService

    init(
        service: GitCommitMessageService = GitCommitMessageService(),
        commitService: GitCommitCommandService = GitCommitCommandService()
    ) {
        self.service = service
        self.commitService = commitService
    }

    func reset() {
        state = .idle
        commitState = .idle
    }

    func fail(_ message: String) {
        state = .failed(message)
        commitState = .idle
    }

    func loadCached(
        repo: GitRepo,
        target: GitCommitMessageTarget,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        algorithmPreference: GitCommitMessageAlgorithmPreference = .automatic
    ) async {
        if case .loading = state { return }
        guard let result = await service.cachedCommitMessage(
            repo: repo,
            target: target,
            endpoint: endpoint,
            language: language,
            algorithmPreference: algorithmPreference
        ) else {
            if case .loaded = state {
                state = .idle
            }
            return
        }
        commitState = .idle
        state = .loaded(result)
    }

    func generate(
        repo: GitRepo,
        target: GitCommitMessageTarget,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        algorithmPreference: GitCommitMessageAlgorithmPreference = .automatic,
        forceRefresh: Bool = false
    ) async {
        commitState = .idle
        state = .loading
        do {
            let result = try await service.generateCommitMessage(
                repo: repo,
                target: target,
                endpoint: endpoint,
                language: language,
                algorithmPreference: algorithmPreference,
                forceRefresh: forceRefresh
            )
            state = .loaded(result)
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func commitAllWorkingTreeChanges(
        repo: GitRepo,
        target: GitCommitMessageTarget,
        result: GitCommitMessageResult
    ) async -> GitWorkingTreeCommitResult? {
        guard target == .workingTree else {
            commitState = .failed("Only working tree changes can be committed from this panel.")
            return nil
        }
        if case .committing = commitState { return nil }
        commitState = .committing
        do {
            let outcome = try await commitService.commitAllWorkingTreeChanges(repo: repo, result: result)
            if let pushTarget = outcome.pushTarget {
                commitState = .readyToPush(GitPendingPushAction(shortHash: outcome.shortHash, target: pushTarget))
            } else {
                commitState = .committed(shortHash: outcome.shortHash)
            }
            return outcome
        } catch is CancellationError {
            commitState = .idle
            return nil
        } catch {
            commitState = .failed(error.localizedDescription)
            return nil
        }
    }

    func pushCommittedChanges(repo: GitRepo) async -> Bool {
        let pendingPush: GitPendingPushAction
        switch commitState {
        case .readyToPush(let pending), .pushFailed(_, let pending):
            pendingPush = pending
        default:
            return false
        }

        commitState = .pushing(pendingPush)
        do {
            _ = try await commitService.pushCommittedChanges(repo: repo, target: pendingPush.target)
            commitState = .pushed(shortHash: pendingPush.shortHash)
            return true
        } catch is CancellationError {
            commitState = .readyToPush(pendingPush)
            return false
        } catch {
            commitState = .pushFailed(error.localizedDescription, pendingPush: pendingPush)
            return false
        }
    }
}
