import Foundation

struct GitCommitMessagePromptFactory: Sendable {
    func singleShotContext(snapshot: GitCommitMessageSnapshot, analysis: GitCommitMessageAnalysis) -> String {
        """
        Target: \(snapshot.target.displayTitle)
        Existing commit subject: \(snapshot.targetSubject ?? "-")
        Existing commit body:
        \(snapshot.body ?? "-")

        Files:
        \(fileList(snapshot.files))

        Risk labels:
        \(riskList(analysis.riskLabels))

        Diff:
        \(snapshot.diffText.gitCommitMessageTruncated(to: 48_000))

        Untracked snippets:
        \(untrackedList(snapshot.untrackedSnippets).gitCommitMessageTruncated(to: 12_000))
        """
    }

    func reduceContext(
        snapshot: GitCommitMessageSnapshot,
        analysis: GitCommitMessageAnalysis,
        repoContext: String,
        observations: [GitCommitMessageObservation]
    ) -> String {
        """
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
        \(observationList(observations))
        """
    }

    func riskAgentPrompt(snapshot: GitCommitMessageSnapshot, analysis: GitCommitMessageAnalysis, chunks: [GitDiffChunk], language: String) -> String {
        let riskyText = chunks
            .filter { !$0.riskLabels.isEmpty }
            .prefix(6)
            .map { "### \($0.path)\n\($0.text.gitCommitMessageTruncated(to: 8_000))" }
            .joined(separator: "\n\n")
        return """
        Analyze only high-risk changes for API/schema/auth/build/concurrency regressions.
        Language: \(language)

        Files:
        \(fileList(snapshot.files))

        Risk labels:
        \(riskList(analysis.riskLabels))

        Diff excerpts:
        \(riskyText.isEmpty ? snapshot.diffText.gitCommitMessageTruncated(to: 20_000) : riskyText)

        Return JSON with keys: id, path, summary, key_changes, risks, public_interfaces, questions.
        """
    }

    func chunkSystemPrompt(language: String) -> String {
        """
        You are a senior code reviewer extracting facts from one Git diff chunk.
        Write in \(language). Be precise, grounded only in the diff, and return compact JSON for downstream commit message generation.
        """
    }

    func finalSystemPrompt(language: String) -> String {
        """
        You write Git commit messages for developers.
        Write in \(language). Ground the message only in the provided diff, file list, existing commit text, and observations.
        Return only valid JSON with keys: commit_title, commit_body.
        """
    }

    func finalUserInstruction(context: String, algorithm: GitCommitMessageAlgorithm) -> String {
        """
        Algorithm: \(algorithm.title)

        Produce:
        - commit_title: one Conventional Commit subject under 72 characters, formatted as <type>(optional-scope): <imperative summary>.
        - commit_body: short commit body with important details, tests, or caveats when useful. Use an empty string for trivial changes.

        Rules:
        - Use a lowercased Conventional Commit type such as feat, fix, refactor, perf, test, docs, build, ci, chore, style, or revert.
        - Add a short kebab-case scope only when it is clear from the changed area, for example refactor(git): or fix(settings):.
        - Keep the subject after the colon imperative, concise, and sentence-case only when the target language requires it.
        - Return only the two requested keys. Do not add any other keys, Markdown sections, or explanatory text.
        - Do not invent tests or risk notes not supported by the evidence.
        - Prefer short body bullets for multi-detail changes; plain prose is okay for one detail.

        Return compact JSON like:
        {"commit_title":"...","commit_body":"..."}

        Context:
        \(context)
        """
    }

    func chunkPrompt(_ chunk: GitDiffChunk) -> String {
        """
        Chunk ID: \(chunk.id)
        Path: \(chunk.path)
        Risk labels: \(chunk.riskLabels.map(\.title).joined(separator: ", ").gitCommitMessageNilIfEmpty ?? "-")

        Return JSON with keys: id, path, summary, key_changes, risks, public_interfaces, questions.

        Diff chunk:
        \(chunk.text)
        """
    }

    func fileList(_ files: [GitCommitMessageFileChange]) -> String {
        if files.isEmpty { return "-" }
        return files.map {
            let old = $0.oldPath.map { " <- \($0)" } ?? ""
            let binary = $0.isBinary ? " binary" : ""
            return "- \($0.status.rawValue): \($0.path)\(old) +\($0.insertions) -\($0.deletions)\(binary)"
        }.joined(separator: "\n")
    }

    func riskList(_ labels: [GitCommitMessageRiskLabel]) -> String {
        if labels.isEmpty { return "-" }
        return labels.map {
            let paths = $0.paths.isEmpty ? "" : " [\($0.paths.prefix(4).joined(separator: ", "))]"
            return "- \($0.title) score=\($0.score)\(paths): \($0.reason)"
        }.joined(separator: "\n")
    }

    func untrackedList(_ snippets: [GitUntrackedSnippet]) -> String {
        if snippets.isEmpty { return "-" }
        return snippets.map { "### \($0.path)\($0.truncated ? " (truncated)" : "")\n\($0.text)" }.joined(separator: "\n\n")
    }

    func observationList(_ observations: [GitCommitMessageObservation]) -> String {
        if observations.isEmpty { return "-" }
        return observations.map { observation in
            """
            ### \(observation.path)
            Summary: \(observation.summary)
            Key changes: \(observation.keyChanges.joined(separator: "; ").gitCommitMessageNilIfEmpty ?? "-")
            Risks: \(observation.risks.joined(separator: "; ").gitCommitMessageNilIfEmpty ?? "-")
            Public interfaces: \(observation.publicInterfaces.joined(separator: "; ").gitCommitMessageNilIfEmpty ?? "-")
            Questions: \(observation.questions.joined(separator: "; ").gitCommitMessageNilIfEmpty ?? "-")
            """
        }.joined(separator: "\n\n")
    }
}
