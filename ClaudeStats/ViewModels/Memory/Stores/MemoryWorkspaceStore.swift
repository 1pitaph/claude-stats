import AppKit
import Foundation
import Observation

enum MemoryCaptureMode: String, CaseIterable, Identifiable, Sendable {
    case balanced
    case idleOnly
    case eager

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .idleOnly: "Idle Only"
        case .eager: "Eager"
        }
    }

    var backgroundDrainLimit: Int {
        switch self {
        case .balanced: 2
        case .idleOnly: 0
        case .eager: 8
        }
    }

    var allowsAutomaticDrain: Bool {
        backgroundDrainLimit > 0
    }
}

@MainActor
@Observable
final class MemoryWorkspaceStore {
    private static let captureModeDefaultsKey = "memory.captureMode"

    var section: MemoryWorkspaceSection = .search
    var selectedProjectID: String?
    var captureMode: MemoryCaptureMode {
        didSet {
            defaults.set(captureMode.rawValue, forKey: Self.captureModeDefaultsKey)
        }
    }

    let search: MemorySearchStore
    let library: MemoryLibraryStore
    let graph: MemoryGraphStore
    let review: MemoryReviewStore
    let settings: MemorySettingsStore

    private(set) var isLoading = false
    private(set) var isBackgroundCapturing = false
    private(set) var codeLastSyncSummary: String?
    private(set) var codeLastBackgroundCaptureResult: CodeMemoryProjectionDrainResponse?
    private(set) var syncError: String?

    @ObservationIgnored private let codeBackend: any CodeMemoryBackend
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hasLoaded = false

    init(
        codeBackend: any CodeMemoryBackend = CodeMemoryHTTPClient(),
        codeOutbox: CodeMemoryEventOutbox = CodeMemoryEventOutbox(),
        defaults: UserDefaults = .standard,
        projectSortMetadataResolver: any MemoryProjectSortMetadataResolving = MemoryProjectSortMetadataResolver()
    ) {
        self.codeBackend = codeBackend
        self.defaults = defaults
        self.captureMode = MemoryCaptureMode(rawValue: defaults.string(forKey: Self.captureModeDefaultsKey) ?? "") ?? .balanced
        self.search = MemorySearchStore(backend: codeBackend)
        self.library = MemoryLibraryStore(
            backend: codeBackend,
            defaults: defaults,
            projectSortMetadataResolver: projectSortMetadataResolver
        )
        self.graph = MemoryGraphStore(backend: codeBackend)
        self.review = MemoryReviewStore(backend: codeBackend)
        self.settings = MemorySettingsStore(backend: codeBackend, outbox: codeOutbox, defaults: defaults)
    }

    var codeHealth: CodeMemoryHealth? { settings.health }
    var codeProjects: [CodeMemoryProject] { library.projects }
    var sortedCodeProjects: [CodeMemoryProject] { library.sortedProjects }
    var codeModules: [CodeMemoryModule] { library.modules }
    var codeMemories: [CodeMemoryMemory] { library.memories }
    var codeSearchResults: [CodeMemorySearchResult] { search.memoryResults }
    var codeGraphResults: [CodeMemoryGraphFact] { search.graphResults }
    var codeSourceResults: [CodeMemoryEpisode] { search.sourceResults }
    var codeLastTraceID: String? { search.lastTraceID }
    var codeContextPack: CodeMemoryContextPack? { search.contextPack }
    var codeProposals: [CodeMemoryMemory] { review.proposals }
    var codeEvents: [CodeMemoryEvent] { search.events }
    var codeTrace: CodeMemoryRunTrace? { search.trace }
    var codeOutboxLastDrainResult: CodeMemoryOutboxDrainResult? { settings.outboxLastDrainResult }
    var codeLastProjectionDrainResult: CodeMemoryProjectionDrainResponse? {
        settings.lastProjectionDrainResult ?? review.lastProjectionDrainResult ?? codeLastBackgroundCaptureResult
    }
    var codeLastReindexResult: CodeMemoryProjectionDrainResponse? { settings.lastReindexResult }
    var codeLastReinferResult: CodeMemoryReinferSourcesResponse? { settings.lastReinferResult }
    var isCodeMemoryLoading: Bool {
        isLoading
            || search.isLoading
            || search.isSearching
            || library.isLoading
            || library.isLoadingProjectSortMetadata
            || graph.isLoadingChanges
            || review.isLoading
            || settings.isLoading
    }
    var isSearching: Bool { search.isSearching }
    var lastError: String? {
        syncError ?? settings.lastError ?? search.lastError ?? library.lastError ?? graph.changeLastError ?? review.lastError
    }
    var setupMessage: String? { settings.setupMessage }
    var diagnosticsRetentionDays: Int { settings.diagnosticsRetention.rawValue }

