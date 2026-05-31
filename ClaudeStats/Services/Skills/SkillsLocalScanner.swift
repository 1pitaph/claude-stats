import CryptoKit
import Foundation

protocol SkillsLocalScanning: Sendable {
    func scan(sessions: [Session], mode: SkillsScanMode) async -> SkillsSnapshot
}

struct SkillsLocalScanner: SkillsLocalScanning, Sendable {
    private let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func scan(sessions: [Session], mode: SkillsScanMode = .fullHash) async -> SkillsSnapshot {
        let homeDirectory = homeDirectory
        return await Task.detached(priority: .utility) {
            let roots = Self.defaultRoots(homeDirectory: homeDirectory, sessions: sessions)
            return Self.scanSync(
                roots: roots,
                codexPluginCacheURL: homeDirectory.appendingPathComponent(".codex/plugins/cache", isDirectory: true),
                claudeMarketplaceURL: homeDirectory.appendingPathComponent(".claude/plugins/marketplaces", isDirectory: true),
                codexConfigURL: homeDirectory.appendingPathComponent(".codex/config.toml"),
                scannedAt: .now,
                mode: mode
            )
        }.value
    }

    static func scanSync(
        roots: [SkillRootDefinition],
        codexPluginCacheURL: URL? = nil,
        claudeMarketplaceURL: URL? = nil,
        codexConfigURL: URL? = nil,
        scannedAt: Date = .now,
        mode: SkillsScanMode = .fullHash
    ) -> SkillsSnapshot {
        var skills: [LocalSkillItem] = []
        for root in roots {
            skills += scanSkillDirectories(
                root: root,
                plugin: nil,
                mode: mode
            )
        }

        if let codexPluginCacheURL {
            skills += scanCodexPluginCache(root: codexPluginCacheURL, configURL: codexConfigURL, mode: mode)
        }

        if let claudeMarketplaceURL {
            let provider = SkillProviderDefinition(
                id: "claude-plugin",
                displayName: "Claude Plugin",
                symbol: AppIcon.Skill.file
            )
            let root = SkillRootDefinition(
                provider: provider,
                scope: .plugin,
                url: claudeMarketplaceURL,
                maxDepth: 9,
                allowsHiddenDirectories: false
            )
            skills += scanSkillDirectories(root: root, plugin: nil, mode: mode)
        }

        let deduped = dedupeByRealPath(skills)
        let groups = Dictionary(grouping: deduped, by: \.normalizedName)
            .values
            .map(LocalSkillGroup.init(skills:))
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        var providerMap: [String: SkillProviderDefinition] = [:]
        for skill in deduped {
            providerMap[skill.providerID] = SkillProviderDefinition(
                id: skill.providerID,
                displayName: skill.providerName,
                symbol: skill.providerSymbol
            )
        }
        let providers = providerMap
            .values
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        let projectRootCount = Set(roots.compactMap { root -> String? in
            if case .project(let path) = root.scope { return path }
            return nil
        }).count

        let summary = SkillsSummary(
            skillCount: deduped.count,
            groupCount: groups.count,
            providerCount: providers.count,
            projectRootCount: projectRootCount,
            pluginSkillCount: deduped.filter { $0.scope == .plugin }.count
        )
        return SkillsSnapshot(
            skills: deduped,
            groups: groups,
            providers: providers,
            summary: summary,
            scannedAt: scannedAt,
            scanMode: mode
        )
    }

