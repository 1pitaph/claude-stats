import Foundation

enum SkillsWorkspaceTab: String, CaseIterable, Identifiable, Sendable, Hashable {
    case installed
    case discover
    case curated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .installed: "Installed"
        case .discover: "Discover"
        case .curated: "Curated"
        }
    }

    var symbol: String {
        switch self {
        case .installed: "externaldrive"
        case .discover: "magnifyingglass"
        case .curated: "sparkles"
        }
    }
}

enum SkillsDetailTab: String, CaseIterable, Identifiable, Sendable, Hashable {
    case overview
    case skill
    case files
    case market

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .skill: "SKILL.md"
        case .files: "Files"
        case .market: "Market"
        }
    }
}

enum SkillsScanMode: Sendable, Hashable {
    case indexOnly
    case fullHash
}

enum SkillScope: Sendable, Hashable {
    case global
    case project(path: String)
    case plugin
    case system
    case custom

    var id: String {
        switch self {
        case .global: "global"
        case .project(let path): "project:\(path)"
        case .plugin: "plugin"
        case .system: "system"
        case .custom: "custom"
        }
    }

    var displayName: String {
        switch self {
        case .global: "Global"
        case .project: "Project"
        case .plugin: "Plugin"
        case .system: "System"
        case .custom: "Custom"
        }
    }

    var detail: String? {
        switch self {
        case .project(let path): path
        case .global, .plugin, .system, .custom: nil
        }
    }
}

enum SkillScopeFilter: String, CaseIterable, Identifiable, Sendable, Hashable {
    case all
    case global
    case project
    case plugin
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All scopes"
        case .global: "Global"
        case .project: "Project"
        case .plugin: "Plugins"
        case .system: "System"
        }
    }

    func matches(_ scope: SkillScope) -> Bool {
        switch (self, scope) {
        case (.all, _): true
        case (.global, .global): true
        case (.project, .project): true
        case (.plugin, .plugin): true
        case (.system, .system): true
        default: false
        }
    }
}

struct SkillProviderDefinition: Identifiable, Sendable, Hashable {
    let id: String
    let displayName: String
    let symbol: String

    init(id: String, displayName: String, symbol: String = "sparkles") {
        self.id = id
        self.displayName = displayName
        self.symbol = symbol
    }
}

struct SkillRootDefinition: Identifiable, Sendable, Hashable {
    let provider: SkillProviderDefinition
    let scope: SkillScope
    let url: URL
    let maxDepth: Int
    let allowsHiddenDirectories: Bool

    var id: String { "\(provider.id):\(scope.id):\(url.path)" }

    init(
        provider: SkillProviderDefinition,
        scope: SkillScope,
        url: URL,
        maxDepth: Int = 5,
        allowsHiddenDirectories: Bool = true
    ) {
        self.provider = provider
        self.scope = scope
        self.url = url
        self.maxDepth = maxDepth
        self.allowsHiddenDirectories = allowsHiddenDirectories
    }
}

struct SkillPluginMetadata: Sendable, Hashable {
    let id: String
    let displayName: String
    let version: String?
    let category: String?
    let author: String?
    let description: String?
    let enabled: Bool?
}

struct SkillFrontmatter: Sendable, Hashable {
    var name: String?
    var description: String?
    var version: String?
    var license: String?
    var compatibility: String?
    var allowedTools: String?
    var effort: String?
    var creator: String?

    func value(for key: String) -> String? {
        switch key {
        case "name": name
        case "description": description
        case "version": version
        case "license": license
        case "compatibility": compatibility
        case "allowedTools": allowedTools
        case "effort": effort
        case "creator", "author": creator
        default: nil
        }
    }
}

struct SkillFolderStats: Sendable, Hashable {
    var fileCount: Int
    var referencesCount: Int
    var assetsCount: Int
    var scriptsCount: Int
    var templatesCount: Int
    var tokenCount: Int
    var byteCount: Int64

    static let empty = SkillFolderStats(
        fileCount: 0,
        referencesCount: 0,
        assetsCount: 0,
        scriptsCount: 0,
        templatesCount: 0,
        tokenCount: 0,
        byteCount: 0
    )
}