    var searchText: String {
        get { search.query }
        set { search.query = newValue }
    }

    var contextText: String {
        get { search.contextQuery }
        set { search.contextQuery = newValue }
    }

    var codeSelectedProjectID: String? {
        get { selectedProjectID }
        set { selectedProjectID = newValue }
    }

    func select(_ next: MemoryWorkspaceSection) {
        section = next
    }

    func loadIfNeeded(sessions: [Session] = []) async {
        guard !hasLoaded else { return }
        await reload(sessions: sessions)
    }

    func reload(sessions: [Session] = []) async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        await refreshCodeMemoryStatus(sessions: sessions)
    }

    func refreshCodeMemoryStatus(sessions: [Session] = []) async {
        await settings.refresh()
        await library.loadProjects()
        await library.refreshProjectSortMetadata(sessions: sessions)
        if selectedProjectID == nil {
            selectedProjectID = library.sortedProjects.first?.projectID
        }
        await library.loadProjectContent(projectID: selectedProjectID)
        await review.load(projectID: selectedProjectID)
    }

    func performSearch() async {
        await search.performSearch(projectID: selectedProjectID)
        if selectedProjectID == nil, let projectID = search.memoryResults.first?.memory.projectID {
            selectedProjectID = projectID
        }
    }

    func clearSearchResults() {
        search.clear()
    }

    func loadContextPack() async {
        await search.loadContextPack(projectID: selectedProjectID)
    }

    func loadEvents() async {
        await search.loadEvents(projectID: selectedProjectID)
    }

    func selectCodeProject(_ projectID: String) async {
        selectedProjectID = projectID
        await library.loadProjects()
        await library.loadProjectContent(projectID: projectID)
        await graph.loadChanges(projectID: projectID)
        await review.load(projectID: projectID)
    }

    func selectLibraryProject(_ projectID: String) async {
        library.selectedModuleID = nil
        await selectCodeProject(projectID)
    }

    func selectModule(_ moduleID: String?) async {
        library.selectedModuleID = moduleID
        await library.loadMemories(projectID: selectedProjectID)
    }

    func loadCodeModules() async {
        await library.loadModules(projectID: selectedProjectID)
    }

    func loadCodeProposals() async {
        await review.load(projectID: selectedProjectID)
    }

    func acceptProposal(_ memory: CodeMemoryMemory) async {
        await review.accept(memory)
        await refreshCodeMemoryStatus()
    }

    func rejectProposal(_ memory: CodeMemoryMemory) async {
        await review.reject(memory)
        await refreshCodeMemoryStatus()
    }

    func deprecateMemory(_ memory: CodeMemoryMemory) async {
        await review.deprecate(memory)
        await refreshCodeMemoryStatus()
    }

    func updateMemory(_ memory: CodeMemoryMemory, with update: CodeMemoryMemoryUpdate) async {
        await review.update(memory, with: update)
        await refreshCodeMemoryStatus()
    }

    func promoteGraphFact(_ fact: CodeMemoryGraphFact) async {
        await review.promote(fact)
        await refreshCodeMemoryStatus()
    }

    func reindexCodeMemory(drain: Bool = false, drainLimit: Int? = nil) async {
        await settings.reindex(projectID: selectedProjectID, drain: drain, drainLimit: drainLimit)
        await refreshCodeMemoryStatus()
    }

    func reinferCodeMemorySources() async {
        await settings.reinferSources(projectID: selectedProjectID)
        await refreshCodeMemoryStatus()
    }

    func drainCodeMemoryProjections(includeFailed: Bool = false) async {
        await settings.drainProjections(includeFailed: includeFailed)
        await refreshCodeMemoryStatus()
    }

    func drainQueuedMemoryCaptures(limit: Int, includeFailed: Bool = false) async {
        guard !isBackgroundCapturing else { return }
        isBackgroundCapturing = true
        defer { isBackgroundCapturing = false }

        MemoryDiagnosticsLog.record(
            "swift.capture.drain.request",
            retentionDays: diagnosticsRetentionDays,
            fields: [
                "limit": "\(limit)",
                "include_failed": "\(includeFailed)",
            ]
        )
        do {
            let response = try await codeBackend.drainCaptures(limit: limit, includeFailed: includeFailed)
            codeLastBackgroundCaptureResult = response
            MemoryDiagnosticsLog.record(
                "swift.capture.drain.result",
                retentionDays: diagnosticsRetentionDays,
                fields: [
                    "delivered": "\(response.delivered ?? 0)",
                    "failed": "\(response.failed ?? 0)",
                    "remaining": "\(response.remaining ?? 0)",
                    "pending": "\(response.pending ?? 0)",
                    "skipped": "\(response.skipped ?? false)",
                ]
            )
            if response.skipped == true {
                syncError = response.message
            } else {
                syncError = nil
            }
        } catch {
            MemoryDiagnosticsLog.record(
                "swift.capture.drain.error",
                level: "error",
                retentionDays: diagnosticsRetentionDays,
                fields: ["error": error.localizedDescription]
            )
            syncError = "Mem0 capture failed: \(error.localizedDescription)"
        }
        await settings.refresh()
    }

    func loadCodeTrace(runID: String) async {
        await search.loadTrace(runID: runID)
    }

    func loadLastTrace() async {
        guard let traceID = search.lastTraceID else { return }
        await search.loadTrace(runID: traceID)
    }

    func startCodeMemorySidecar(
        localAIEnvironment: CodeMemoryLocalAIEnvironment? = nil,
        modelRuntimeConfig: CodeMemoryModelRuntimeConfig? = nil,
        sessions: [Session] = []
    ) async {
        await settings.startSidecar(
            localAIEnvironment: localAIEnvironment,
            modelRuntimeConfig: modelRuntimeConfig
        )
        await refreshCodeMemoryStatus(sessions: sessions)
    }

    func stopCodeMemorySidecar() async {
        await settings.stopSidecar()
    }

    func installShell(shell: MemoryShell, helperPath: String) {
        settings.installShell(shell: shell, helperPath: helperPath)
    }

    func uninstallShell(shell: MemoryShell) {
        settings.uninstallShell(shell: shell)
    }

    func syncAvailableSources(sessions: [Session], configProjects: [AIConfigProject]) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        syncError = nil
        let sources = await Self.makeSyncSources(sessions: sessions, configProjects: configProjects)
        guard !sources.isEmpty else {
            codeLastSyncSummary = "No local sources found."
            return
        }

        var created = 0
        var proposed = 0
        var queued = 0
        var skipped = 0
        var failed = 0
        for source in sources {
            MemoryDiagnosticsLog.record(
                "swift.source.upload.start",
                retentionDays: diagnosticsRetentionDays,
                fields: [
                    "source_id": source.id ?? "",
                    "source_kind": source.kind,
                    "project_id": source.projectID,
                    "content_hash": source.contentHash,
                    "text_chars": "\(source.body.count)",
                ]
            )
            do {
                let response = try await codeBackend.ingestSource(source)
                MemoryDiagnosticsLog.record(
                    "swift.source.upload.end",
                    retentionDays: diagnosticsRetentionDays,
                    fields: [
                        "source_id": source.id ?? "",
                        "source_kind": source.kind,
                        "project_id": source.projectID,
                        "status": response.status,
                        "queued": "\(response.queued ?? 0)",
                        "created": "\(response.created?.count ?? 0)",
                        "proposed": "\(response.proposed?.count ?? 0)",
                    ]
                )
                if response.status == "skipped" {
                    skipped += 1
                }
                created += response.created?.count ?? 0
                proposed += response.proposed?.count ?? 0
                queued += response.queued ?? (response.status == "queued" ? 1 : 0)
            } catch {
                MemoryDiagnosticsLog.record(
                    "swift.source.upload.error",
                    level: "error",
                    retentionDays: diagnosticsRetentionDays,
                    fields: [
                        "source_id": source.id ?? "",
                        "source_kind": source.kind,
                        "project_id": source.projectID,
                        "error": error.localizedDescription,
                    ]
                )
                failed += 1
            }
        }
        codeLastSyncSummary = "Synced \(sources.count) sources · \(queued) queued · \(created) active · \(proposed) proposed · \(skipped) skipped · \(failed) failed"
        await refreshCodeMemoryStatus(sessions: sessions)
    }
}

