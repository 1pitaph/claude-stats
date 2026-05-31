import Foundation

struct GitSummaryService: Sendable {
    static let promptVersion = "git-summary-prompt-v1"
    static let algorithmVersion = "git-summary-algorithm-v1"

    private let snapshotBuilder: GitSummarySnapshotBuilder
    private let classifier: GitChangeClassifier
    private let chunker: GitDiffChunker
    private let planner: GitSummaryPlanner
    private let cache: GitSummaryCache
    private let generator: any LLMGenerating

    init(
        snapshotBuilder: GitSummarySnapshotBuilder = GitSummarySnapshotBuilder(),
        classifier: GitChangeClassifier = GitChangeClassifier(),
        chunker: GitDiffChunker = GitDiffChunker(),
        planner: GitSummaryPlanner = GitSummaryPlanner(),
        cache: GitSummaryCache = GitSummaryCache(),
        generator: any LLMGenerating = AppLLMClient()
    ) {
        self.snapshotBuilder = snapshotBuilder
        self.classifier = classifier
        self.chunker = chunker
        self.planner = planner
        self.cache = cache
        self.generator = generator
    }

    func summarize(
        repo: GitRepo,
        target: GitSummaryTarget,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        forceRefresh: Bool = false
    ) async throws -> GitAISummaryResult {
        let snapshot = try await snapshotBuilder.snapshot(for: target, repo: repo)
        var analysis = classifier.classify(snapshot)
        let chunks = chunker.chunks(for: snapshot, analysis: analysis)
        analysis.skippedPaths = chunker.skippedPaths(for: snapshot)
        let plan = planner.plan(snapshot: snapshot, analysis: analysis, chunks: chunks)
        let key = cacheKey(snapshot: snapshot, endpoint: endpoint, language: language)

        if !forceRefresh, let cached = await cache.read(key) {
            return cached.cachedCopy()
        }

        let generated: GitAISummaryResult
        switch plan.algorithm {
        case .singleShot:
            generated = try await runSingleShot(snapshot: snapshot, analysis: analysis, plan: plan, endpoint: endpoint, language: language)
        case .fileLevel, .mapReduce, .mapReduceWithVerifier:
            generated = try await runMapReduce(
                snapshot: snapshot,
                analysis: analysis,
                chunks: chunks,
                plan: plan,
                endpoint: endpoint,
                language: language
            )
        }

        await cache.write(generated, for: key)
        return generated
    }

    private func runSingleShot(
        snapshot: GitSummarySnapshot,
        analysis: GitSummaryAnalysis,
        plan: GitSummaryPlan,
        endpoint: AppLLMGenerationEndpoint,
        language: String
    ) async throws -> GitAISummaryResult {
        let prompt = """
        Target: \(snapshot.target.displayTitle)
        Existing commit subject: \(snapshot.targetSubject ?? "-")
        Existing commit body:
        \(snapshot.body ?? "-")

        Files:
        \(fileList(snapshot.files))

        Risk labels:
        \(riskList(analysis.riskLabels))

        Diff:
        \(snapshot.diffText)

        Untracked snippets:
        \(untrackedList(snapshot.untrackedSnippets))
        """
        let request = LLMGenerationRequest(
            systemPrompt: finalSystemPrompt(language: language),
            userPrompt: finalUserInstruction(context: prompt, algorithm: plan.algorithm),
            maxTokens: 1_400,
            temperature: 0.2
        )
        let response = try await generator.generate(endpoint: endpoint, request: request)
        var usage = GitSummaryUsage.zero
        usage.add(response)
        return finalResult(
            from: response.text,
            fallbackSummary: response.text,
            snapshot: snapshot,
            analysis: analysis,
            plan: plan,
            modelName: response.model,
            usage: usage,
            language: language,
            verifierNotes: nil
        )
    }

