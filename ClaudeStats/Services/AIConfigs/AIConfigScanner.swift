import Foundation

struct AIConfigScanner: Sendable {
    static let previewByteLimit = 256 * 1024

    let registry: ProviderRegistry

    init(registry: ProviderRegistry) {
        self.registry = registry
    }

    func scan(sessions: [Session]) async -> AIConfigSnapshot {
        let providers = registry.providers
        return await Task.detached(priority: .utility) {
            Self.scanSync(providers: providers, sessions: sessions, scannedAt: .now)
        }.value
    }

    static func scanSync(
        providers: [any Provider],
        sessions: [Session],
        scannedAt: Date = .now
    ) -> AIConfigSnapshot {
        let projectSeeds = makeProjectSeeds(from: sessions)
        var allDocuments: [AIConfigDocument] = []

        for provider in providers {
            allDocuments += documents(from: provider.globalAIConfigSources(), projects: projectSeeds)
            for project in projectSeeds {
                allDocuments += documents(
                    from: provider.projectAIConfigSources(for: URL(fileURLWithPath: project.path, isDirectory: true)),
                    projects: projectSeeds
                )
            }
        }

        let groupedProjects = makeProjects(from: allDocuments, projectSeeds: projectSeeds)
        return AIConfigSnapshot(
            projects: groupedProjects,
            summary: AIConfigSummary.make(projects: groupedProjects),
            scannedAt: scannedAt
        )
    }

    static func stats(forMarkdown content: String) -> AIConfigContentStats {
        var stats = AIConfigContentStats.empty
        var inFence = false
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        for rawLine in lines {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }

            guard !inFence else { continue }

            if trimmed.hasPrefix("#") {
                stats.headingCount += 1
            }

            let lower = trimmed.lowercased()
            if lower.hasPrefix("- [ ]") || lower.hasPrefix("* [ ]") {
                stats.uncheckedTaskCount += 1
            } else if lower.hasPrefix("- [x]") || lower.hasPrefix("* [x]") {
                stats.checkedTaskCount += 1
            }

            stats.todoMentions += mentionCount(in: lower, tokens: ["todo"])
            stats.blockedMentions += mentionCount(in: lower, tokens: ["blocked", "blocker"])
            stats.cancelledMentions += mentionCount(in: lower, tokens: ["cancelled", "canceled"])
        }

