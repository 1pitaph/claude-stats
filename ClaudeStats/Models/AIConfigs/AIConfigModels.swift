import Foundation

enum AIConfigDocumentKind: String, CaseIterable, Sendable, Hashable, Identifiable {
    case instruction
    case providerConfig
    case plan
    case pluginConfig
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instruction: "Instructions"
        case .providerConfig: "Provider"
        case .plan: "Plans"
        case .pluginConfig: "Plugin Manifests"
        case .other: "Other"
        }
    }

    var singularDisplayName: String {
        switch self {
        case .instruction: "Instruction"
        case .providerConfig: "Provider Config"
        case .plan: "Plan"
        case .pluginConfig: "Plugin Manifest"
        case .other: "Config"
        }
    }

    var symbol: String {
        switch self {
        case .instruction: "doc.text"
        case .providerConfig: "slider.horizontal.3"
        case .plan: "checklist"
        case .pluginConfig: "puzzlepiece.extension"
        case .other: "doc"
        }
    }
}

enum AIConfigsFilter: String, CaseIterable, Sendable, Hashable, Identifiable {
    case all
    case instructions
    case provider
    case plans
    case plugins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .instructions: "Instructions"
        case .provider: "Provider"
        case .plans: "Plans"
        case .plugins: "Plugin Manifests"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .instructions: AIConfigDocumentKind.instruction.symbol
        case .provider: AIConfigDocumentKind.providerConfig.symbol
        case .plans: AIConfigDocumentKind.plan.symbol
        case .plugins: AIConfigDocumentKind.pluginConfig.symbol
        }
    }

    func matches(_ kind: AIConfigDocumentKind) -> Bool {
        switch self {
        case .all:
            true
        case .instructions:
            kind == .instruction
        case .provider:
            kind == .providerConfig
        case .plans:
            kind == .plan
        case .plugins:
            kind == .pluginConfig
        }
    }
}

enum AIConfigsSection: String, CaseIterable, Sendable, Hashable, Identifiable {
    case overview
    case instructions
    case provider
    case plans
    case plugins
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .instructions: "Instructions"
        case .provider: "Provider"
        case .plans: "Plans"
        case .plugins: "Plugin Manifests"
        case .diagnostics: "Diagnostics"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .instructions: AIConfigDocumentKind.instruction.symbol
        case .provider: AIConfigDocumentKind.providerConfig.symbol
        case .plans: AIConfigDocumentKind.plan.symbol
        case .plugins: AIConfigDocumentKind.pluginConfig.symbol
        case .diagnostics: "exclamationmark.triangle"
        }
    }

    var detailTitle: String {
        switch self {
        case .overview: "AI configs"
        case .instructions: "Instructions"
        case .provider: "Provider configs"
        case .plans: "Plans"
        case .plugins: "Plugin Manifests"
        case .diagnostics: "Diagnostics"
        }
    }

    var detailDescription: String {
        switch self {
        case .overview:
            "Review Claude and Codex configuration coverage, plan ownership, and file health."
        case .instructions:
            "Inspect global and project instruction files such as CLAUDE.md and AGENTS.md."
        case .provider:
            "Inspect provider settings and local configuration files without editing them."
        case .plans:
            "Review discovered markdown plans and their best-effort project assignment."
        case .plugins:
            "Inspect plugin manifests and configuration metadata discovered for AI tools."
        case .diagnostics:
            "Focus on malformed or skipped configuration files that need attention."
        }
    }

    var documentKind: AIConfigDocumentKind? {
        switch self {
        case .instructions: .instruction
        case .provider: .providerConfig
        case .plans: .plan
        case .plugins: .pluginConfig
        case .overview, .diagnostics: nil
        }
    }
}

enum AIConfigSourceLocation: Sendable, Hashable {
    case global
    case project(path: String)
    case planStore
    case pluginStore

    var id: String {
        switch self {
        case .global: "global"
        case .project(let path): "project:\(path)"
        case .planStore: "plans"
        case .pluginStore: "plugins"
        }
    }
}

