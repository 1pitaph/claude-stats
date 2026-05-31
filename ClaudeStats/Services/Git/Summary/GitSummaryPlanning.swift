import Foundation

struct GitChangeClassifier: Sendable {
    func classify(_ snapshot: GitSummarySnapshot) -> GitSummaryAnalysis {
        var collector = RiskCollector()
        let diffLower = snapshot.diffText.lowercased()

        for file in snapshot.files {
            classify(file: file, diffText: snapshot.diffText, collector: &collector)
        }

        if diffLower.contains("@mainactor") || diffLower.contains("sendable") || diffLower.contains("task {") || diffLower.contains("async ") || diffLower.contains("await ") {
            collector.add(.concurrency, title: "Concurrency", reason: "Diff touches async/concurrency primitives.", score: 5, path: nil)
        }
        if diffLower.contains("authorization") || diffLower.contains("bearer ") || diffLower.contains("jwt") || diffLower.contains("oauth") || diffLower.contains("keychain") {
            collector.add(.auth, title: "Auth/security", reason: "Diff touches auth or secret-handling terms.", score: 6, path: nil)
        }
        if hasPublicSignatureChange(snapshot.diffText) {
            collector.add(.api, title: "Public signature", reason: "Public/exported API signature changed.", score: 7, path: nil)
        }

        let labels = collector.labels.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.category.rawValue < $1.category.rawValue
        }
        return GitSummaryAnalysis(
            riskLabels: labels,
            riskScore: labels.reduce(0) { $0 + max($1.score, 0) },
            skippedPaths: []
        )
    }

    private func classify(file: GitSummaryFileChange, diffText: String, collector: inout RiskCollector) {
        let path = file.path
        let lower = path.lowercased()
        let ext = (path as NSString).pathExtension.lowercased()

        if file.isBinary {
            collector.add(.binary, title: "Binary", reason: "Binary file changed.", score: 1, path: path)
        }
        if file.status == .renamed || file.oldPath != nil {
            collector.add(.rename, title: "Rename", reason: "File was renamed or moved.", score: 1, path: path)
        }
        if file.churn >= 2_000 {
            collector.add(.large, title: "Large churn", reason: "File churn exceeds 2,000 changed lines.", score: 2, path: path)
        }
        if isGeneratedPath(lower) {
            collector.add(.generated, title: "Generated", reason: "Generated or vendored file changed.", score: 0, path: path)
        }
        if isDocumentationPath(lower, ext: ext) {
            collector.add(.docs, title: "Docs", reason: "Documentation changed.", score: 0, path: path)
        }
        if isTestPath(lower) {
            collector.add(.tests, title: "Tests", reason: "Test code changed.", score: 1, path: path)
        }
        if isDependencyPath(lower) {
            collector.add(.dependencies, title: "Dependencies", reason: "Dependency manifest or lockfile changed.", score: 4, path: path)
        }
        if isBuildPath(lower) {
            collector.add(.build, title: "Build config", reason: "Build, CI, signing, or project configuration changed.", score: 6, path: path)
        }
        if isReleasePath(lower) {
            collector.add(.release, title: "Release", reason: "Release, packaging, Sparkle, or appcast files changed.", score: 5, path: path)
        }
        if isSchemaPath(lower, ext: ext) {
            collector.add(.schema, title: "Schema", reason: "Schema, migration, model, or protocol file changed.", score: 7, path: path)
        }
        if isAPIPath(lower, ext: ext) {
            collector.add(.api, title: "API surface", reason: "API route, client, protocol, or exported interface file changed.", score: 6, path: path)
        }
        if isAuthPath(lower) {
            collector.add(.auth, title: "Auth/security", reason: "Auth, token, cookie, keychain, or permission path changed.", score: 7, path: path)
        }
        if isConcurrencyPath(lower) || fileDiff(for: path, in: diffText).lowercased().contains("sendable") {
            collector.add(.concurrency, title: "Concurrency", reason: "Concurrency-sensitive code changed.", score: 5, path: path)
        }
    }

    private func hasPublicSignatureChange(_ diff: String) -> Bool {
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("+") || line.hasPrefix("-") else { continue }
            let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
            let lower = text.lowercased()
            if lower.hasPrefix("public ") || lower.hasPrefix("open ") {
                if lower.contains(" func ") || lower.contains(" var ") || lower.contains(" let ") ||
                    lower.contains(" class ") || lower.contains(" struct ") || lower.contains(" enum ") ||
                    lower.contains(" protocol ") || lower.contains(" typealias ") ||
                    lower.hasPrefix("public func") || lower.hasPrefix("public var") ||
                    lower.hasPrefix("public struct") || lower.hasPrefix("open class") {
                    return true
                }
            }
            if lower.hasPrefix("export ") || lower.hasPrefix("export default ") {
                return true
            }
            if text.hasPrefix("func "), let name = text.split(separator: " ").dropFirst().first?.split(separator: "(").first,
               name.first?.isUppercase == true {
                return true
            }
        }
        return false
    }

    private func fileDiff(for path: String, in diffText: String) -> String {
        GitSummarySnapshotBuilder.splitDiffSections(diffText).first { section in
            section.contains(" b/\(path)") || section.contains("rename to \(path)")
        } ?? ""
    }

    private func isAPIPath(_ lower: String, ext: String) -> Bool {
        lower.contains("/api/") || lower.contains("api.") || lower.contains("client") ||
            lower.contains("endpoint") || lower.contains("route") || lower.contains("controller") ||
            lower.contains("protocol") || ["proto", "graphql", "thrift", "openapi", "wsdl"].contains(ext)
    }

    private func isSchemaPath(_ lower: String, ext: String) -> Bool {
        lower.contains("schema") || lower.contains("migration") || lower.contains("/migrations/") ||
            lower.contains("xcdatamodel") || lower.contains("prisma") || lower.contains("modelruntime") ||
            ["sql", "graphql", "proto", "avsc"].contains(ext)
    }

    private func isAuthPath(_ lower: String) -> Bool {
        lower.contains("auth") || lower.contains("oauth") || lower.contains("jwt") ||
            lower.contains("token") || lower.contains("keychain") || lower.contains("cookie") ||
            lower.contains("permission") || lower.contains("security") || lower.contains("credential")
    }

    private func isBuildPath(_ lower: String) -> Bool {
        lower == "package.swift" || lower == "project.yml" || lower.hasSuffix(".pbxproj") ||
            lower.contains(".xcodeproj/") || lower.contains(".github/workflows/") ||
            lower.contains("fastlane/") || lower.contains("dockerfile") ||
            lower.contains("makefile") || lower.contains("build.gradle") ||
            lower.contains("scripts/") || lower.hasSuffix(".xcconfig")
    }

    private func isReleasePath(_ lower: String) -> Bool {
        lower.contains("release") || lower.contains("appcast") || lower.contains("sparkle") ||
            lower.contains("notary") || lower.contains("codesign") || lower.contains("entitlements")
    }

    private func isConcurrencyPath(_ lower: String) -> Bool {
        lower.contains("actor") || lower.contains("concurrency") || lower.contains("thread") ||
            lower.contains("queue") || lower.contains("lock")
    }

    private func isDependencyPath(_ lower: String) -> Bool {
        lower == "package.resolved" || lower == "package.swift" || lower.hasSuffix("package-lock.json") ||
            lower.hasSuffix("pnpm-lock.yaml") || lower.hasSuffix("yarn.lock") ||
            lower.hasSuffix("gemfile.lock") || lower.hasSuffix("podfile.lock") ||
            lower.hasSuffix("go.mod") || lower.hasSuffix("go.sum") ||
            lower.hasSuffix("cargo.toml") || lower.hasSuffix("cargo.lock")
    }

    private func isTestPath(_ lower: String) -> Bool {
        lower.contains("test") || lower.contains("spec") || lower.contains("__tests__")
    }

    private func isDocumentationPath(_ lower: String, ext: String) -> Bool {
        lower.contains("readme") || lower.contains("/docs/") || ["md", "mdx", "rst", "txt"].contains(ext)
    }

    private func isGeneratedPath(_ lower: String) -> Bool {
        lower.contains(".generated.") || lower.contains("/generated/") ||
            lower.contains("/vendor/") || lower.contains("/pods/") ||
            lower.hasSuffix(".pb.swift") || lower.hasSuffix(".pb.go") ||
            lower.hasSuffix(".snapshots") || lower.contains("deriveddata")
    }
}

