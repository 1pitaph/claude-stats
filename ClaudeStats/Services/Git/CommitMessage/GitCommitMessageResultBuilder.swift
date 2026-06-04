import Foundation

struct GitCommitMessageResultBuildOutcome: Sendable {
    var result: GitCommitMessageResult
    var jsonParseOK: Bool
}

struct GitCommitMessageResultBuilder: Sendable {
    func build(
        from rawText: String,
        snapshot: GitCommitMessageSnapshot,
        plan: GitCommitMessagePlan,
        modelName: String,
        usage: GitLLMUsage,
        language: String
    ) -> GitCommitMessageResultBuildOutcome {
        let parse = GitCommitMessageResponseParser.parseFinalCommitMessage(rawText)
        let decoded = parse.response
        let fallback = fallbackMessage(snapshot: snapshot, rawText: rawText)
        let result = GitCommitMessageResult(
            commitTitle: decoded?.commitTitle ?? fallback.title,
            commitBody: decoded?.commitBody ?? fallback.body,
            algorithm: plan.algorithm,
            modelName: modelName,
            usage: usage,
            isCached: false,
            generatedAt: .now,
            language: language,
            diffHash: snapshot.diffHash,
            targetTitle: snapshot.target.displayTitle
        )
        return GitCommitMessageResultBuildOutcome(result: result, jsonParseOK: parse.jsonParseOK)
    }

    private func fallbackMessage(snapshot: GitCommitMessageSnapshot, rawText: String) -> (title: String, body: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if snapshot.target.kind == "commit",
           let subject = snapshot.targetSubject?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subject.isEmpty {
            let body = snapshot.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (subject.gitCommitMessageTruncated(to: 72), body)
        }
        let lines = trimmed.components(separatedBy: .newlines)
        let title = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Update git changes"
        let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (title
            .replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression)
            .gitCommitMessageTruncated(to: 72), body)
    }
}
