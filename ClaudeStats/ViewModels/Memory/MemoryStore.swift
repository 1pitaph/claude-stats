import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class MemoryStore {
    var section: MemoryWorkspaceSection = .overview
    var searchText = ""
    var contextText = ""

    private(set) var codeHealth: CodeMemoryHealth?
    private(set) var codeProjects: [CodeMemoryProject] = []
    private(set) var codeModules: [CodeMemoryModule] = []
    private(set) var codeSearchResults: [CodeMemorySearchResult] = []
    private(set) var codeLastTraceID: String?
    private(set) var codeContextPack: CodeMemoryContextPack?
    private(set) var codeProposals: [CodeMemoryMemory] = []
    private(set) var codeEvents: [CodeMemoryEvent] = []
    private(set) var codeSelectedProjectID: String?
    private(set) var codeGraph: CodeMemoryGraph?
    private(set) var codeTrace: CodeMemoryRunTrace?
    private(set) var codeOutboxLastDrainResult: CodeMemoryOutboxDrainResult?
    private(set) var codeLastProjectionDrainResult: CodeMemoryProjectionDrainResponse?
    private(set) var codeLastReindexResult: CodeMemoryProjectionDrainResponse?
    private(set) var codeLastSyncSummary: String?
    private(set) var isCodeMemoryLoading = false
    private(set) var isLoading = false
    private(set) var isSearching = false
    private(set) var lastError: String?
    private(set) var setupMessage: String?

    @ObservationIgnored private let codeBackend: any CodeMemoryBackend
    @ObservationIgnored private let codeOutbox: CodeMemoryEventOutbox
    @ObservationIgnored private var hasLoaded = false

    init(
        codeBackend: any CodeMemoryBackend = CodeMemoryHTTPClient(),
        codeOutbox: CodeMemoryEventOutbox = CodeMemoryEventOutbox()
    ) {
        self.codeBackend = codeBackend
        self.codeOutbox = codeOutbox
    }

    func select(_ next: MemoryWorkspaceSection) {
        section = next
    }

    func clearSearchResults() {
        codeSearchResults = []
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await refreshCodeMemoryStatus()
        hasLoaded = true
    }

    func performSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            codeSearchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let response = try await codeBackend.search(query: query, projectID: codeSelectedProjectID, limit: 30)
            codeSearchResults = response.results
            codeLastTraceID = response.traceID
            if let first = response.results.first?.memory.projectID {
                codeSelectedProjectID = first
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshCodeMemoryStatus() async {
        guard !isCodeMemoryLoading else { return }
        isCodeMemoryLoading = true
        defer { isCodeMemoryLoading = false }
        do {
            async let health = codeBackend.health()
            async let projects = codeBackend.projects()
            async let modules = codeBackend.modules(projectID: codeSelectedProjectID)
            async let proposals = codeBackend.proposals(projectID: codeSelectedProjectID, limit: 50)
            codeHealth = try await health
            codeProjects = try await projects
            codeModules = try await modules
            codeProposals = try await proposals
            if codeSelectedProjectID == nil {
                codeSelectedProjectID = codeProjects.first?.projectID
            }
            lastError = nil
        } catch {
            codeHealth = nil
            codeProjects = []
            codeModules = []
            codeProposals = []
            lastError = "Code Memory sidecar is unavailable: \(error.localizedDescription)"
        }
    }

    func startCodeMemorySidecar(localAIEnvironment: CodeMemoryLocalAIEnvironment? = nil) async {
        guard !isCodeMemoryLoading else { return }
        isCodeMemoryLoading = true
        do {
            let configuration = CodeMemorySidecarConfiguration(localAI: localAIEnvironment)
            let pid = try CodeMemorySidecarManager(configuration: configuration).start(helperPath: CodeMemorySidecarManager.defaultHelperPath())
            setupMessage = "Started memoryd pid=\(pid)."
            lastError = nil
        } catch {
            setupMessage = error.localizedDescription
            lastError = error.localizedDescription
            isCodeMemoryLoading = false
            return
        }
        isCodeMemoryLoading = false
        try? await Task.sleep(nanoseconds: 300_000_000)
        codeOutboxLastDrainResult = await codeOutbox.drain()
        await refreshCodeMemoryStatus()
    }

    func stopCodeMemorySidecar() async {
        guard !isCodeMemoryLoading else { return }
        isCodeMemoryLoading = true
        defer { isCodeMemoryLoading = false }
        do {
            let stopped = try CodeMemorySidecarManager().stop()
            setupMessage = stopped ? "Stopped memoryd." : "memoryd was not running."
            codeHealth = nil
            codeProjects = []
            codeGraph = nil
            lastError = nil
        } catch {
            setupMessage = error.localizedDescription
            lastError = error.localizedDescription
        }
    }

    func selectCodeProject(_ projectID: String) async {
        codeSelectedProjectID = projectID
        await loadCodeGraph(projectID: projectID)
        await loadCodeModules()
        await loadCodeProposals()
    }

    func loadCodeModules() async {
        do {
            codeModules = try await codeBackend.modules(projectID: codeSelectedProjectID)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadCodeProposals() async {
        do {
            codeProposals = try await codeBackend.proposals(projectID: codeSelectedProjectID, limit: 100)
            lastError = nil
        } catch {
            codeProposals = []
            lastError = error.localizedDescription
        }
    }

    func loadContextPack() async {
        let query = (contextText.isEmpty ? searchText : contextText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isCodeMemoryLoading = true
        defer { isCodeMemoryLoading = false }
        do {
            codeContextPack = try await codeBackend.contextPack(query: query, projectID: codeSelectedProjectID, limit: 12)
            codeLastTraceID = codeContextPack?.traceID
            lastError = nil
        } catch {
            codeContextPack = nil
            lastError = error.localizedDescription
        }
    }

    func loadEvents() async {
        do {
            codeEvents = try await codeBackend.events(projectID: codeSelectedProjectID, afterSeq: nil, limit: 100)
            lastError = nil
        } catch {
            codeEvents = []
            lastError = error.localizedDescription
        }
    }

    func acceptProposal(_ memory: CodeMemoryMemory) async {
        do {
            try await codeBackend.accept(memoryID: memory.id)
            var drainError: Error?
            do {
                codeLastProjectionDrainResult = try await codeBackend.drainProjections()
            } catch {
                drainError = error
            }
            await loadCodeProposals()
            await refreshCodeMemoryStatus()
            if let drainError {
                lastError = "Accepted proposal; projection drain failed: \(drainError.localizedDescription)"
            } else {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func rejectProposal(_ memory: CodeMemoryMemory) async {
        do {
            try await codeBackend.reject(memoryID: memory.id)
            await loadCodeProposals()
            await refreshCodeMemoryStatus()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reindexCodeMemory() async {
        guard !isCodeMemoryLoading else { return }
        isCodeMemoryLoading = true
        do {
            codeLastReindexResult = try await codeBackend.reindex(projectID: codeSelectedProjectID)
            isCodeMemoryLoading = false
            await refreshCodeMemoryStatus()
            lastError = nil
        } catch {
            isCodeMemoryLoading = false
            lastError = error.localizedDescription
        }
    }

    func drainCodeMemoryProjections() async {
        guard !isCodeMemoryLoading else { return }
        isCodeMemoryLoading = true
        do {
            codeLastProjectionDrainResult = try await codeBackend.drainProjections()
            isCodeMemoryLoading = false
            await refreshCodeMemoryStatus()
            lastError = nil
        } catch {
            isCodeMemoryLoading = false
            lastError = error.localizedDescription
        }
    }

    func loadCodeGraph(projectID: String? = nil) async {
        let projectID = projectID ?? codeSelectedProjectID ?? codeProjects.first?.projectID
        guard let projectID else {
            codeGraph = nil
            return
        }
        isCodeMemoryLoading = true
        defer { isCodeMemoryLoading = false }
        do {
            codeGraph = try await codeBackend.graph(projectID: projectID)
            codeSelectedProjectID = projectID
            lastError = nil
        } catch {
            codeGraph = nil
            lastError = error.localizedDescription
        }
    }

    func loadCodeTrace(runID: String) async {
        let trimmed = runID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isCodeMemoryLoading = true
        defer { isCodeMemoryLoading = false }
        do {
            codeTrace = try await codeBackend.trace(runID: trimmed)
            lastError = nil
        } catch {
            codeTrace = nil
            lastError = error.localizedDescription
        }
    }

    func syncAvailableSources(sessions: [Session], configProjects: [AIConfigProject]) async {
        guard !isCodeMemoryLoading else { return }
        isCodeMemoryLoading = true

        let sources = await Self.makeSyncSources(sessions: sessions, configProjects: configProjects)
        guard !sources.isEmpty else {
            codeLastSyncSummary = "No local sources found."
            isCodeMemoryLoading = false
            return
        }

        var created = 0
        var proposed = 0
        var skipped = 0
        var failed = 0
        for source in sources {
            do {
                let response = try await codeBackend.ingestSource(source)
                if response.status == "skipped" {
                    skipped += 1
                }
                created += response.created?.count ?? 0
                proposed += response.proposed?.count ?? 0
            } catch {
                failed += 1
            }
        }
        codeLastSyncSummary = "Synced \(sources.count) sources · \(created) active · \(proposed) proposed · \(skipped) skipped · \(failed) failed"
        isCodeMemoryLoading = false
        await refreshCodeMemoryStatus()
    }

    func installShell(shell: MemoryShell, helperPath: String) {
        do {
            let backup = try MemoryShellIntegrationManager().install(shell: shell, helperPath: helperPath)
            setupMessage = backup.map { "Installed \(shell.rawValue); backup at \($0.path.memoryAbbreviatingHomeDirectory)." }
                ?? "\(shell.rawValue) integration is already installed."
        } catch {
            setupMessage = error.localizedDescription
        }
    }

    func uninstallShell(shell: MemoryShell) {
        do {
            let backup = try MemoryShellIntegrationManager().uninstall(shell: shell)
            setupMessage = backup.map { "Uninstalled \(shell.rawValue); backup at \($0.path.memoryAbbreviatingHomeDirectory)." }
                ?? "\(shell.rawValue) integration was not installed."
        } catch {
            setupMessage = error.localizedDescription
        }
    }
}

private extension MemoryStore {
    static func makeSyncSources(sessions: [Session], configProjects: [AIConfigProject]) async -> [CodeMemorySourceInput] {
        var sources: [CodeMemorySourceInput] = []
        for session in sessions.prefix(80) {
            let body = await readPreview(path: session.filePath, limit: 128 * 1024)
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
                guard document.exists, let body = document.contentPreview, !body.isEmpty else { continue }
                let projectID = document.assignedProjectPath ?? project.path ?? project.name
                sources.append(
                    CodeMemorySourceInput(
                        id: "config:\(document.id):\(MemoryHash.textHash(body).prefix(16))",
                        projectID: projectID,
                        title: document.title,
                        body: body,
                        kind: configSourceKind(document),
                        uri: document.path,
                        path: document.path,
                        contentHash: MemoryHash.textHash(body),
                        infer: false,
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
        return "ai_config"
    }
}
