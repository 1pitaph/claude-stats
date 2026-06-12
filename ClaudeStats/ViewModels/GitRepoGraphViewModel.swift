import Foundation
import Observation

@MainActor
@Observable
final class GitRepoGraphViewModel {
    private(set) var graph: GitGraph?
    private(set) var layout: GraphLayout?
    private(set) var isGraphLoading = false
    private(set) var isDetailLoading = false
    private(set) var isBaseStatsLoading = false
    private(set) var isCodeOwnershipLoading = false
    private(set) var commitDetail: CommitDetail?
    private(set) var repoBaseStats: GitRepoInspectorBaseStats?
    private(set) var codeOwnershipState: GitCodeOwnershipLoadState = .idle
    private(set) var minimapData: GitGraphMinimapData?
    private(set) var isMinimapLoading = false
    private(set) var currentRepoID: String?
    private(set) var loadedLimit = 0
    private(set) var statsRefreshGeneration: UInt64 = 0

    var statsScope: GitStatsScope = .head {
        didSet {
            guard oldValue != statsScope else { return }
            invalidateBaseStatsRequest()
            invalidateCodeOwnershipRequest()
            repoBaseStats = nil
            repoBaseStatsRepoID = nil
            repoBaseStatsScope = nil
            codeOwnershipState = .idle
        }
    }
    var selectedHash: String?
    var limit = 200

    private let pageSize = 200
    @ObservationIgnored private var minimapTargetMaxBuckets = 120
    @ObservationIgnored private let repositoryService = GitRepositoryService.shared
    private let isPreview: Bool
    @ObservationIgnored private var watcher: GitRepositoryWatcher?
    @ObservationIgnored private var graphRequestID: UInt64 = 0
    @ObservationIgnored private var detailRequestID: UInt64 = 0
    @ObservationIgnored private var baseStatsRequestID: UInt64 = 0
    @ObservationIgnored private var codeOwnershipRequestID: UInt64 = 0
    @ObservationIgnored private var minimapRequestID: UInt64 = 0
    @ObservationIgnored private var repoBaseStatsRepoID: String?
    @ObservationIgnored private var repoBaseStatsScope: GitStatsScope?
    @ObservationIgnored private var repoBaseStatsGeneration: UInt64 = 0

    init() {
        isPreview = false
    }

    #if DEBUG
    init(previewGraph: GitGraph) {
        isPreview = true
        let initialSelectedHash = previewGraph.commits.first?.hash
        graph = previewGraph
        layout = GraphLayout.build(previewGraph.commits)
        currentRepoID = previewGraph.repo.id
        loadedLimit = previewGraph.commits.count
        selectedHash = initialSelectedHash
        minimapData = GitGraphMinimapData.build(
            commits: previewGraph.commits.map {
                GitCommit(
                    hash: $0.hash,
                    date: $0.date,
                    author: $0.author,
                    authorEmail: $0.authorEmail,
                    subject: $0.subject,
                    insertions: 0,
                    deletions: 0,
                    filesChanged: 0,
                    repoID: previewGraph.repo.id
                )
            },
            refsByHash: Dictionary(uniqueKeysWithValues: previewGraph.commits.map { ($0.hash, $0.refs) }),
            workingTree: previewGraph.workingTree,
            selectedHash: initialSelectedHash,
            currentBranch: previewGraph.repo.currentBranch
        )
        if let commit = previewGraph.commits.first {
            commitDetail = .preview(
                from: commit,
                files: GitGraph.previewFileChanges()[commit.hash] ?? []
            )
        }
        repoBaseStats = .preview
        codeOwnershipState = .loaded(GitRepoCodeOwnershipStats.preview.codeContributors)
    }
    #endif

    var isStatsLoading: Bool {
        isBaseStatsLoading || isCodeOwnershipLoading
    }

    var selectedCommit: GraphCommit? {
        guard let selectedHash else { return nil }
        return graph?.commits.first { $0.hash == selectedHash }
    }

    var graphLoadID: String {
        "\(currentRepoID ?? "")|\(limit)"
    }

    var detailLoadID: String {
        "\(currentRepoID ?? "")|\(selectedHash ?? "")"
    }