struct SkillFileEntry: Identifiable, Sendable, Hashable {
    let path: String
    let byteCount: Int64?
    let modifiedAt: Date?

    var id: String { path }
}

struct SkillFileRowModel: Identifiable, Sendable, Hashable {
    let id: String
    let path: String
    let byteCountText: String?

    init(entry: SkillFileEntry) {
        id = entry.id
        path = entry.path
        byteCountText = entry.byteCount.map { Format.bytes(Int($0)) }
    }
}

struct SkillMarkdownDocument: Identifiable, Sendable, Hashable {
    let id: String
    let contentHash: String
    let text: String

    init(id: String, contentHash: String?, text: String) {
        self.id = id
        self.contentHash = contentHash ?? Self.fallbackHash(text)
        self.text = text
    }

    private static func fallbackHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

struct SkillFactModel: Identifiable, Sendable, Hashable {
    let id: String
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.id = label
        self.label = label
        self.value = value
    }
}

struct LocalSkillItem: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let folderName: String
    let description: String?
    let providerID: String
    let providerName: String
    let providerSymbol: String
    let scope: SkillScope
    let rootPath: String
    let folderPath: String
    let skillMarkdownPath: String
    let realPath: String
    let isSymlink: Bool
    let symlinkTarget: String?
    let frontmatter: SkillFrontmatter
    let plugin: SkillPluginMetadata?
    let stats: SkillFolderStats
    let files: [SkillFileEntry]
    let modifiedAt: Date?
    let contentHash: String?
    let skillMarkdown: String?

    var normalizedName: String {
        Self.normalizedName(name)
    }

    var displayDescription: String {
        guard let description, !description.isEmpty else { return "No description in SKILL.md." }
        return description
    }

    var displayPath: String {
        folderPath.abbreviatingHomeDirectory
    }

    static func normalizedName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

struct LocalSkillGroup: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let description: String?
    let skills: [LocalSkillItem]
    let providers: [String]
    let scopes: [SkillScope]

    init(skills: [LocalSkillItem]) {
        let sorted = skills.sorted { lhs, rhs in
            if lhs.providerName != rhs.providerName {
                return lhs.providerName.localizedCaseInsensitiveCompare(rhs.providerName) == .orderedAscending
            }
            return lhs.folderPath.localizedCaseInsensitiveCompare(rhs.folderPath) == .orderedAscending
        }
        self.skills = sorted
        self.name = sorted.first?.name ?? "Untitled Skill"
        self.description = sorted.first(where: { !($0.description ?? "").isEmpty })?.description
        self.id = sorted.first?.normalizedName ?? UUID().uuidString
        self.providers = Array(Set(sorted.map(\.providerName))).sorted()
        self.scopes = Array(Set(sorted.map(\.scope))).sorted { $0.displayName < $1.displayName }
    }

    var primarySkill: LocalSkillItem? {
        skills.first
    }

    var installedCopyCount: Int {
        skills.count
    }
}

struct LocalSkillRowModel: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let description: String
    let copyCount: Int
    let providerBadges: [String]

    init(group: LocalSkillGroup) {
        id = group.id
        name = group.name
        description = group.description ?? "No description"
        copyCount = group.installedCopyCount
        providerBadges = Array(group.providers.prefix(3))
    }
}

struct LocalSkillActionModel: Sendable, Hashable {
    let folderPath: String
    let skillMarkdownPath: String
}

struct LocalSkillCopyRowModel: Identifiable, Sendable, Hashable {
    let id: String
    let providerName: String
    let providerSymbol: String
    let scopeName: String
    let displayPath: String
    let isSymlink: Bool

    init(skill: LocalSkillItem) {
        id = skill.id
        providerName = skill.providerName
        providerSymbol = skill.providerSymbol
        scopeName = skill.scope.displayName
        displayPath = skill.displayPath
        isSymlink = skill.isSymlink
    }
}