    private func runMapReduce(
        snapshot: GitSummarySnapshot,
        analysis: GitSummaryAnalysis,
        chunks: [GitDiffChunk],
        plan: GitSummaryPlan,
        endpoint: AppLLMGenerationEndpoint,
        language: String
    ) async throws -> GitAISummaryResult {
        let observations = try await summarizeChunks(chunks, endpoint: endpoint, language: language)
        var usage = observations.usage
        var allObservations = observations.values
        var modelName = observations.modelName ?? endpoint.model

        if analysis.hasVerifierTrigger {
            let risk = try await runRiskAgent(snapshot: snapshot, analysis: analysis, chunks: chunks, endpoint: endpoint, language: language)
            usage.add(risk.usage)
            allObservations.append(risk.observation)
            modelName = risk.modelName
        }

        let repoContext = plan.includeRepoContext ? await repositoryContext(for: snapshot) : ""
        let reduceContext = """
        Target: \(snapshot.target.displayTitle)
        Existing commit subject: \(snapshot.targetSubject ?? "-")
        Files:
        \(fileList(snapshot.files))

        Risk labels:
        \(riskList(analysis.riskLabels))

        Skipped paths:
        \(analysis.skippedPaths.isEmpty ? "-" : analysis.skippedPaths.joined(separator: "\n"))

        Repo context:
        \(repoContext.isEmpty ? "-" : repoContext)

        Observations:
        \(observationList(allObservations))
        """
        let reduceRequest = LLMGenerationRequest(
            systemPrompt: finalSystemPrompt(language: language),
            userPrompt: finalUserInstruction(context: reduceContext, algorithm: plan.algorithm),
            maxTokens: 1_600,
            temperature: 0.2
        )
        let reduced = try await generator.generate(endpoint: endpoint, request: reduceRequest)
        usage.add(reduced)
        modelName = reduced.model
        var result = finalResult(
            from: reduced.text,
            fallbackSummary: reduced.text,
            snapshot: snapshot,
            analysis: analysis,
            plan: plan,
            modelName: modelName,
            usage: usage,
            language: language,
            verifierNotes: nil
        )

        if plan.useVerifier {
            let verifier = try await runVerifier(
                result: result,
                snapshot: snapshot,
                analysis: analysis,
                observations: allObservations,
                endpoint: endpoint,
                language: language
            )
            result.usage.add(verifier.usage)
            result.verifierNotes = verifier.notes
            result.modelName = verifier.modelName
        }

        return result
    }