    @discardableResult
    func loadGraph(repo: GitRepo, forceReload: Bool = false) async -> Bool {
        if currentRepoID != repo.id {
            reset(for: repo)
        }
        if isPreview { return true }
        if !forceReload {
            if graph != nil, loadedLimit >= limit { return true }
            if graph?.truncated == false { return true }
        }

        graphRequestID &+= 1
        let requestID = graphRequestID
        isGraphLoading = true
        defer { finishGraphRequest(requestID) }

        let requestedRepoID = repo.id
        let requestedOffset = forceReload ? 0 : loadedLimit
        let requestedLimit = forceReload ? max(limit, pageSize) : max(limit - loadedLimit, pageSize)
        let page = await repositoryService.graphPage(for: repo, offset: requestedOffset, limit: requestedLimit)

        guard graphRequestID == requestID,
              currentRepoID == requestedRepoID,
              (forceReload || loadedLimit == requestedOffset) else { return false }
        guard let page else {
            if graph == nil {
                loadedLimit = 0
            }
            return false
        }
        let existing = requestedOffset == 0 ? [] : (graph?.commits ?? [])
        let existingHashes = Set(existing.map(\.hash))
        let commits = existing + page.commits.filter { !existingHashes.contains($0.hash) }
        graph = GitGraph(
            repo: page.repo,
            commits: commits,
            truncated: page.hasMore,
            workingTree: page.workingTree
        )
        layout = GraphLayout.build(commits)
        loadedLimit = requestedOffset + page.commits.count
        reconcileSelection()
        await loadMinimap(repo: repo)
        return true
    }

    func loadDetail(repo: GitRepo) async {
        guard let hash = selectedHash else {
            invalidateDetailRequest()
            commitDetail = nil
            return
        }
        if isPreview { return }

        detailRequestID &+= 1
        let requestID = detailRequestID
        isDetailLoading = true
        defer { finishDetailRequest(requestID) }

        let requestedRepoID = repo.id
        let requestedHash = hash
        let detail = await repositoryService.commitDetail(for: requestedHash, in: repo)

        guard detailRequestID == requestID,
              currentRepoID == requestedRepoID,
              selectedHash == requestedHash else { return }
        commitDetail = detail
    }

    func loadRepoStats(repo: GitRepo) async {
        if currentRepoID != repo.id {
            reset(for: repo)
        }
        if isPreview { return }

        let requestedScope = statsScope
        let requestedGeneration = statsRefreshGeneration
        let baseStats: GitRepoInspectorBaseStats
        if let existing = repoBaseStats,
           repoBaseStatsRepoID == repo.id,
           repoBaseStatsScope == requestedScope,
           repoBaseStatsGeneration == requestedGeneration {
            baseStats = existing
        } else {
            baseStatsRequestID &+= 1
            let requestID = baseStatsRequestID
            isBaseStatsLoading = true
            defer { finishBaseStatsRequest(requestID) }

            let requestedRepoID = repo.id
            let task = Task.detached(priority: .userInitiated) {
                GitRepoStatsService().baseStats(for: repo, scope: requestedScope)
            }
            let loadedBaseStats = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }

            guard baseStatsRequestID == requestID,
                  currentRepoID == requestedRepoID,
                  statsScope == requestedScope,
                  statsRefreshGeneration == requestedGeneration,
                  !Task.isCancelled else { return }
            repoBaseStats = loadedBaseStats
            repoBaseStatsRepoID = requestedRepoID
            repoBaseStatsScope = requestedScope
            repoBaseStatsGeneration = requestedGeneration
            baseStats = loadedBaseStats
        }