struct LocalSkillDetailModel: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let copyCount: Int
    let fileCount: Int
    let tokenCount: Int
    let primaryFacts: [SkillFactModel]
    let installedCopies: [LocalSkillCopyRowModel]
    let files: [SkillFileRowModel]
    let actions: LocalSkillActionModel?

    init(group: LocalSkillGroup) {
        let primary = group.primarySkill
        id = group.id
        title = group.name
        subtitle = group.description ?? "Local SKILL.md directory"
        copyCount = group.installedCopyCount
        fileCount = primary?.stats.fileCount ?? 0
        tokenCount = primary?.stats.tokenCount ?? 0
        installedCopies = group.skills.map(LocalSkillCopyRowModel.init(skill:))
        files = primary?.files.map(SkillFileRowModel.init(entry:)) ?? []
        actions = primary.map {
            LocalSkillActionModel(folderPath: $0.folderPath, skillMarkdownPath: $0.skillMarkdownPath)
        }

        var facts: [SkillFactModel] = []
        if let primary {
            facts.append(SkillFactModel("Provider", value: primary.providerName))
            facts.append(SkillFactModel("Scope", value: primary.scope.displayName))
            facts.append(SkillFactModel("Path", value: primary.displayPath))
            if let creator = primary.frontmatter.creator {
                facts.append(SkillFactModel("Creator", value: creator))
            }
            if let version = primary.frontmatter.version {
                facts.append(SkillFactModel("Version", value: version))
            }
            if let plugin = primary.plugin {
                facts.append(SkillFactModel("Plugin", value: plugin.displayName))
                facts.append(SkillFactModel("Plugin ID", value: plugin.id))
                if let version = plugin.version {
                    facts.append(SkillFactModel("Plugin Version", value: version))
                }
                if let enabled = plugin.enabled {
                    facts.append(SkillFactModel("Plugin Enabled", value: enabled ? "Yes" : "No"))
                }
            }
        }
        primaryFacts = facts
    }
}

struct SkillsSummary: Sendable, Hashable {
    var skillCount: Int
    var groupCount: Int
    var providerCount: Int
    var projectRootCount: Int
    var pluginSkillCount: Int

    static let empty = SkillsSummary(
        skillCount: 0,
        groupCount: 0,
        providerCount: 0,
        projectRootCount: 0,
        pluginSkillCount: 0
    )
}

struct SkillsSnapshot: Sendable, Hashable {
    let skills: [LocalSkillItem]
    let groups: [LocalSkillGroup]
    let providers: [SkillProviderDefinition]
    let summary: SkillsSummary
    let scannedAt: Date?
    let scanMode: SkillsScanMode

    static let empty = SkillsSnapshot(
        skills: [],
        groups: [],
        providers: [],
        summary: .empty,
        scannedAt: nil,
        scanMode: .indexOnly
    )
}

enum SkillInstallState: Sendable, Hashable {
    case notInstalled
    case installed
    case possiblyInstalled
    case outOfDate

    var title: String {
        switch self {
        case .notInstalled: "Not installed"
        case .installed: "Installed"
        case .possiblyInstalled: "Possibly installed"
        case .outOfDate: "Update available"
        }
    }
}

struct RemoteSkillSummary: Identifiable, Sendable, Hashable, Decodable {
    let id: String
    let slug: String?
    let name: String
    let source: String?
    let sourceType: String?
    let installs: Int?
    let installURL: String?
    let url: String?
    let isDuplicate: Bool

    var installCommand: String? {
        guard let installURL, !installURL.isEmpty else { return nil }
        return "npx skills add \(installURL)"
    }

    var displaySource: String {
        source ?? sourceType ?? "skills.sh"
    }