    private func summarizeChunks(
        _ chunks: [GitDiffChunk],
        endpoint: AppLLMGenerationEndpoint,
        language: String
    ) async throws -> (values: [GitSummaryObservation], usage: GitSummaryUsage, modelName: String?) {
        if chunks.isEmpty {
            return ([], .zero, nil)
        }

        let generator = generator
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: (GitSummaryObservation, LLMGenerationResult).self) { group in
            for chunk in chunks {
                group.addTask {
                    let request = LLMGenerationRequest(
                        systemPrompt: chunkSystemPrompt(language: language),
                        userPrompt: chunkPrompt(chunk),
                        maxTokens: 800,
                        temperature: 0.15
                    )
                    let response = try await generator.generate(endpoint: endpoint, request: request)
                    return (parseObservation(response.text, fallbackPath: chunk.path, fallbackID: chunk.id), response)
                }
            }

            var values: [GitSummaryObservation] = []
            var usage = GitSummaryUsage.zero
            var modelName: String?
            for try await (observation, response) in group {
                values.append(observation)
                usage.add(response)
                modelName = response.model
            }
            values.sort { $0.id < $1.id }
            return (values, usage, modelName)
        }
    }

    private func runRiskAgent(
        snapshot: GitSummarySnapshot,
        analysis: GitSummaryAnalysis,
        chunks: [GitDiffChunk],
        endpoint: AppLLMGenerationEndpoint,
        language: String
    ) async throws -> (observation: GitSummaryObservation, usage: GitSummaryUsage, modelName: String) {
        let riskyText = chunks
            .filter { !$0.riskLabels.isEmpty }
            .prefix(6)
            .map { "### \($0.path)\n\($0.text.truncated(to: 8_000))" }
            .joined(separator: "\n\n")
        let prompt = """
        Analyze only high-risk changes for API/schema/auth/build/concurrency regressions.
        Language: \(language)

        Files:
        \(fileList(snapshot.files))

        Risk labels:
        \(riskList(analysis.riskLabels))

        Diff excerpts:
        \(riskyText.isEmpty ? snapshot.diffText.truncated(to: 20_000) : riskyText)

        Return JSON with keys: id, path, summary, key_changes, risks, public_interfaces, questions.
        """
        let response = try await generator.generate(
            endpoint: endpoint,
            request: LLMGenerationRequest(systemPrompt: chunkSystemPrompt(language: language), userPrompt: prompt, maxTokens: 900, temperature: 0.1)
        )
        var usage = GitSummaryUsage.zero
        usage.add(response)
        var observation = parseObservation(response.text, fallbackPath: "risk-agent", fallbackID: "risk-agent")
        observation.id = "risk-agent"
        observation.path = "risk-agent"
        return (observation, usage, response.model)
    }

    private func runVerifier(
        result: GitAISummaryResult,
        snapshot: GitSummarySnapshot,
        analysis: GitSummaryAnalysis,
        observations: [GitSummaryObservation],
        endpoint: AppLLMGenerationEndpoint,
        language: String
    ) async throws -> (notes: String, usage: GitSummaryUsage, modelName: String) {
        let prompt = """
        Check the proposed Git summary against the file list, risk labels, and observations.
        Do not rewrite everything. Return concise verifier notes with omissions, hallucinations, or "No material issues found."
        Language: \(language)

        Proposed summary:
        \(result.summary)

        Proposed commit message:
        \(result.commitMessage)

        Files:
        \(fileList(snapshot.files))

        Risk labels:
        \(riskList(analysis.riskLabels))

        Observations:
        \(observationList(observations).truncated(to: 28_000))
        """
        let response = try await generator.generate(
            endpoint: endpoint,
            request: LLMGenerationRequest(systemPrompt: verifierSystemPrompt(language: language), userPrompt: prompt, maxTokens: 700, temperature: 0.1)
        )
        var usage = GitSummaryUsage.zero
        usage.add(response)
        return (response.text.trimmingCharacters(in: .whitespacesAndNewlines), usage, response.model)
    }

    private func finalResult(
        from rawText: String,
        fallbackSummary: String,
        snapshot: GitSummarySnapshot,
        analysis: GitSummaryAnalysis,
        plan: GitSummaryPlan,
        modelName: String,
        usage: GitSummaryUsage,
        language: String,
        verifierNotes: String?
    ) -> GitAISummaryResult {
        let decoded = parseFinalSummary(rawText)
        let summary = decoded?.summary ?? fallbackSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = decoded?.commitTitle ?? fallbackTitle(snapshot: snapshot, summary: summary)
        let body = decoded?.commitBody ?? fallbackBody(summary: summary, analysis: analysis)
        return GitAISummaryResult(
            summary: summary,
            commitTitle: title,
            commitBody: body,
            riskLabels: analysis.riskLabels,
            algorithm: plan.algorithm,
            modelName: modelName,
            usage: usage,
            isCached: false,
            generatedAt: .now,
            language: language,
            diffHash: snapshot.diffHash,
            targetTitle: snapshot.target.displayTitle,
            verifierNotes: verifierNotes ?? decoded?.verifierNotes
        )
    }

    private func cacheKey(snapshot: GitSummarySnapshot, endpoint: AppLLMGenerationEndpoint, language: String) -> GitSummaryCacheKey {
        GitSummaryCacheKey(
            repoKey: snapshot.repo.cacheKey,
            targetKind: snapshot.target.kind,
            targetID: snapshot.target.identity,
            diffHash: snapshot.diffHash,
            language: language,
            modelID: "\(endpoint.mode.rawValue)|\(endpoint.protocol.rawValue)|\(endpoint.baseURL.absoluteString)|\(endpoint.model)",
            promptVersion: Self.promptVersion,
            algorithmVersion: Self.algorithmVersion
        )
    }

    private func repositoryContext(for snapshot: GitSummarySnapshot) async -> String {
        await Task.detached(priority: .utility) {
            let root = URL(fileURLWithPath: snapshot.repo.rootPath)
            let candidates = [
                "AGENTS.md",
                "README.md",
                "Package.swift",
                "project.yml",
                "Info.plist",
                ".github/workflows/release.yml",
            ]
            var blocks: [String] = []
            for candidate in candidates {
                let url = root.appendingPathComponent(candidate)
                guard let data = try? Data(contentsOf: url), data.count <= 96 * 1024,
                      let text = String(data: data, encoding: .utf8)
                else { continue }
                blocks.append("### \(candidate)\n\(text.truncated(to: 4_000))")
            }
            return blocks.joined(separator: "\n\n").truncated(to: 24_000)
        }.value
    }
}

private struct GitSummaryObservation: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var path: String
    var summary: String
    var keyChanges: [String]
    var risks: [String]
    var publicInterfaces: [String]
    var questions: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case summary
        case keyChanges = "key_changes"
        case risks
        case publicInterfaces = "public_interfaces"
        case questions
    }
}

private struct GitSummaryFinalLLMResponse: Decodable {
    var summary: String
    var commitTitle: String
    var commitBody: String
    var verifierNotes: String?

    private enum CodingKeys: String, CodingKey {
        case summary
        case commitTitle = "commit_title"
        case commitBody = "commit_body"
        case verifierNotes = "verifier_notes"
    }
}

private func chunkSystemPrompt(language: String) -> String {
    """
    You are a senior code reviewer summarizing one Git diff chunk.
    Write in \(language). Be precise, grounded only in the diff, and return compact JSON.
    """
}

private func verifierSystemPrompt(language: String) -> String {
    """
    You are a verifier for Git change summaries. Write in \(language).
    Compare claims against the provided evidence and flag omissions or hallucinations.
    """
}

