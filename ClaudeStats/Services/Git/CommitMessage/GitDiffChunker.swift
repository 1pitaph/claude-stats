import Foundation

struct GitDiffChunker: Sendable {
    var maxTokensPerChunk: Int = 6_000

    func chunks(for snapshot: GitCommitMessageSnapshot, analysis: GitCommitMessageAnalysis) -> [GitDiffChunk] {
        let filesByPath = Dictionary(uniqueKeysWithValues: snapshot.files.map { ($0.path, $0) })
        var chunks: [GitDiffChunk] = []
        var skipped: [String] = []

        for section in GitDiffSectionParser.splitDiffSections(snapshot.diffText) {
            let path = GitDiffSectionParser.path(for: section)
            guard !path.isEmpty else { continue }
            guard let file = filesByPath[path], !shouldSkip(file) else {
                skipped.append(path)
                continue
            }
            chunks.append(contentsOf: splitSection(section, path: path, riskLabels: labels(for: path, analysis: analysis)))
        }

        for snippet in snapshot.untrackedSnippets {
            let file = filesByPath[snippet.path] ?? GitCommitMessageFileChange(
                path: snippet.path,
                oldPath: nil,
                status: .untracked,
                insertions: snippet.text.split(separator: "\n").count,
                deletions: 0,
                isBinary: false
            )
            guard !shouldSkip(file) else {
                skipped.append(snippet.path)
                continue
            }
            let text = """
            untracked file: \(snippet.path)\(snippet.truncated ? " (truncated)" : "")
            \(snippet.text)
            """
            chunks.append(GitDiffChunk(
                id: "untracked|\(snippet.path)",
                path: snippet.path,
                text: text,
                estimatedTokens: GitCommitMessageTokenEstimator.estimate(text),
                riskLabels: labels(for: snippet.path, analysis: analysis)
            ))
        }

        if chunks.isEmpty, !snapshot.diffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let text = String(snapshot.diffText.prefix(80_000))
            chunks.append(GitDiffChunk(
                id: "diff|fallback",
                path: "diff",
                text: text,
                estimatedTokens: GitCommitMessageTokenEstimator.estimate(text),
                riskLabels: analysis.riskLabels
            ))
        }

        return chunks
    }

    func skippedPaths(for snapshot: GitCommitMessageSnapshot) -> [String] {
        snapshot.files.filter(shouldSkip).map(\.path).sorted()
    }

    private func splitSection(_ section: String, path: String, riskLabels: [GitCommitMessageRiskLabel]) -> [GitDiffChunk] {
        let tokens = GitCommitMessageTokenEstimator.estimate(section)
        guard tokens > maxTokensPerChunk else {
            return [GitDiffChunk(id: "file|\(path)", path: path, text: section, estimatedTokens: tokens, riskLabels: riskLabels)]
        }

        var header: [String] = []
        var hunks: [[String]] = []
        var current: [String] = []
        var inHunk = false
        for line in section.components(separatedBy: "\n") {
            if line.hasPrefix("@@") {
                if !current.isEmpty { hunks.append(current) }
                current = [line]
                inHunk = true
            } else if inHunk {
                current.append(line)
            } else {
                header.append(line)
            }
        }
        if !current.isEmpty { hunks.append(current) }

        var output: [GitDiffChunk] = []
        var buffer = header
        var index = 1
        for hunk in hunks {
            let candidate = (buffer + hunk).joined(separator: "\n")
            if GitCommitMessageTokenEstimator.estimate(candidate) > maxTokensPerChunk, buffer.count > header.count {
                let text = buffer.joined(separator: "\n")
                output.append(GitDiffChunk(
                    id: "file|\(path)|\(index)",
                    path: path,
                    text: text,
                    estimatedTokens: GitCommitMessageTokenEstimator.estimate(text),
                    riskLabels: riskLabels
                ))
                index += 1
                buffer = header + hunk
            } else {
                buffer += hunk
            }
        }
        if buffer.count > header.count {
            let text = buffer.joined(separator: "\n")
            output.append(GitDiffChunk(
                id: "file|\(path)|\(index)",
                path: path,
                text: text,
                estimatedTokens: GitCommitMessageTokenEstimator.estimate(text),
                riskLabels: riskLabels
            ))
        }
        return output
    }

    private func labels(for path: String, analysis: GitCommitMessageAnalysis) -> [GitCommitMessageRiskLabel] {
        analysis.riskLabels.filter { $0.paths.isEmpty || $0.paths.contains(path) }
    }

    private func shouldSkip(_ file: GitCommitMessageFileChange) -> Bool {
        if file.isBinary { return true }
        let lower = file.path.lowercased()
        let ext = (file.path as NSString).pathExtension.lowercased()
        if file.churn > 8_000 { return true }
        if lower.contains(".generated.") || lower.contains("/generated/") || lower.contains("/vendor/") { return true }
        if ["png", "jpg", "jpeg", "gif", "webp", "pdf", "zip", "dmg", "xcarchive", "mov", "mp4"].contains(ext) { return true }
        if lower.hasSuffix("package-lock.json") || lower.hasSuffix("pnpm-lock.yaml") ||
            lower.hasSuffix("yarn.lock") || lower.hasSuffix("podfile.lock") {
            return true
        }
        return false
    }
}