private extension MemoryWorkspaceStore {
    static func makeSyncSources(sessions: [Session], configProjects: [AIConfigProject]) async -> [CodeMemorySourceInput] {
        var sources: [CodeMemorySourceInput] = []
        for session in sessions.prefix(80) {
            let body = await transcriptMemoryBody(for: session, limit: 128 * 1024)
            guard !body.isEmpty else { continue }
            let projectID = session.cwd ?? session.projectDisplayName
            sources.append(
                CodeMemorySourceInput(
                    id: "session:\(session.id):\(MemoryHash.textHash(body).prefix(16))",
                    projectID: projectID,
                    title: session.stats?.title ?? session.projectDisplayName,
                    body: body,
                    kind: session.provider == .codex ? "codex_transcript" : "claude_transcript",
                    uri: session.filePath,
                    path: session.filePath,
                    contentHash: MemoryHash.textHash(body),
                    infer: true,
                    metadata: [
                        "provider": session.provider.rawValue,
                        "session_id": session.id,
                        "external_id": session.externalID,
                        "project": session.projectDisplayName,
                    ]
                )
            )
        }

        for project in configProjects {
            for document in project.documents {
                guard document.exists else { continue }
                let kind = configSourceKind(document)
                var body = document.contentPreview ?? ""
                if document.isPreviewTruncated || kind == "AGENTS.md" || kind == "CLAUDE.md" {
                    let fullBody = await readPreview(path: document.path, limit: 512 * 1024)
                    if !fullBody.isEmpty {
                        body = fullBody
                    }
                }
                guard !body.isEmpty else { continue }
                let projectID = document.assignedProjectPath ?? project.path ?? project.name
                sources.append(
                    CodeMemorySourceInput(
                        id: "config:\(document.id):\(MemoryHash.textHash(body).prefix(16))",
                        projectID: projectID,
                        title: document.title,
                        body: body,
                        kind: kind,
                        uri: document.path,
                        path: document.path,
                        contentHash: MemoryHash.textHash(body),
                        infer: shouldInferConfigSource(kind),
                        metadata: [
                            "provider": document.provider.rawValue,
                            "document_id": document.id,
                            "document_kind": "\(document.kind)",
                            "file_kind": "\(document.fileKind)",
                        ]
                    )
                )
            }
        }
        return sources
    }