        guard !isCodeOwnershipLoading else { return }
        if case .loaded = codeOwnershipState { return }
        await loadCodeOwnership(repo: repo, scope: requestedScope, codeFilePaths: baseStats.code.codeFilePaths)
    }

    private func loadCodeOwnership(repo: GitRepo, scope: GitStatsScope, codeFilePaths: [String]) async {
        codeOwnershipRequestID &+= 1
        let requestID = codeOwnershipRequestID
        isCodeOwnershipLoading = true
        codeOwnershipState = .loading
        defer { finishCodeOwnershipRequest(requestID) }

        let requestedRepoID = repo.id
        let task = Task.detached(priority: .utility) {
            await GitRepoStatsService().codeOwnershipStats(for: repo, scope: scope, codeFilePaths: codeFilePaths)
        }
        let ownership = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }

        guard codeOwnershipRequestID == requestID,
              currentRepoID == requestedRepoID,
              statsScope == scope,
              !Task.isCancelled else { return }
        codeOwnershipState = .loaded(ownership.codeContributors)
    }

    func selectCommit(_ hash: String) {
        guard selectedHash != hash else { return }
        invalidateDetailRequest()
        selectedHash = hash
        updateMinimapSelection()
        commitDetail = nil
    }

    func selectWorkingTree() {
        invalidateDetailRequest()
        selectedHash = nil
        updateMinimapSelection()
        commitDetail = nil
    }

    func loadMore() {
        limit = max(limit, loadedLimit) + pageSize
    }

    func loadMinimap(repo: GitRepo) async {
        if currentRepoID != repo.id {
            reset(for: repo)
        }
        if isPreview { return }

        minimapRequestID &+= 1
        let requestID = minimapRequestID
        isMinimapLoading = true
        defer { finishMinimapRequest(requestID) }

        let requestedRepoID = repo.id
        let requestedSelectedHash = selectedHash
        let requestedLimit = max(limit, loadedLimit, 800)
        let requestedTargetMaxBuckets = minimapTargetMaxBuckets
        let data = await repositoryService.minimapData(
            for: repo,
            limit: requestedLimit,
            targetMaxBuckets: requestedTargetMaxBuckets,
            selectedHash: requestedSelectedHash
        )
        guard minimapRequestID == requestID,
              currentRepoID == requestedRepoID,
              minimapTargetMaxBuckets == requestedTargetMaxBuckets,
              selectedHash == requestedSelectedHash else { return }
        minimapData = data
    }

    func updateMinimapTargetMaxBuckets(_ targetMaxBuckets: Int, repo: GitRepo) async {
        let normalized = max(targetMaxBuckets, 1)
        guard minimapTargetMaxBuckets != normalized else { return }
        minimapTargetMaxBuckets = normalized
        await loadMinimap(repo: repo)
    }

    func selectMinimapBucket(_ bucket: GitGraphMinimapData.Bucket, repo: GitRepo) async {
        guard let hash = bucket.representativeHash else { return }
        while graph?.commits.contains(where: { $0.hash == hash }) != true,
              graph?.truncated == true {
            let previousLoadedLimit = loadedLimit
            loadMore()
            let didLoad = await loadGraph(repo: repo)
            guard didLoad, loadedLimit > previousLoadedLimit else { return }
        }
        guard graph?.commits.contains(where: { $0.hash == hash }) == true else { return }
        selectCommit(hash)
    }

    func reloadAfterRepositoryMutation(repo: GitRepo) async {
        await repositoryDidChange(repo: repo)
    }

    private func reset(for repo: GitRepo) {
        invalidateGraphRequest()
        invalidateDetailRequest()
        invalidateBaseStatsRequest()
        invalidateCodeOwnershipRequest()
        invalidateMinimapRequest()
        configureWatcher(for: repo)
        currentRepoID = repo.id
        graph = nil
        layout = nil
        commitDetail = nil
        repoBaseStats = nil
        repoBaseStatsRepoID = nil
        repoBaseStatsScope = nil
        repoBaseStatsGeneration = 0
        codeOwnershipState = .idle
        minimapData = nil
        selectedHash = nil
        loadedLimit = 0
        limit = pageSize
        minimapTargetMaxBuckets = 120
    }

    private func reconcileSelection() {
        guard let commits = graph?.commits, !commits.isEmpty else {
            invalidateDetailRequest()
            selectedHash = nil
            commitDetail = nil
            return
        }
        if let selectedHash, commits.contains(where: { $0.hash == selectedHash }) {
            return
        }
        invalidateDetailRequest()
        selectedHash = nil
        updateMinimapSelection()
        commitDetail = nil
    }

    private func updateMinimapSelection() {
        minimapData = minimapData?.selecting(hash: selectedHash)
    }

    private func configureWatcher(for repo: GitRepo) {
        watcher?.stop()
        watcher = nil
        guard !isPreview else { return }
        let watcher = GitRepositoryWatcher(repo: repo) { [weak self] in
            Task { @MainActor in
                await self?.repositoryDidChange(repo: repo)
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    private func repositoryDidChange(repo: GitRepo) async {
        guard currentRepoID == repo.id else { return }
        await repositoryService.invalidate(repo: repo)
        invalidateGraphRequest()
        invalidateMinimapRequest()
        invalidateRepoStatsForRefresh()
        loadedLimit = 0
        limit = max(limit, pageSize)
        await loadGraph(repo: repo, forceReload: true)
    }

    private func invalidateRepoStatsForRefresh() {
        invalidateBaseStatsRequest()
        invalidateCodeOwnershipRequest()
        repoBaseStats = nil
        repoBaseStatsRepoID = nil
        repoBaseStatsScope = nil
        repoBaseStatsGeneration = 0
        codeOwnershipState = .idle
        statsRefreshGeneration &+= 1
    }

    private func invalidateGraphRequest() {
        graphRequestID &+= 1
        isGraphLoading = false
    }

    private func invalidateDetailRequest() {
        detailRequestID &+= 1
        isDetailLoading = false
    }

    private func invalidateBaseStatsRequest() {
        baseStatsRequestID &+= 1
        isBaseStatsLoading = false
    }

    private func invalidateCodeOwnershipRequest() {
        codeOwnershipRequestID &+= 1
        isCodeOwnershipLoading = false
        if case .loading = codeOwnershipState {
            codeOwnershipState = .idle
        }
    }

    private func invalidateMinimapRequest() {
        minimapRequestID &+= 1
        isMinimapLoading = false
    }

    private func finishGraphRequest(_ requestID: UInt64) {
        if graphRequestID == requestID {
            isGraphLoading = false
        }
    }

    private func finishDetailRequest(_ requestID: UInt64) {
        if detailRequestID == requestID {
            isDetailLoading = false
        }
    }

    private func finishBaseStatsRequest(_ requestID: UInt64) {
        if baseStatsRequestID == requestID {
            isBaseStatsLoading = false
        }
    }

    private func finishCodeOwnershipRequest(_ requestID: UInt64) {
        if codeOwnershipRequestID == requestID {
            isCodeOwnershipLoading = false
        }
    }

    private func finishMinimapRequest(_ requestID: UInt64) {
        if minimapRequestID == requestID {
            isMinimapLoading = false
        }
    }
}

#if DEBUG
private extension GitRepoInspectorBaseStats {
    static let preview = GitRepoInspectorBaseStats(
        code: GitRepoCodeStats(
            engine: .linguist,
            scope: .head,
            warning: nil,
            totalFiles: 24,
            analyzedFiles: 19,
            skippedFiles: 5,
            totalBytes: 552_480,
            totalLines: 18_712,
            sourceLines: 15_920,
            codeFilePaths: [
                "ClaudeStats/App/ClaudeStatsApp.swift",
                "ClaudeStats/Services/GitAnalyzer.swift",
                "ClaudeStats/Views/Git/MainWindow/GitRepoWorkspaceView.swift",
                "project.yml",
                "scripts/run-debug.sh",
            ],
            languageRows: [
                .init(language: "Swift", fileCount: 14, sizeBytes: 489_600, byteShare: 0.886, totalLines: 17_313, sourceLines: 14_880),
                .init(language: "YAML", fileCount: 2, sizeBytes: 24_480, byteShare: 0.044, totalLines: 372, sourceLines: 320),
                .init(language: "Shell", fileCount: 2, sizeBytes: 17_880, byteShare: 0.032, totalLines: 360, sourceLines: 300),
                .init(language: "JSON", fileCount: 1, sizeBytes: 11_920, byteShare: 0.022, totalLines: 281, sourceLines: 260),
                .init(language: "Markdown", fileCount: 1, sizeBytes: 8_600, byteShare: 0.016, totalLines: 236, sourceLines: 160),
            ]
        ),
        contributors: [
            GitContributorStat(name: "1pitaph", email: "xzltxy@163.com", commitCount: 46, share: 46.0 / 56.0),
            GitContributorStat(name: "Codex", email: "codex@example.com", commitCount: 7, share: 7.0 / 56.0),
            GitContributorStat(name: "Ada", email: "ada@example.com", commitCount: 3, share: 3.0 / 56.0),
        ]
    )
}

private extension GitRepoCodeOwnershipStats {
    static let preview = GitRepoCodeOwnershipStats(
        codeContributors: [
            GitCodeContributionStat(name: "1pitaph", email: "xzltxy@163.com", lineCount: 15_840, share: 15_840.0 / 18_712.0),
            GitCodeContributionStat(name: "Codex", email: "codex@example.com", lineCount: 2_104, share: 2_104.0 / 18_712.0),
            GitCodeContributionStat(name: "Ada", email: "ada@example.com", lineCount: 768, share: 768.0 / 18_712.0),
        ]
    )
}
#endif