private func finalSystemPrompt(language: String) -> String {
    """
    You summarize Git changes for developers.
    Write in \(language). Be concise, avoid hype, and ground every claim in the provided diff, file list, and observations.
    Return only valid JSON with keys: summary, commit_title, commit_body, verifier_notes.
    """
}

private func finalUserInstruction(context: String, algorithm: GitSummaryAlgorithm) -> String {
    """
    Algorithm: \(algorithm.title)

    Produce:
    - summary: 2-5 concise bullets or sentences covering behavior, files, and risks.
    - commit_title: one imperative commit title under 72 characters.
    - commit_body: short commit body with important details and risk/test notes.
    - verifier_notes: empty unless you see uncertainty in the evidence.

    Context:
    \(context)
    """
}

private func chunkPrompt(_ chunk: GitDiffChunk) -> String {
    """
    Chunk ID: \(chunk.id)
    Path: \(chunk.path)
    Risk labels: \(chunk.riskLabels.map(\.title).joined(separator: ", ").nilIfEmpty ?? "-")

    Return JSON with keys: id, path, summary, key_changes, risks, public_interfaces, questions.

    Diff chunk:
    \(chunk.text)
    """
}

private func fileList(_ files: [GitSummaryFileChange]) -> String {
    if files.isEmpty { return "-" }
    return files.map {
        let old = $0.oldPath.map { " <- \($0)" } ?? ""
        let binary = $0.isBinary ? " binary" : ""
        return "- \($0.status.rawValue): \($0.path)\(old) +\($0.insertions) -\($0.deletions)\(binary)"
    }.joined(separator: "\n")
}

private func riskList(_ labels: [GitSummaryRiskLabel]) -> String {
    if labels.isEmpty { return "-" }
    return labels.map {
        let paths = $0.paths.isEmpty ? "" : " [\($0.paths.prefix(4).joined(separator: ", "))]"
        return "- \($0.title) score=\($0.score)\(paths): \($0.reason)"
    }.joined(separator: "\n")
}

private func untrackedList(_ snippets: [GitUntrackedSnippet]) -> String {
    if snippets.isEmpty { return "-" }
    return snippets.map { "### \($0.path)\($0.truncated ? " (truncated)" : "")\n\($0.text)" }.joined(separator: "\n\n")
}

private func observationList(_ observations: [GitSummaryObservation]) -> String {
    if observations.isEmpty { return "-" }
    return observations.map { observation in
        """
        ### \(observation.path)
        Summary: \(observation.summary)
        Key changes: \(observation.keyChanges.joined(separator: "; ").nilIfEmpty ?? "-")
        Risks: \(observation.risks.joined(separator: "; ").nilIfEmpty ?? "-")
        Public interfaces: \(observation.publicInterfaces.joined(separator: "; ").nilIfEmpty ?? "-")
        Questions: \(observation.questions.joined(separator: "; ").nilIfEmpty ?? "-")
        """
    }.joined(separator: "\n\n")
}

private func parseObservation(_ raw: String, fallbackPath: String, fallbackID: String) -> GitSummaryObservation {
    if let data = extractJSONObject(from: raw)?.data(using: .utf8),
       let decoded = try? JSONDecoder().decode(GitSummaryObservation.self, from: data) {
        return decoded
    }
    return GitSummaryObservation(
        id: fallbackID,
        path: fallbackPath,
        summary: raw.trimmingCharacters(in: .whitespacesAndNewlines),
        keyChanges: [],
        risks: [],
        publicInterfaces: [],
        questions: []
    )
}

private func parseFinalSummary(_ raw: String) -> GitSummaryFinalLLMResponse? {
    guard let json = extractJSONObject(from: raw), let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(GitSummaryFinalLLMResponse.self, from: data)
}

private func extractJSONObject(from raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
        return trimmed
    }
    guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end else {
        return nil
    }
    return String(trimmed[start...end])
}

private func fallbackTitle(snapshot: GitSummarySnapshot, summary: String) -> String {
    if snapshot.target.kind == "commit", let subject = snapshot.targetSubject?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
        return subject.truncated(to: 72)
    }
    let firstLine = summary.split(separator: "\n").first.map(String.init) ?? "Summarize git changes"
    return firstLine
        .replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression)
        .truncated(to: 72)
}

private func fallbackBody(summary: String, analysis: GitSummaryAnalysis) -> String {
    let risks = analysis.riskLabels.prefix(5).map(\.title).joined(separator: ", ")
    if risks.isEmpty { return summary }
    return "\(summary)\n\nRisk labels: \(risks)"
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    func truncated(to maxLength: Int) -> String {
        guard count > maxLength else { return self }
        return String(prefix(max(0, maxLength - 12))) + "\n[truncated]"
    }
}