enum AIConfigSourceTarget: Sendable, Hashable {
    case file
    case directory(extensions: Set<String>, maxDepth: Int)
}

struct AIConfigSource: Identifiable, Sendable, Hashable {
    let provider: ProviderKind
    let title: String
    let url: URL
    let kind: AIConfigDocumentKind
    let fileKind: ProviderConfigFileKind
    let location: AIConfigSourceLocation
    let target: AIConfigSourceTarget
    let isExpected: Bool

    var id: String {
        "\(provider.rawValue):\(location.id):\(url.path)"
    }

    init(
        provider: ProviderKind,
        title: String,
        url: URL,
        kind: AIConfigDocumentKind,
        fileKind: ProviderConfigFileKind,
        location: AIConfigSourceLocation,
        target: AIConfigSourceTarget = .file,
        isExpected: Bool = false
    ) {
        self.provider = provider
        self.title = title
        self.url = url
        self.kind = kind
        self.fileKind = fileKind
        self.location = location
        self.target = target
        self.isExpected = isExpected
    }
}

struct AIConfigContentStats: Sendable, Hashable {
    var headingCount: Int
    var wordCount: Int
    var uncheckedTaskCount: Int
    var checkedTaskCount: Int
    var todoMentions: Int
    var blockedMentions: Int
    var cancelledMentions: Int

    static let empty = AIConfigContentStats(
        headingCount: 0,
        wordCount: 0,
        uncheckedTaskCount: 0,
        checkedTaskCount: 0,
        todoMentions: 0,
        blockedMentions: 0,
        cancelledMentions: 0
    )
}

struct AIConfigDiagnostic: Identifiable, Sendable, Hashable {
    enum Severity: String, Sendable, Hashable {
        case info
        case warning
        case error
    }

    let id: String
    let severity: Severity
    let message: String
    let line: Int?
    let column: Int?

    var locationDisplay: String? {
        guard let line else { return nil }
        if let column { return "Line \(line), column \(column)" }
        return "Line \(line)"
    }
}

struct AIPlanStats: Sendable, Hashable {
    var total: Int
    var assigned: Int
    var unassigned: Int
    var uncheckedTasks: Int
    var checkedTasks: Int
    var todoMentions: Int
    var blockedMentions: Int
    var cancelledMentions: Int

    static let empty = AIPlanStats(
        total: 0,
        assigned: 0,
        unassigned: 0,
        uncheckedTasks: 0,
        checkedTasks: 0,
        todoMentions: 0,
        blockedMentions: 0,
        cancelledMentions: 0
    )
}

struct AIConfigDocument: Identifiable, Sendable, Hashable {
    let id: String
    let provider: ProviderKind
    let title: String
    let path: String
    let kind: AIConfigDocumentKind
    let fileKind: ProviderConfigFileKind
    let location: AIConfigSourceLocation
    let exists: Bool
    let isExpected: Bool
    let fileSize: Int64?
    let modifiedAt: Date?
    let contentPreview: String?
    let isPreviewTruncated: Bool
    let assignedProjectPath: String?
    let stats: AIConfigContentStats
    let diagnostics: [AIConfigDiagnostic]

    var displayPath: String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    var hasProblems: Bool {
        diagnostics.contains { $0.severity == .error || $0.severity == .warning }
    }

    var templateContent: String? {
        guard isExpected, !exists else { return nil }
        switch (provider, fileKind, title) {
        case (.claude, .json, _):
            return "{\n  \"permissions\": {\n    \"allow\": [],\n    \"deny\": []\n  }\n}\n"
        case (.claude, .markdown, _):
            return "# Project Instructions\n\nDescribe project conventions, commands, and review expectations here.\n"
        case (.codex, .toml, _):
            return "# Codex configuration\nmodel = \"gpt-5.3-codex\"\napproval_policy = \"on-request\"\nsandbox_mode = \"workspace-write\"\n"
        case (.codex, .markdown, _):
            return "# AGENTS.md\n\n## Build & Test\n\nDescribe the commands agents should run after code changes.\n"
        default:
            switch fileKind {
            case .json:
                return "{\n}\n"
            case .markdown:
                return "# Instructions\n\n"
            case .toml:
                return "# Configuration\n"
            case .text:
                return ""
            }
        }
    }

