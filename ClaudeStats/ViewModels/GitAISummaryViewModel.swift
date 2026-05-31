import Foundation
import Observation

@MainActor
@Observable
final class GitAISummaryViewModel {
    private(set) var state: GitSummaryLoadState = .idle

    @ObservationIgnored private let service: GitSummaryService

    init(service: GitSummaryService = GitSummaryService()) {
        self.service = service
    }

    func reset() {
        state = .idle
    }

    func fail(_ message: String) {
        state = .failed(message)
    }

    func generate(
        repo: GitRepo,
        target: GitSummaryTarget,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        forceRefresh: Bool = false
    ) async {
        state = .loading
        do {
            let result = try await service.summarize(
                repo: repo,
                target: target,
                endpoint: endpoint,
                language: language,
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