    static func shouldInferConfigSource(_ kind: String) -> Bool {
        kind == "AGENTS.md" || kind == "CLAUDE.md"
    }

    static func transcriptMemoryBody(for session: Session, limit: Int) async -> String {
        let url = URL(fileURLWithPath: session.filePath)
        let messages: [SessionTranscriptMessage]
        switch session.provider {
        case .codex:
            messages = await CodexTranscriptParser(pricing: .fallback).messages(transcriptAt: url)
        case .claude:
            messages = await TranscriptParser(pricing: .fallback).messages(transcriptAt: url)
        case .opencode:
            messages = OpenCodeTranscriptParser(pricing: .fallback).messages(for: session)
        case .kiro:
            messages = KiroTranscriptParser(pricing: .fallback).messages(for: session)
        case .hermes:
            messages = HermesTranscriptParser(pricing: .fallback).messages(for: session)
        case .zcode:
            messages = ZCodeTranscriptParser(paths: .default, pricing: .fallback).messages(for: session)
        case .gemini:
            messages = []
        }

        let conversation = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .prefix(120)
            .map { "\($0.role.memoryLabel): \(limitText($0.text, to: 4_000))" }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conversation.isEmpty else { return "" }

        let header = [
            "Session: \(session.stats?.title ?? session.projectDisplayName)",
            "Project: \(session.cwd ?? session.projectDisplayName)",
        ].joined(separator: "\n")
        return limitText("\(header)\n\n\(conversation)", to: limit)
    }

    static func readPreview(path: String, limit: Int) async -> String {
        await Task.detached(priority: .utility) {
            guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return "" }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: limit), !data.isEmpty else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }

    static func configSourceKind(_ document: AIConfigDocument) -> String {
        if document.title == "AGENTS.md" { return "AGENTS.md" }
        if document.title == "CLAUDE.md" || document.title.contains("CLAUDE.md") { return "CLAUDE.md" }
        switch document.kind {
        case .instruction:
            return "ai_config"
        case .providerConfig:
            return "provider_config"
        case .pluginConfig:
            return "plugin_config"
        case .plan:
            return "plan"
        case .other:
            return "ai_config"
        }
    }

    static func limitText(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "\n..."
    }
}

private extension SessionTranscriptMessage.Role {
    var memoryLabel: String {
        switch self {
        case .user:
            "User"
        case .assistant:
            "Assistant"
        case .tool:
            "Tool"
        case .system:
            "System"
        }
    }
}