    var canCreateFromTemplate: Bool {
        templateContent != nil
    }
}

struct AIConfigSummary: Sendable, Hashable {
    var projectCount: Int
    var documentCount: Int
    var existingDocumentCount: Int
    var missingExpectedCount: Int
    var diagnosticCount: Int
    var errorCount: Int
    var planStats: AIPlanStats

    static let empty = AIConfigSummary(
        projectCount: 0,
        documentCount: 0,
        existingDocumentCount: 0,
        missingExpectedCount: 0,
        diagnosticCount: 0,
        errorCount: 0,
        planStats: .empty
    )
}

struct AIConfigProject: Identifiable, Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case global
        case project
        case unassigned
    }

    static let globalID = "global"
    static let unassignedID = "unassigned"

    let id: String
    let kind: Kind
    let name: String
    let path: String?
    let documents: [AIConfigDocument]
    let summary: AIConfigSummary
    let lastModified: Date?

    static func global(documents: [AIConfigDocument]) -> AIConfigProject {
        AIConfigProject(kind: .global, name: "Global", path: nil, documents: documents)
    }

    static func unassigned(documents: [AIConfigDocument]) -> AIConfigProject {
        AIConfigProject(kind: .unassigned, name: "Unassigned", path: nil, documents: documents)
    }

    init(kind: Kind, name: String, path: String?, documents: [AIConfigDocument]) {
        self.kind = kind
        self.name = name
        self.path = path
        self.documents = documents

        switch kind {
        case .global:
            id = Self.globalID
        case .unassigned:
            id = Self.unassignedID
        case .project:
            id = path ?? name
        }

        summary = AIConfigSummary.make(projects: [], documents: documents)
        lastModified = documents.compactMap(\.modifiedAt).max()
    }
}

struct AIConfigSnapshot: Sendable, Hashable {
    let projects: [AIConfigProject]
    let summary: AIConfigSummary
    let scannedAt: Date?

    static let empty = AIConfigSnapshot(projects: [], summary: .empty, scannedAt: nil)

    var globalProject: AIConfigProject? {
        projects.first { $0.kind == .global }
    }
}

extension AIConfigSummary {
    static func make(projects: [AIConfigProject], documents: [AIConfigDocument]? = nil) -> AIConfigSummary {
        let docs = documents ?? projects.flatMap(\.documents)
        let planDocs = docs.filter { $0.kind == .plan && $0.exists }
        let planStats = AIPlanStats(
            total: planDocs.count,
            assigned: planDocs.filter { $0.assignedProjectPath != nil }.count,
            unassigned: planDocs.filter { $0.assignedProjectPath == nil }.count,
            uncheckedTasks: planDocs.reduce(0) { $0 + $1.stats.uncheckedTaskCount },
            checkedTasks: planDocs.reduce(0) { $0 + $1.stats.checkedTaskCount },
            todoMentions: planDocs.reduce(0) { $0 + $1.stats.todoMentions },
            blockedMentions: planDocs.reduce(0) { $0 + $1.stats.blockedMentions },
            cancelledMentions: planDocs.reduce(0) { $0 + $1.stats.cancelledMentions }
        )
        return AIConfigSummary(
            projectCount: projects.filter { $0.kind == .project }.count,
            documentCount: docs.count,
            existingDocumentCount: docs.filter(\.exists).count,
            missingExpectedCount: docs.filter { !$0.exists && $0.isExpected }.count,
            diagnosticCount: docs.reduce(0) { $0 + $1.diagnostics.count },
            errorCount: docs.reduce(0) { total, doc in total + doc.diagnostics.filter { $0.severity == .error }.count },
            planStats: planStats
        )
    }
}

extension ProviderConfigFileKind {
    static func aiConfigKind(for url: URL) -> ProviderConfigFileKind {
        switch url.pathExtension.lowercased() {
        case "json", "jsonc":
            .json
        case "md", "markdown":
            .markdown
        case "toml":
            .toml
        default:
            .text
        }
    }
}