    init(
        id: String,
        slug: String? = nil,
        name: String,
        source: String? = nil,
        sourceType: String? = nil,
        installs: Int? = nil,
        installURL: String? = nil,
        url: String? = nil,
        isDuplicate: Bool = false
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.source = source
        self.sourceType = sourceType
        self.installs = installs
        self.installURL = installURL
        self.url = url
        self.isDuplicate = isDuplicate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let id = try container.decodeString(for: "id")
        let slug = container.decodeStringIfPresent(for: "slug")
        let name = container.decodeStringIfPresent(for: "name")
            ?? container.decodeStringIfPresent(for: "title")
            ?? slug
            ?? id
        self.init(
            id: id,
            slug: slug,
            name: name,
            source: container.decodeStringIfPresent(for: "source"),
            sourceType: container.decodeStringIfPresent(for: "sourceType"),
            installs: container.decodeIntIfPresent(for: "installs"),
            installURL: container.decodeStringIfPresent(for: "installUrl"),
            url: container.decodeStringIfPresent(for: "url"),
            isDuplicate: container.decodeBoolIfPresent(for: "isDuplicate") ?? false
        )
    }
}

struct RemoteSkillRowModel: Identifiable, Sendable, Hashable {
    let skill: RemoteSkillSummary
    let installState: SkillInstallState

    var id: String { skill.id }
}

struct CuratedSkillOwnerRowModel: Identifiable, Sendable, Hashable {
    let owner: String
    let totalInstalls: Int?
    let skills: [RemoteSkillRowModel]

    var id: String { owner }
}

struct RemoteSkillActionModel: Sendable, Hashable {
    let installCommand: String?
    let remoteURLString: String?
}

struct RemoteSkillAuditRowModel: Identifiable, Sendable, Hashable {
    let id: String
    let provider: String
    let status: String
    let summary: String?
    let auditedAtText: String?
    let riskLevel: String?

    init(entry: SkillsShAuditEntry) {
        id = entry.id
        provider = entry.provider
        status = entry.status
        summary = entry.summary
        auditedAtText = entry.auditedAt.map(Format.shortDate)
        riskLevel = entry.riskLevel
    }
}

struct RemoteSkillDetailModel: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let installsText: String
    let fileCount: Int
    let installStateTitle: String
    let facts: [SkillFactModel]
    let installCommand: String?
    let files: [SkillFileRowModel]
    let audits: [RemoteSkillAuditRowModel]
    let markdownDocument: SkillMarkdownDocument?
    let isDetailLoading: Bool
    let actions: RemoteSkillActionModel

    init(skill: RemoteSkillSummary, bundle: SkillRemoteDetailBundle?, installState: SkillInstallState, isDetailLoading: Bool) {
        id = skill.id
        title = skill.name
        subtitle = skill.displaySource
        installsText = skill.installs.map(String.init) ?? "-"
        let fileEntries = bundle?.fileEntries ?? []
        files = fileEntries.map(SkillFileRowModel.init(entry:))
        fileCount = fileEntries.count
        installStateTitle = installState.title
        installCommand = skill.installCommand
        audits = bundle?.audit?.audits.map(RemoteSkillAuditRowModel.init(entry:)) ?? []
        self.isDetailLoading = isDetailLoading

        let remoteURLString = skill.url ?? skill.installURL
        actions = RemoteSkillActionModel(
            installCommand: skill.installCommand,
            remoteURLString: remoteURLString
        )
        markdownDocument = bundle?.skillMarkdown.map {
            SkillMarkdownDocument(
                id: "remote:\(skill.id)",
                contentHash: bundle?.detail?.hash,
                text: $0
            )
        }

        var facts = [SkillFactModel("ID", value: skill.id)]
        if let source = skill.source {
            facts.append(SkillFactModel("Source", value: source))
        }
        if let installURL = skill.installURL {
            facts.append(SkillFactModel("Install URL", value: installURL))
        }
        if let hash = bundle?.detail?.hash {
            facts.append(SkillFactModel("Hash", value: hash))
        }
        self.facts = facts
    }
}

struct RemoteSkillFile: Identifiable, Sendable, Hashable, Decodable {
    let path: String
    let contents: String?

    var id: String { path }
}

struct RemoteSkillDetail: Identifiable, Sendable, Hashable, Decodable {
    let id: String
    let source: String?
    let slug: String?
    let installs: Int?
    let hash: String?
    let files: [RemoteSkillFile]

    var skillMarkdown: String? {
        files.first { $0.path == "SKILL.md" }?.contents
    }

