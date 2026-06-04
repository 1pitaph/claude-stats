import Foundation
import Observation

@MainActor
@Observable
final class GitCommitMessageViewModel {
    private(set) var state: GitCommitMessageLoadState = .idle

    @ObservationIgnored private let service: GitCommitMessageService

    init(service: GitCommitMessageService = GitCommitMessageService()) {
        self.service = service
    }

    func reset() {
        state = .idle
    }

    func fail(_ message: String) {
        state = .failed(message)
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
}