    static func defaultRoots(homeDirectory: URL, sessions: [Session]) -> [SkillRootDefinition] {
        var roots: [SkillRootDefinition] = []

        func home(_ path: String) -> URL {
            homeDirectory.appendingPathComponent(path, isDirectory: true)
        }

        func append(_ provider: SkillProviderDefinition, _ scope: SkillScope, _ url: URL, maxDepth: Int = 5) {
            roots.append(SkillRootDefinition(provider: provider, scope: scope, url: url, maxDepth: maxDepth))
        }

        let codex = SkillProviderDefinition(id: "codex", displayName: "Codex", symbol: "chevron.left.forwardslash.chevron.right")
        let claude = SkillProviderDefinition(id: "claude", displayName: "Claude", symbol: "sparkles")
        let agents = SkillProviderDefinition(id: "agents", displayName: "Agents", symbol: "person.2")
        let openCode = SkillProviderDefinition(id: "opencode", displayName: "OpenCode", symbol: "curlybraces")
        let gemini = SkillProviderDefinition(id: "gemini", displayName: "Gemini", symbol: "sparkle")
        let cursor = SkillProviderDefinition(id: "cursor", displayName: "Cursor", symbol: "cursorarrow")
        let copilot = SkillProviderDefinition(id: "copilot", displayName: "GitHub Copilot", symbol: "ellipsis.curlybraces")
        let windsurf = SkillProviderDefinition(id: "windsurf", displayName: "Windsurf", symbol: "wind")
        let antigravity = SkillProviderDefinition(id: "antigravity", displayName: "Antigravity", symbol: "arrow.up.and.down.and.arrow.left.and.right")
        let amp = SkillProviderDefinition(id: "amp", displayName: "Amp", symbol: "bolt")
        let aider = SkillProviderDefinition(id: "aider", displayName: "Aider", symbol: "hammer")
        let cline = SkillProviderDefinition(id: "cline", displayName: "Cline", symbol: "terminal")
        let roo = SkillProviderDefinition(id: "roo", displayName: "Roo Code", symbol: "shippingbox")
        let `continue` = SkillProviderDefinition(id: "continue", displayName: "Continue", symbol: "play")
        let zed = SkillProviderDefinition(id: "zed", displayName: "Zed", symbol: "z.square")
        let augment = SkillProviderDefinition(id: "augment", displayName: "Augment", symbol: "wand.and.stars")
        let pi = SkillProviderDefinition(id: "pi", displayName: "Pi", symbol: "pi")
        let hermes = SkillProviderDefinition(id: "hermes", displayName: "Hermes", symbol: "paperplane")
        let openClaw = SkillProviderDefinition(id: "openclaw", displayName: "OpenClaw", symbol: "hand.raised")

        append(codex, .global, home(".codex/skills"))
        append(codex, .global, home(".codex/skills/public"))
        append(claude, .global, home(".claude/skills"))
        append(agents, .global, home(".agents/skills"))
        append(openCode, .global, home(".config/opencode/skills"))
        append(gemini, .global, home(".gemini/skills"))
        append(cursor, .global, home(".cursor/rules"))
        append(copilot, .global, home(".github/instructions"))
        append(windsurf, .global, home(".windsurf/rules"))
        append(antigravity, .global, home(".antigravity/skills"))
        append(amp, .global, home(".amp/skills"))
        append(aider, .global, home(".aider/skills"))
        append(cline, .global, home(".cline/skills"))
        append(roo, .global, home(".roo/skills"))
        append(`continue`, .global, home(".continue/skills"))
        append(zed, .global, home(".zed/skills"))
        append(augment, .global, home(".augment/skills"))
        append(pi, .global, home(".pi/skills"))
        append(hermes, .global, home(".hermes/skills"))
        append(openClaw, .global, home(".openclaw/skills"))

        let projectPaths = Set(
            sessions
                .compactMap(\.cwd)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path }
        )

        for path in projectPaths.sorted() {
            let projectURL = URL(fileURLWithPath: path, isDirectory: true)
            let scope = SkillScope.project(path: path)
            append(codex, scope, projectURL.appendingPathComponent(".codex/skills", isDirectory: true))
            append(codex, scope, projectURL.appendingPathComponent(".codex/skills/public", isDirectory: true))
            append(claude, scope, projectURL.appendingPathComponent(".claude/skills", isDirectory: true))
            append(agents, scope, projectURL.appendingPathComponent(".agents/skills", isDirectory: true))
            append(openCode, scope, projectURL.appendingPathComponent(".opencode/skills", isDirectory: true))
            append(gemini, scope, projectURL.appendingPathComponent(".gemini/skills", isDirectory: true))
            append(cursor, scope, projectURL.appendingPathComponent(".cursor/rules", isDirectory: true))
            append(copilot, scope, projectURL.appendingPathComponent(".github/instructions", isDirectory: true))
            append(windsurf, scope, projectURL.appendingPathComponent(".windsurf/rules", isDirectory: true))
            append(antigravity, scope, projectURL.appendingPathComponent(".antigravity/skills", isDirectory: true))
            append(amp, scope, projectURL.appendingPathComponent(".amp/skills", isDirectory: true))
            append(aider, scope, projectURL.appendingPathComponent(".aider/skills", isDirectory: true))
            append(cline, scope, projectURL.appendingPathComponent(".cline/skills", isDirectory: true))
            append(roo, scope, projectURL.appendingPathComponent(".roo/skills", isDirectory: true))
            append(`continue`, scope, projectURL.appendingPathComponent(".continue/skills", isDirectory: true))
            append(zed, scope, projectURL.appendingPathComponent(".zed/skills", isDirectory: true))
            append(augment, scope, projectURL.appendingPathComponent(".augment/skills", isDirectory: true))
        }