struct GitDiffChunker: Sendable {
    var maxTokensPerChunk: Int = 6_000

    func chunks(for snapshot: GitSummarySnapshot, analysis: GitSummaryAnalysis) -> [GitDiffChunk] {
        let filesByPath = Dictionary(uniqueKeysWithValues: snapshot.files.map { ($0.path, $0) })
        var chunks: [GitDiffChunk] = []
        var skipped: [String] = []

        for section in GitSummarySnapshotBuilder.splitDiffSections(snapshot.diffText) {
            let path = Self.path(for: section)
            guard !path.isEmpty else { continue }
            guard let file = filesByPath[path], !shouldSkip(file) else {
                skipped.append(path)
                continue
            }
            chunks.append(contentsOf: splitSection(section, path: path, riskLabels: labels(for: path, analysis: analysis)))
        }

        for snippet in snapshot.untrackedSnippets {
            let file = filesByPath[snippet.path] ?? GitSummaryFileChange(
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
                estimatedTokens: GitSummaryTokenEstimator.estimate(text),
                riskLabels: labels(for: snippet.path, analysis: analysis)
            ))
        }

        if chunks.isEmpty, !snapshot.diffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let text = String(snapshot.diffText.prefix(80_000))
            chunks.append(GitDiffChunk(
                id: "diff|fallback",
                path: "diff",
                text: text,
                estimatedTokens: GitSummaryTokenEstimator.estimate(text),
                riskLabels: analysis.riskLabels
            ))
        }

        return chunks
    }

    func skippedPaths(for snapshot: GitSummarySnapshot) -> [String] {
        snapshot.files.filter(shouldSkip).map(\.path).sorted()
    }

    private func splitSection(_ section: String, path: String, riskLabels: [GitSummaryRiskLabel]) -> [GitDiffChunk] {
        let tokens = GitSummaryTokenEstimator.estimate(section)
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
            if GitSummaryTokenEstimator.estimate(candidate) > maxTokensPerChunk, buffer.count > header.count {
                let text = buffer.joined(separator: "\n")
                output.append(GitDiffChunk(
                    id: "file|\(path)|\(index)",
                    path: path,
                    text: text,
                    estimatedTokens: GitSummaryTokenEstimator.estimate(text),
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
                estimatedTokens: GitSummaryTokenEstimator.estimate(text),
                riskLabels: riskLabels
            ))
        }
        return output
    }

    private func labels(for path: String, analysis: GitSummaryAnalysis) -> [GitSummaryRiskLabel] {
        analysis.riskLabels.filter { $0.paths.isEmpty || $0.paths.contains(path) }
    }

    private func shouldSkip(_ file: GitSummaryFileChange) -> Bool {
        if file.isBinary { return true }
        let lower = file.path.lowercased()
        let ext = (file.path as NSString).pathExtension.lowercased()
        if file.churn > 8_000 { return true }
        if lower.contains(".generated.") || lower.contains("/generated/") || lower.contains("/vendor/") { return true }
        if ["png", "jpg", "jpeg", "gif", "webp", "pdf", "zip", "dmg", "xcarchive", "mov", "mp4"].contains(ext) { return true }
        if lower.hasSuffix("package-lock.json") || lower.hasSuffix("pnpm-lock.yaml") || lower.hasSuffix("yarn.lock") || lower.hasSuffix("podfile.lock") {
            return true
        }
        return false
    }

    private static func path(for section: String) -> String {
        guard let first = section.components(separatedBy: "\n").first else { return "" }
        let parts = first.split(separator: " ")
        guard parts.count >= 4 else { return "" }
        var path = String(parts[3])
        if path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 {
            path = String(path.dropFirst().dropLast())
        }
        if path.hasPrefix("b/") { path = String(path.dropFirst(2)) }
        for line in section.components(separatedBy: "\n") where line.hasPrefix("rename to ") {
            return String(line.dropFirst("rename to ".count))
        }
        return path
    }
}