        stats.wordCount = content
            .split { !$0.isLetter && !$0.isNumber }
            .count
        return stats
    }

    private static func documents(from sources: [AIConfigSource], projects: [ProjectSeed]) -> [AIConfigDocument] {
        sources.flatMap { source -> [AIConfigDocument] in
            switch source.target {
            case .file:
                if let document = document(from: source, projects: projects) {
                    return [document]
                }
                return []
            case .directory(let extensions, let maxDepth):
                return expandedSources(from: source, extensions: extensions, maxDepth: maxDepth)
                    .compactMap { document(from: $0, projects: projects) }
            }
        }
    }

    private static func document(from source: AIConfigSource, projects: [ProjectSeed]) -> AIConfigDocument? {
        let url = source.url
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        let exists = values?.isRegularFile == true

        guard exists || source.isExpected else { return nil }

        let size = values?.fileSize.map(Int64.init)
        let modifiedAt = values?.contentModificationDate
        var content: String?
        var truncated = false
        var diagnostics: [AIConfigDiagnostic] = []

        if exists {
            if let size, size > previewByteLimit {
                truncated = true
                diagnostics.append(
                    AIConfigDiagnostic(
                        id: "\(source.id):large",
                        severity: .warning,
                        message: "Large file skipped for preview.",
                        line: nil,
                        column: nil
                    )
                )
            } else {
                do {
                    content = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    diagnostics.append(
                        AIConfigDiagnostic(
                            id: "\(source.id):read",
                            severity: .error,
                            message: "Could not read file: \(error.localizedDescription)",
                            line: nil,
                            column: nil
                        )
                    )
                }
            }
        }

        if let content {
            diagnostics += syntaxDiagnostics(for: content, kind: source.fileKind, sourceID: source.id)
        }

        let contentStats: AIConfigContentStats = {
            guard let content else { return .empty }
            switch source.fileKind {
            case .markdown:
                return stats(forMarkdown: content)
            case .json, .toml, .text:
                var stats = AIConfigContentStats.empty
                stats.wordCount = content.split { !$0.isLetter && !$0.isNumber }.count
                return stats
            }
        }()

        let assignedProjectPath = assignedProjectPath(for: source, content: content, projects: projects)

        return AIConfigDocument(
            id: source.id,
            provider: source.provider,
            title: source.title,
            path: url.path,
            kind: source.kind,
            fileKind: source.fileKind,
            location: source.location,
            exists: exists,
            isExpected: source.isExpected,
            fileSize: size,
            modifiedAt: modifiedAt,
            contentPreview: content,
            isPreviewTruncated: truncated,
            assignedProjectPath: assignedProjectPath,
            stats: contentStats,
            diagnostics: diagnostics
        )
    }

    private static func expandedSources(
        from source: AIConfigSource,
        extensions: Set<String>,
        maxDepth: Int
    ) -> [AIConfigSource] {
        let root = source.url
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sources: [AIConfigSource] = []
        let rootPath = root.standardizedFileURL.path

        for case let fileURL as URL in enumerator {
            let relativeDepth = depth(of: fileURL, relativeTo: rootPath)
            if relativeDepth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                continue
            }

            guard values?.isRegularFile == true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard extensions.isEmpty || extensions.contains(ext) else { continue }

            sources.append(
                AIConfigSource(
                    provider: source.provider,
                    title: fileURL.lastPathComponent,
                    url: fileURL,
                    kind: source.kind,
                    fileKind: ProviderConfigFileKind.aiConfigKind(for: fileURL),
                    location: source.location,
                    target: .file,
                    isExpected: false
                )
            )
        }

        return sources.sorted { lhs, rhs in
            lhs.url.path.localizedCaseInsensitiveCompare(rhs.url.path) == .orderedAscending
        }
    }

    private static func makeProjects(from documents: [AIConfigDocument], projectSeeds: [ProjectSeed]) -> [AIConfigProject] {
        var projects: [AIConfigProject] = []

        let globalDocuments = sortedDocuments(
            documents.filter { document in
                switch document.location {
                case .global, .pluginStore:
                    true
                case .project, .planStore:
                    false
                }
            }
        )
        if !globalDocuments.isEmpty {
            projects.append(.global(documents: globalDocuments))
        }

        for seed in projectSeeds {
            let projectDocuments = sortedDocuments(
                documents.filter { document in
                    switch document.location {
                    case .project(let path):
                        normalizedPath(path) == seed.path
                    case .planStore:
                        document.assignedProjectPath == seed.path
                    case .global, .pluginStore:
                        false
                    }
                }
            )
            projects.append(
                AIConfigProject(kind: .project, name: seed.name, path: seed.path, documents: projectDocuments)
            )
        }

        let unassignedPlans = sortedDocuments(
            documents.filter { $0.location == .planStore && $0.assignedProjectPath == nil }
        )
        if !unassignedPlans.isEmpty {
            projects.append(.unassigned(documents: unassignedPlans))
        }

        return projects
    }

    private static func syntaxDiagnostics(
        for content: String,
        kind: ProviderConfigFileKind,
        sourceID: String
    ) -> [AIConfigDiagnostic] {
        ConfigurationEditorService.diagnosticsSync(for: content, kind: kind).map { diagnostic in
            let severity: AIConfigDiagnostic.Severity
            switch diagnostic.severity {
            case .info:
                severity = .info
            case .warning:
                severity = .warning
            case .error:
                severity = .error
            }
            return AIConfigDiagnostic(
                id: "\(sourceID):\(diagnostic.id)",
                severity: severity,
                message: diagnostic.message,
                line: diagnostic.line,
                column: diagnostic.column
            )
        }
    }

    private static func assignedProjectPath(
        for source: AIConfigSource,
        content: String?,
        projects: [ProjectSeed]
    ) -> String? {
        guard source.location == .planStore else {
            if case .project(let path) = source.location {
                return normalizedPath(path)
            }
            return nil
        }

        let sourcePath = normalizedPath(source.url.path)
        if let direct = projects.first(where: { sourcePath.hasPrefix($0.path + "/") }) {
            return direct.path
        }

        if let content {
            let lowerContent = content.lowercased()
            if let match = projects.first(where: { lowerContent.contains($0.path.lowercased()) }) {
                return match.path
            }
        }

        let fileToken = searchableToken(source.url.deletingPathExtension().lastPathComponent)
        let uniqueNameMatches = projects.filter { project in
            fileToken.contains(project.nameToken) || fileToken.contains(project.pathToken)
        }
        return uniqueNameMatches.count == 1 ? uniqueNameMatches[0].path : nil
    }

    private static func makeProjectSeeds(from sessions: [Session]) -> [ProjectSeed] {
        var byPath: [String: ProjectSeed] = [:]

        for session in sessions {
            guard let cwd = session.cwd, !cwd.isEmpty else { continue }
            let path = normalizedPath(cwd)
            guard !path.isEmpty else { continue }
            let name = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
            let seed = ProjectSeed(path: path, name: name.isEmpty ? session.projectDisplayName : name)
            if byPath[path] == nil {
                byPath[path] = seed
            }
        }

        return byPath.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func sortedDocuments(_ documents: [AIConfigDocument]) -> [AIConfigDocument] {
        documents.sorted { lhs, rhs in
            let lhsKind = kindSortRank(lhs.kind)
            let rhsKind = kindSortRank(rhs.kind)
            if lhsKind != rhsKind { return lhsKind < rhsKind }
            let lhsProvider = providerSortRank(lhs.provider)
            let rhsProvider = providerSortRank(rhs.provider)
            if lhsProvider != rhsProvider { return lhsProvider < rhsProvider }
            if lhs.exists != rhs.exists { return lhs.exists && !rhs.exists }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func providerSortRank(_ provider: ProviderKind) -> Int {
        ProviderKind.allCases.firstIndex(of: provider) ?? Int.max
    }

    private static func kindSortRank(_ kind: AIConfigDocumentKind) -> Int {
        switch kind {
        case .instruction: 0
        case .providerConfig: 1
        case .plan: 2
        case .pluginConfig: 3
        case .other: 4
        }
    }

    private static func depth(of url: URL, relativeTo rootPath: String) -> Int {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return Int.max }
        let relative = path.dropFirst(rootPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return 0 }
        return relative.split(separator: "/").count
    }

    private static func mentionCount(in lowercasedLine: String, tokens: [String]) -> Int {
        tokens.reduce(0) { count, token in
            count + lowercasedLine.components(separatedBy: token).count - 1
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func searchableToken(_ value: String) -> String {
        value.lowercased()
            .map { character in character.isLetter || character.isNumber ? character : "-" }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" {
                    return
                }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private struct ProjectSeed: Sendable, Hashable {
        let path: String
        let name: String

        var nameToken: String { searchableToken(name) }
        var pathToken: String { searchableToken(path) }
    }
}