        return roots
    }

    // MARK: - Scan helpers

    private static func scanSkillDirectories(
        root: SkillRootDefinition,
        plugin: SkillPluginMetadata?,
        mode: SkillsScanMode
    ) -> [LocalSkillItem] {
        guard directoryExists(root.url) else { return [] }

        var output: [LocalSkillItem] = []
        var stack: [(url: URL, depth: Int)] = [(root.url, 0)]
        var visited: Set<String> = []

        while let current = stack.popLast() {
            let isSymlink = isSymbolicLink(current.url)
            let visitKey = isSymlink ? current.url.standardizedFileURL.path : resolvedPath(current.url)
            guard visited.insert(visitKey).inserted else { continue }

            if current.url.appendingPathComponent("SKILL.md").isReadableRegularFile {
                if let item = makeSkill(from: current.url, root: root, plugin: plugin, mode: mode) {
                    output.append(item)
                }
                continue
            }

            guard !isSymlink else { continue }
            guard current.depth < root.maxDepth else { continue }
            for child in directoryChildren(current.url) {
                let name = child.lastPathComponent
                if shouldSkipDirectory(name: name, allowsHiddenDirectories: root.allowsHiddenDirectories) {
                    continue
                }
                if isDirectoryOrDirectorySymlink(child) {
                    stack.append((child, current.depth + 1))
                }
            }
        }

        return output.sorted { lhs, rhs in
            lhs.folderPath.localizedCaseInsensitiveCompare(rhs.folderPath) == .orderedAscending
        }
    }

    private static func makeSkill(
        from folderURL: URL,
        root: SkillRootDefinition,
        plugin: SkillPluginMetadata?,
        mode: SkillsScanMode
    ) -> LocalSkillItem? {
        let skillURL = folderURL.appendingPathComponent("SKILL.md")
        guard let markdown = try? String(contentsOf: skillURL, encoding: .utf8) else { return nil }

        let parsed = SkillFrontmatterParser.parse(markdown)
        let folderName = folderURL.lastPathComponent
        let name = parsed.frontmatter.name?.nilIfBlank ?? folderName
        let description = parsed.frontmatter.description?.nilIfBlank ?? parsed.fallbackDescription?.nilIfBlank
        let values = try? folderURL.resourceValues(forKeys: [
            .contentModificationDateKey,
        ])
        let attributes = try? FileManager.default.attributesOfItem(atPath: folderURL.path)
        let symlinkDestination = try? FileManager.default.destinationOfSymbolicLink(atPath: folderURL.path)
        let isSymlink = symlinkDestination != nil
            || (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
        let realPath = resolvedPath(folderURL)
        let files = collectFiles(in: folderURL)
        let stats = folderStats(files: files, markdown: markdown)
        let hash = mode == .fullHash ? folderHash(folderURL: folderURL, files: files) : nil
        let id = "\(root.provider.id):\(root.scope.id):\(realPath)"

        return LocalSkillItem(
            id: id,
            name: name,
            folderName: folderName,
            description: description,
            providerID: root.provider.id,
            providerName: root.provider.displayName,
            providerSymbol: root.provider.symbol,
            scope: root.scope,
            rootPath: root.url.path,
            folderPath: folderURL.path,
            skillMarkdownPath: skillURL.path,
            realPath: realPath,
            isSymlink: isSymlink,
            symlinkTarget: symlinkDestination ?? (isSymlink ? realPath : nil),
            frontmatter: parsed.frontmatter,
            plugin: plugin,
            stats: stats,
            files: files,
            modifiedAt: values?.contentModificationDate ?? files.compactMap(\.modifiedAt).max(),
            contentHash: hash,
            skillMarkdown: nil
        )
    }

    private static func collectFiles(in folderURL: URL) -> [SkillFileEntry] {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let rootPath = folderURL.path
        var files: [SkillFileEntry] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == ".git" {
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            let relative = relativePath(url.path, rootPath: rootPath)
            files.append(
                SkillFileEntry(
                    path: relative,
                    byteCount: values?.fileSize.map(Int64.init),
                    modifiedAt: values?.contentModificationDate
                )
            )
        }
        return files.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private static func folderStats(files: [SkillFileEntry], markdown: String) -> SkillFolderStats {
        SkillFolderStats(
            fileCount: files.count,
            referencesCount: files.filter { $0.path.hasPrefix("references/") }.count,
            assetsCount: files.filter { $0.path.hasPrefix("assets/") }.count,
            scriptsCount: files.filter { $0.path.hasPrefix("scripts/") }.count,
            templatesCount: files.filter { $0.path.hasPrefix("templates/") }.count,
            tokenCount: markdown.split { $0.isWhitespace || $0.isNewline }.count,
            byteCount: files.compactMap(\.byteCount).reduce(0, +)
        )
    }

    private static func folderHash(folderURL: URL, files: [SkillFileEntry]) -> String? {
        var hasher = SHA256()
        var hashedAnyFile = false
        for file in files {
            let url = folderURL.appendingPathComponent(file.path)
            guard let data = try? Data(contentsOf: url) else { continue }
            hashedAnyFile = true
            hasher.update(data: Data(file.path.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: data)
            hasher.update(data: Data([0]))
        }
        guard hashedAnyFile else { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func scanCodexPluginCache(root: URL, configURL: URL?, mode: SkillsScanMode) -> [LocalSkillItem] {
        guard directoryExists(root) else { return [] }
        let enabledMap = codexPluginEnabledMap(configURL: configURL)
        var output: [LocalSkillItem] = []
        let provider = SkillProviderDefinition(
            id: "codex-plugin",
            displayName: "Codex Plugin",
            symbol: AppIcon.Skill.file
        )

        for marketplace in directoryChildren(root) where isDirectoryOrDirectorySymlink(marketplace) {
            for pluginDir in directoryChildren(marketplace) where isDirectoryOrDirectorySymlink(pluginDir) {
                guard let versionDir = latestCodexPluginVersion(in: pluginDir) else { continue }
                let manifest = parseCodexPluginManifest(versionDir.appendingPathComponent(".codex-plugin/plugin.json"))
                let pluginID = "\(marketplace.lastPathComponent)/\(pluginDir.lastPathComponent)"
                let metadata = SkillPluginMetadata(
                    id: pluginID,
                    displayName: manifest.displayName ?? pluginDir.lastPathComponent,
                    version: manifest.version ?? versionDir.lastPathComponent,
                    category: manifest.category,
                    author: manifest.author,
                    description: manifest.description,
                    enabled: enabledMap[pluginID] ?? enabledMap[pluginDir.lastPathComponent]
                )
                let skillsRoot = versionDir.appendingPathComponent("skills", isDirectory: true)
                let rootDefinition = SkillRootDefinition(
                    provider: provider,
                    scope: .plugin,
                    url: skillsRoot,
                    maxDepth: 4,
                    allowsHiddenDirectories: false
                )
                output += scanSkillDirectories(root: rootDefinition, plugin: metadata, mode: mode)
            }
        }

        return output
    }

    private static func latestCodexPluginVersion(in pluginDir: URL) -> URL? {
        let candidates = directoryChildren(pluginDir)
            .filter { isDirectoryOrDirectorySymlink($0) }
            .filter { $0.appendingPathComponent(".codex-plugin/plugin.json").isReadableRegularFile }
        return candidates.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
        }.first
    }

    private static func parseCodexPluginManifest(_ url: URL) -> (
        displayName: String?,
        version: String?,
        category: String?,
        author: String?,
        description: String?
    ) {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil, nil, nil, nil)
        }
        let interface = object["interface"] as? [String: Any]
        return (
            (interface?["displayName"] as? String) ?? object["name"] as? String,
            object["version"] as? String,
            object["category"] as? String,
            object["author"] as? String,
            (object["shortDescription"] as? String) ?? object["description"] as? String
        )
    }

    private static func codexPluginEnabledMap(configURL: URL?) -> [String: Bool] {
        guard let configURL,
              let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return [:]
        }

        var currentPlugin: String?
        var values: [String: Bool] = [:]
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[plugins.") && line.hasSuffix("]") {
                currentPlugin = line
                    .dropFirst("[plugins.".count)
                    .dropLast()
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            } else if line.hasPrefix("enabled"),
                      let currentPlugin,
                      let value = line.components(separatedBy: "=").dropFirst().first?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased() {
                values[currentPlugin] = value == "true"
            }
        }
        return values
    }

    private static func dedupeByRealPath(_ skills: [LocalSkillItem]) -> [LocalSkillItem] {
        var seen: Set<String> = []
        var output: [LocalSkillItem] = []
        for skill in skills.sorted(by: skillSort) {
            guard seen.insert(skill.realPath).inserted else { continue }
            output.append(skill)
        }
        return output.sorted(by: skillSort)
    }

    private static func skillSort(_ lhs: LocalSkillItem, _ rhs: LocalSkillItem) -> Bool {
        if lhs.isSymlink != rhs.isSymlink {
            return !lhs.isSymlink
        }
        if lhs.name != rhs.name {
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhs.folderPath.localizedCaseInsensitiveCompare(rhs.folderPath) == .orderedAscending
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func directoryChildren(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )) ?? []
    }

    private static func isDirectoryOrDirectorySymlink(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            return true
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private static func shouldSkipDirectory(name: String, allowsHiddenDirectories: Bool) -> Bool {
        if name == ".git" || name == "node_modules" { return true }
        if !allowsHiddenDirectories && name.hasPrefix(".") { return true }
        return false
    }

    private static func relativePath(_ path: String, rootPath: String) -> String {
        guard path.hasPrefix(rootPath + "/") else { return (path as NSString).lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func resolvedPath(_ url: URL) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(url.path, &buffer) != nil {
            return String(cString: buffer)
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

struct SkillFrontmatterParser {
    static func parse(_ markdown: String) -> (
        frontmatter: SkillFrontmatter,
        fallbackDescription: String?
    ) {
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return (SkillFrontmatter(), fallbackDescription(in: lines, from: 0))
        }

        guard let endIndex = lines.dropFirst().firstIndex(where: {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed == "---" || trimmed == "..."
        }) else {
            return (SkillFrontmatter(), fallbackDescription(in: lines, from: 0))
        }

        let map = parseFrontmatterLines(Array(lines[1..<endIndex]))
        return (
            SkillFrontmatter(
                name: map["name"],
                description: map["description"],
                version: map["version"],
                license: map["license"],
                compatibility: map["compatibility"],
                allowedTools: map["allowedtools"],
                effort: map["effort"],
                creator: map["creator"] ?? map["author"]
            ),
            fallbackDescription(in: lines, from: endIndex + 1)
        )
    }

    private static func parseFrontmatterLines(_ lines: [String]) -> [String: String] {
        var map: [String: String] = [:]
        var currentKey: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            if let separator = trimmed.firstIndex(of: ":"),
               !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                let rawKey = String(trimmed[..<separator])
                let key = canonicalKey(rawKey)
                var value = String(trimmed[trimmed.index(after: separator)...])
                    .trimmingCharacters(in: .whitespaces)
                if value == "|" || value == ">" {
                    value = ""
                }
                map[key] = cleanScalar(value)
                currentKey = key
                continue
            }

            guard let currentKey else { continue }
            let continuation = trimmed.hasPrefix("- ")
                ? String(trimmed.dropFirst(2))
                : trimmed
            let clean = cleanScalar(continuation)
            guard !clean.isEmpty else { continue }
            if let existing = map[currentKey], !existing.isEmpty {
                map[currentKey] = existing + ", " + clean
            } else {
                map[currentKey] = clean
            }
        }

        return map
    }

    private static func canonicalKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func cleanScalar(_ value: String) -> String {
        var output = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.hasPrefix("[") && output.hasSuffix("]") {
            output = String(output.dropFirst().dropLast())
        }
        output = output.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        return output
    }

    private static func fallbackDescription(in lines: [String], from startIndex: Int) -> String? {
        for line in lines.dropFirst(startIndex) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  !trimmed.hasPrefix("```") else {
                continue
            }
            return trimmed
        }
        return nil
    }
}

private extension URL {
    var isReadableRegularFile: Bool {
        let values = try? resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true && FileManager.default.isReadableFile(atPath: path)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