struct GitSummaryPlanner: Sendable {
    func plan(snapshot: GitSummarySnapshot, analysis: GitSummaryAnalysis, chunks: [GitDiffChunk]) -> GitSummaryPlan {
        let tokenEstimate = max(snapshot.tokenEstimate, chunks.reduce(0) { $0 + $1.estimatedTokens })
        let fileCount = snapshot.files.count
        let highRisk = analysis.riskScore >= 13 || analysis.hasVerifierTrigger
        let algorithm: GitSummaryAlgorithm
        let useVerifier: Bool
        let includeRepoContext: Bool

        if highRisk {
            algorithm = .mapReduceWithVerifier
            useVerifier = true
            includeRepoContext = true
        } else if tokenEstimate > 40_000 || fileCount > 20 || analysis.riskScore >= 8 {
            algorithm = .mapReduce
            useVerifier = false
            includeRepoContext = false
        } else if tokenEstimate >= 8_000 || analysis.riskScore >= 3 {
            algorithm = .fileLevel
            useVerifier = false
            includeRepoContext = false
        } else {
            algorithm = .singleShot
            useVerifier = false
            includeRepoContext = false
        }

        return GitSummaryPlan(
            algorithm: algorithm,
            useVerifier: useVerifier,
            includeRepoContext: includeRepoContext,
            tokenEstimate: tokenEstimate,
            fileCount: fileCount,
            riskScore: analysis.riskScore
        )
    }
}

private struct RiskCollector {
    private var storage: [GitSummaryRiskCategory: GitSummaryRiskLabel] = [:]

    var labels: [GitSummaryRiskLabel] { Array(storage.values) }

    mutating func add(_ category: GitSummaryRiskCategory, title: String, reason: String, score: Int, path: String?) {
        if var existing = storage[category] {
            existing.score = max(existing.score, score)
            if let path, !existing.paths.contains(path) {
                existing.paths.append(path)
                existing.paths.sort()
            }
            if !existing.reason.contains(reason) {
                existing.reason += " \(reason)"
            }
            storage[category] = existing
        } else {
            storage[category] = GitSummaryRiskLabel(
                category: category,
                title: title,
                reason: reason,
                score: score,
                paths: path.map { [$0] } ?? []
            )
        }
    }
}
