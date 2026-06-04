import Foundation

struct GitChangeClassifier: Sendable {
    func classify(_ snapshot: GitCommitMessageSnapshot) -> GitCommitMessageAnalysis {
        var collector = RiskCollector()
        let diffLower = snapshot.diffText.lowercased()

        for file in snapshot.files {
            classify(file: file, diffText: snapshot.diffText, collector: &collector)
        }

        if diffLower.contains("@mainactor") || diffLower.contains("sendable") || diffLower.contains("task {") {
            collector.add(.concurrency, title: "Concurrency", reason: "Diff touches async/concurrency primitives.", score: 5, path: nil)
        } else if diffLower.contains("async ") || diffLower.contains("await ") {
            collector.add(.concurrency, title: "Concurrency", reason: "Diff touches ordinary async/await usage.", score: 2, path: nil)
        }
        if diffLower.contains("authorization") || diffLower.contains("bearer ") || diffLower.contains("jwt") ||
            diffLower.contains("oauth") || diffLower.contains("keychain") {
            collector.add(.auth, title: "Auth/security", reason: "Diff touches auth or secret-handling terms.", score: 6, path: nil)
        }

        let labels = collector.labels.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.category.rawValue < $1.category.rawValue
        }
        return GitCommitMessageAnalysis(
            riskLabels: labels,
            riskScore: labels.reduce(0) { $0 + max($1.score, 0) },
            skippedPaths: []
        )
    }

    private func classify(file: GitCommitMessageFileChange, diffText: String, collector: inout RiskCollector) {
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
        if !isTestPath(lower), !isDocumentationPath(lower, ext: ext), !isGeneratedPath(lower),
           hasPublicSignatureChange(fileDiff(for: path, in: diffText)) {
            collector.add(.api, title: "Public signature", reason: "Public/exported API signature changed.", score: 6, path: path)
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
        GitDiffSectionParser.splitDiffSections(diffText).first { section in
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
            lower.hasSuffix(".xcconfig") || isBuildScriptPath(lower)
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

    private func isBuildScriptPath(_ lower: String) -> Bool {
        guard lower.contains("scripts/") else { return false }
        return lower.contains("release") || lower.contains("build") ||
            lower.contains("sign") || lower.contains("notary") ||
            lower.contains("ci")
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

private struct RiskCollector {
    private var storage: [GitCommitMessageRiskCategory: GitCommitMessageRiskLabel] = [:]

    var labels: [GitCommitMessageRiskLabel] { Array(storage.values) }

    mutating func add(_ category: GitCommitMessageRiskCategory, title: String, reason: String, score: Int, path: String?) {
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
            storage[category] = GitCommitMessageRiskLabel(
                category: category,
                title: title,
                reason: reason,
                score: score,
                paths: path.map { [$0] } ?? []
            )
        }
    }
}