    var displayName: String {
        skillMarkdown.flatMap { SkillFrontmatterParser.parse($0).frontmatter.name } ?? slug ?? id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        id = try container.decodeString(for: "id")
        source = container.decodeStringIfPresent(for: "source")
        slug = container.decodeStringIfPresent(for: "slug")
        installs = container.decodeIntIfPresent(for: "installs")
        hash = container.decodeStringIfPresent(for: "hash")
        files = (try? container.decode([RemoteSkillFile].self, forKey: DynamicCodingKey("files"))) ?? []
    }
}

struct SkillsShCuratedOwner: Identifiable, Sendable, Hashable, Decodable {
    let owner: String
    let totalInstalls: Int?
    let featuredRepo: String?
    let featuredSkill: String?
    let skills: [RemoteSkillSummary]

    var id: String { owner }
}

struct SkillsShAuditEntry: Identifiable, Sendable, Hashable, Decodable {
    let provider: String
    let slug: String?
    let status: String
    let summary: String?
    let auditedAt: Date?
    let riskLevel: String?
    let categories: [String]

    var id: String { slug ?? provider }

    private enum CodingKeys: String, CodingKey {
        case provider, slug, status, summary, auditedAt, riskLevel, categories
    }

    init(
        provider: String,
        slug: String?,
        status: String,
        summary: String?,
        auditedAt: Date?,
        riskLevel: String?,
        categories: [String]
    ) {
        self.provider = provider
        self.slug = slug
        self.status = status
        self.summary = summary
        self.auditedAt = auditedAt
        self.riskLevel = riskLevel
        self.categories = categories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        status = try container.decode(String.self, forKey: .status)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        auditedAt = try container.decodeIfPresent(Date.self, forKey: .auditedAt)
        riskLevel = try container.decodeIfPresent(String.self, forKey: .riskLevel)
        categories = (try? container.decodeIfPresent([String].self, forKey: .categories)) ?? []
    }
}

struct SkillsShAuditReport: Identifiable, Sendable, Hashable, Decodable {
    let id: String
    let source: String?
    let slug: String?
    let audits: [SkillsShAuditEntry]
}

struct SkillRemoteDetailBundle: Sendable, Hashable {
    var detail: RemoteSkillDetail?
    var audit: SkillsShAuditReport?
    var skillMarkdown: String?
    var fileEntries: [SkillFileEntry]

    init(
        detail: RemoteSkillDetail? = nil,
        audit: SkillsShAuditReport? = nil,
        skillMarkdown: String? = nil,
        fileEntries: [SkillFileEntry]? = nil
    ) {
        self.detail = detail
        self.audit = audit
        self.skillMarkdown = skillMarkdown ?? detail?.skillMarkdown
        self.fileEntries = fileEntries ?? detail?.files.map {
            SkillFileEntry(path: $0.path, byteCount: Int64($0.contents?.utf8.count ?? 0), modifiedAt: nil)
        } ?? []
    }
}

extension String {
    var abbreviatingHomeDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard hasPrefix(home) else { return self }
        return "~" + dropFirst(home.count)
    }
}

struct DynamicCodingKey: CodingKey, Sendable {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where K == DynamicCodingKey {
    func decodeString(for key: String) throws -> String {
        try decode(String.self, forKey: DynamicCodingKey(key))
    }

    func decodeStringIfPresent(for key: String) -> String? {
        try? decodeIfPresent(String.self, forKey: DynamicCodingKey(key))
    }

    func decodeIntIfPresent(for key: String) -> Int? {
        if let intValue = try? decodeIfPresent(Int.self, forKey: DynamicCodingKey(key)) {
            return intValue
        }
        if let stringValue = decodeStringIfPresent(for: key) {
            return Int(stringValue)
        }
        return nil
    }

    func decodeBoolIfPresent(for key: String) -> Bool? {
        if let boolValue = try? decodeIfPresent(Bool.self, forKey: DynamicCodingKey(key)) {
            return boolValue
        }
        if let stringValue = decodeStringIfPresent(for: key) {
            switch stringValue.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }
}
