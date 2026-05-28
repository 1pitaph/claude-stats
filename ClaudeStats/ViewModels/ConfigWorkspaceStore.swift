import Foundation
import Observation

@MainActor
@Observable
final class ConfigWorkspaceStore {
    let apiProviders: APIProviderSwitcherViewModel
    let cliEnvironment: CLIEnvironmentViewModel
    let aiConfigs: AIConfigsViewModel
    let skills: SkillsStore
    let configurationProfiles: ConfigurationProfilesViewModel?

    var section: ConfigWorkspaceSection = .overview
    var filesSection: ConfigFilesSection = .instructions
    var filesSearchText = ""
    var diagnosticsSearchText = ""
    var lastActionMessage: String?

    init(
        apiProviders: APIProviderSwitcherViewModel,
        cliEnvironment: CLIEnvironmentViewModel,
        aiConfigs: AIConfigsViewModel,
        skills: SkillsStore,
        configurationProfiles: ConfigurationProfilesViewModel? = nil
    ) {
        self.apiProviders = apiProviders
        self.cliEnvironment = cliEnvironment
        self.aiConfigs = aiConfigs
        self.skills = skills
        self.configurationProfiles = configurationProfiles
    }

    var counts: ConfigWorkspaceCounts {
        ConfigWorkspaceCounts(
            providerCount: providerCount,
            configFileCount: aiConfigs.snapshot.summary.existingDocumentCount + skills.snapshot.skills.count,
            skillCount: skills.snapshot.summary.groupCount,
            profileCount: configurationProfiles?.library.profiles.count ?? 0,
            backupCount: configurationProfiles?.backups.count ?? 0,
            diagnosticCount: diagnostics.count
        )
    }

    var providerCount: Int {
        apiProviders.library.cliProviders.count
    }

    var showsSearch: Bool {
        switch section {
        case .files, .diagnostics: true
        case .overview, .providers, .profiles: false
        }
    }

    var searchPlaceholder: String {
        switch section {
        case .files: "Search files"
        case .diagnostics: "Search diagnostics"
        case .overview, .providers, .profiles: ""
        }
    }

    var activeSearchText: String {
        get {
            switch section {
            case .files:
                filesSearchText
            case .diagnostics:
                diagnosticsSearchText
            case .overview, .providers, .profiles:
                ""
            }
        }
        set {
            switch section {
            case .files:
                filesSearchText = newValue
            case .diagnostics:
                diagnosticsSearchText = newValue
            case .overview, .providers, .profiles:
                break
            }
        }
    }

    var activeTitle: String {
        if section == .files {
            return filesSection.detailTitle
        }
        return section.detailTitle
    }

    var activeDescription: String {
        if section == .files {
            return filesSection.detailDescription
        }
        return section.detailDescription
    }

    var isLoadingActiveSection: Bool {
        switch section {
        case .providers:
            apiProviders.isWorking || cliEnvironment.isLoading
        case .files:
            aiConfigs.isLoading
        case .profiles:
            configurationProfiles?.isLoading == true || configurationProfiles?.isWorking == true
        case .diagnostics:
            aiConfigs.isLoading || cliEnvironment.isLoading || skills.isScanning || skills.isRemoteLoading || configurationProfiles?.isLoading == true
        case .overview:
            aiConfigs.isLoading || cliEnvironment.isLoading || skills.isScanning || apiProviders.isWorking || configurationProfiles?.isLoading == true
        }
    }

    var diagnostics: [ConfigDiagnosticItem] {
        var items: [ConfigDiagnosticItem] = []
        items.append(contentsOf: fileDiagnostics())
        items.append(contentsOf: providerDiagnostics())
        items.append(contentsOf: environmentDiagnostics())
        items.append(contentsOf: profileDiagnostics())
        items.append(contentsOf: skillDiagnostics())
        return items.sorted { lhs, rhs in
            let lhsRank = severityRank(lhs.severity)
            let rhsRank = severityRank(rhs.severity)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.source.title != rhs.source.title { return lhs.source.title < rhs.source.title }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var filteredDiagnostics: [ConfigDiagnosticItem] {
        let query = normalizedQuery(diagnosticsSearchText)
        guard !query.isEmpty else { return diagnostics }
        return diagnostics.filter { item in
            item.title.lowercased().contains(query)
                || item.message.lowercased().contains(query)
                || item.source.title.lowercased().contains(query)
                || item.severity.title.lowercased().contains(query)
                || (item.detail?.lowercased().contains(query) ?? false)
        }
    }

    func select(_ nextSection: ConfigWorkspaceSection) {
        section = nextSection
    }

    func selectFileSection(_ nextSection: ConfigFilesSection) {
        filesSection = nextSection
        section = .files
    }

    @discardableResult
    func migrateLegacyMainPage(rawValue: String) -> Bool {
        switch rawValue {
        case "configurations":
            section = .providers
            return true
        case "skills":
            section = .files
            filesSection = .skillFiles
            return true
        default:
            return false
        }
    }

    func loadIfNeeded(sessions: [Session], keyStorageMode: APIProviderKeyStorageMode) async {
        await apiProviders.loadIfNeeded(keyStorageMode: keyStorageMode)
        await cliEnvironment.loadIfNeeded()
        await aiConfigs.loadIfNeeded(sessions: sessions)
        await skills.loadIfNeeded(sessions: sessions)
        await configurationProfiles?.loadIfNeeded()
        await configurationProfiles?.refreshScopeOptions(from: sessions)
        await configurationProfiles?.reloadBackups()
    }

    func refreshActiveSection(sessions: [Session], keyStorageMode: APIProviderKeyStorageMode) async {
        switch section {
        case .overview:
            await refreshAll(sessions: sessions, keyStorageMode: keyStorageMode)
        case .providers:
            await apiProviders.reload(keyStorageMode: keyStorageMode)
            await cliEnvironment.refresh()
        case .files:
            await aiConfigs.reload(sessions: sessions)
            await skills.reloadLocal(sessions: sessions)
        case .profiles:
            await configurationProfiles?.reload()
            await configurationProfiles?.refreshScopeOptions(from: sessions)
            await configurationProfiles?.reloadBackups()
        case .diagnostics:
            await refreshAll(sessions: sessions, keyStorageMode: keyStorageMode)
        }
    }

    func refreshAll(sessions: [Session], keyStorageMode: APIProviderKeyStorageMode) async {
        await apiProviders.reload(keyStorageMode: keyStorageMode)
        await cliEnvironment.refresh()
        await aiConfigs.reload(sessions: sessions)
        await skills.reloadLocal(sessions: sessions)
        await configurationProfiles?.reload()
        await configurationProfiles?.refreshScopeOptions(from: sessions)
        await configurationProfiles?.reloadBackups()
    }

    func fileCount(for section: ConfigFilesSection) -> Int {
        if section == .skillFiles {
            return filteredSkillFiles.count
        }
        return aiConfigs.count(for: section.aiConfigSection, query: filesSearchText)
    }

    var filteredSkillFiles: [LocalSkillItem] {
        let query = normalizedQuery(filesSearchText)
        let skillItems = self.skills.snapshot.skills.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard !query.isEmpty else { return skillItems }
        return skillItems.filter { skill in
            skill.name.lowercased().contains(query)
                || skill.folderPath.lowercased().contains(query)
                || skill.providerName.lowercased().contains(query)
                || skill.displayDescription.lowercased().contains(query)
        }
    }

    func createMissingDocument(_ document: AIConfigDocument) async {
        guard let template = document.templateContent, !document.exists else { return }
        do {
            try await Task.detached(priority: .utility) {
                let url = URL(fileURLWithPath: document.path, isDirectory: false)
                guard !FileManager.default.fileExists(atPath: url.path) else {
                    throw CocoaError(.fileWriteFileExists)
                }
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try template.write(to: url, atomically: true, encoding: .utf8)
            }.value
            lastActionMessage = "Created \(document.title)."
        } catch {
            lastActionMessage = error.localizedDescription
        }
    }

    func relatedPluginSkills(for document: AIConfigDocument) -> [ConfigRelatedSkill] {
        guard document.kind == .pluginConfig else { return [] }

        let candidateKeys = manifestCandidateKeys(for: document)
        let rootURL = manifestRootURL(for: document)
        let rootPath = rootURL?.standardizedFileURL.path

        return skills.snapshot.skills
            .filter { skill in
                guard let plugin = skill.plugin else { return false }
                let pluginKeys = [
                    normalizedIdentity(plugin.id),
                    normalizedIdentity(plugin.displayName),
                ]
                if pluginKeys.contains(where: { candidateKeys.contains($0) }) {
                    return true
                }
                guard let rootPath else { return false }
                let skillPath = URL(fileURLWithPath: skill.folderPath).standardizedFileURL.path
                return skillPath == rootPath || skillPath.hasPrefix(rootPath + "/")
            }
            .sorted {
                if $0.name != $1.name {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.folderPath.localizedCaseInsensitiveCompare($1.folderPath) == .orderedAscending
            }
            .map(ConfigRelatedSkill.init(skill:))
    }

    private func fileDiagnostics() -> [ConfigDiagnosticItem] {
        allDocuments.flatMap { document -> [ConfigDiagnosticItem] in
            var items: [ConfigDiagnosticItem] = []
            let filesSection = fileSection(for: document.kind)
            if !document.exists, document.isExpected {
                items.append(
                    ConfigDiagnosticItem(
                        id: "files:missing:\(document.id)",
                        severity: .warning,
                        source: .files,
                        title: "Missing expected file",
                        message: "\(document.title) is not present.",
                        detail: document.displayPath,
                        targetSection: .files,
                        targetFilesSection: filesSection
                    )
                )
            }

            items.append(contentsOf: document.diagnostics.enumerated().map { offset, diagnostic in
                let location = diagnostic.locationDisplay.map { "\(document.displayPath) · \($0)" } ?? document.displayPath
                return ConfigDiagnosticItem(
                    id: "files:diagnostic:\(document.id):\(diagnostic.id):\(offset)",
                    severity: ConfigDiagnosticSeverity(aiSeverity: diagnostic.severity),
                    source: .files,
                    title: document.title,
                    message: diagnostic.message,
                    detail: location,
                    targetSection: .files,
                    targetFilesSection: filesSection
                )
            })
            return items
        }
    }

    private func providerDiagnostics() -> [ConfigDiagnosticItem] {
        guard let lastError = apiProviders.lastError, !lastError.isEmpty else { return [] }
        return [
            ConfigDiagnosticItem(
                id: "providers:last-error",
                severity: .error,
                source: .providers,
                title: "Provider switcher error",
                message: lastError,
                detail: nil,
                targetSection: .providers,
                targetFilesSection: nil
            ),
        ]
    }

    private func environmentDiagnostics() -> [ConfigDiagnosticItem] {
        var items = cliEnvironment.conflicts.map { conflict in
            ConfigDiagnosticItem(
                id: "environment:conflict:\(conflict.id)",
                severity: .warning,
                source: .environment,
                title: "Environment variable conflict",
                message: "\(conflict.varName) may override \(conflict.cli.shortName) provider settings.",
                detail: conflict.sourceDescription,
                targetSection: .providers,
                targetFilesSection: nil
            )
        }

        items.append(contentsOf: cliEnvironment.statuses.values.compactMap { status in
            if status.isOutdated {
                return ConfigDiagnosticItem(
                    id: "environment:outdated:\(status.cli.rawValue)",
                    severity: .warning,
                    source: .environment,
                    title: "\(status.cli.shortName) CLI is outdated",
                    message: "Installed \(status.version ?? "unknown"), latest \(status.latestVersion ?? "unknown").",
                    detail: status.executablePath,
                    targetSection: .providers,
                    targetFilesSection: nil
                )
            }
            guard !status.isInstalled else { return nil }
            return ConfigDiagnosticItem(
                id: "environment:missing:\(status.cli.rawValue)",
                severity: .warning,
                source: .environment,
                title: "\(status.cli.shortName) CLI unavailable",
                message: status.error ?? "CLI is not installed or not executable.",
                detail: status.diagnostic ?? status.executablePath,
                targetSection: .providers,
                targetFilesSection: nil
            )
        })

        if let lastError = cliEnvironment.lastError, !lastError.isEmpty {
            items.append(
                ConfigDiagnosticItem(
                    id: "environment:last-error",
                    severity: .error,
                    source: .environment,
                    title: "CLI environment check failed",
                    message: lastError,
                    detail: nil,
                    targetSection: .providers,
                    targetFilesSection: nil
                )
            )
        }

        return items
    }

    private func skillDiagnostics() -> [ConfigDiagnosticItem] {
        var items: [ConfigDiagnosticItem] = []

        if let lastError = skills.lastError, !lastError.isEmpty {
            items.append(
                ConfigDiagnosticItem(
                    id: "skills:last-error",
                    severity: .error,
                source: .skills,
                title: "Local skills scan failed",
                message: lastError,
                detail: nil,
                targetSection: .files,
                targetFilesSection: .skillFiles
            )
            )
        }

        if let remoteError = skills.remoteError, !remoteError.isEmpty {
            items.append(
                ConfigDiagnosticItem(
                    id: "skills:remote-error",
                    severity: .error,
                source: .skills,
                title: "skills.sh request failed",
                message: remoteError,
                detail: nil,
                targetSection: .files,
                targetFilesSection: .skillFiles
            )
            )
        }

        items.append(contentsOf: skills.snapshot.groups.filter { $0.installedCopyCount > 1 }.map { group in
            ConfigDiagnosticItem(
                id: "skills:duplicate:\(group.id)",
                severity: .warning,
                source: .skills,
                title: "Duplicate installed skill",
                message: "\(group.name) has \(group.installedCopyCount) installed copies.",
                detail: group.providers.joined(separator: ", "),
                targetSection: .files,
                targetFilesSection: .skillFiles
            )
        })

        var remoteRowsByID: [String: RemoteSkillRowModel] = [:]
        for row in skills.discoverRows {
            remoteRowsByID[row.id] = row
        }
        for owner in skills.curatedOwnerRows {
            for row in owner.skills {
                remoteRowsByID[row.id] = row
            }
        }

        items.append(contentsOf: remoteRowsByID.values.compactMap { row in
            guard row.installState == .outOfDate else { return nil }
            return ConfigDiagnosticItem(
                id: "skills:out-of-date:\(row.id)",
                severity: .warning,
                source: .skills,
                title: "Skill update available",
                message: "\(row.skill.name) has a newer remote version.",
                detail: row.skill.displaySource,
                targetSection: .files,
                targetFilesSection: .skillFiles
            )
        })

        items.append(contentsOf: remoteRowsByID.values.compactMap { row in
            guard row.skill.isDuplicate else { return nil }
            return ConfigDiagnosticItem(
                id: "skills:remote-duplicate:\(row.id)",
                severity: .warning,
                source: .skills,
                title: "Duplicate remote skill",
                message: "\(row.skill.name) is marked as duplicate by skills.sh.",
                detail: row.skill.displaySource,
                targetSection: .files,
                targetFilesSection: .skillFiles
            )
        })

        return items
    }

    private func profileDiagnostics() -> [ConfigDiagnosticItem] {
        guard let configurationProfiles else { return [] }
        var items: [ConfigDiagnosticItem] = []
        if let lastError = configurationProfiles.lastError, !lastError.isEmpty {
            items.append(
                ConfigDiagnosticItem(
                    id: "profiles:last-error",
                    severity: .error,
                    source: .profiles,
                    title: "Profile operation failed",
                    message: lastError,
                    detail: nil,
                    targetSection: .profiles,
                    targetFilesSection: nil
                )
            )
        }
        for profile in configurationProfiles.library.profiles {
            switch configurationProfiles.status(for: profile) {
            case .missing(let count):
                items.append(
                    ConfigDiagnosticItem(
                        id: "profiles:missing:\(profile.id)",
                        severity: .warning,
                        source: .profiles,
                        title: "Profile files missing",
                        message: "\(profile.name) has \(count) missing files.",
                        detail: profile.scope.detail,
                        targetSection: .profiles,
                        targetFilesSection: nil
                    )
                )
            case .modified(let count):
                items.append(
                    ConfigDiagnosticItem(
                        id: "profiles:modified:\(profile.id)",
                        severity: .info,
                        source: .profiles,
                        title: "Profile differs from disk",
                        message: "\(profile.name) has \(count) modified files.",
                        detail: profile.scope.detail,
                        targetSection: .profiles,
                        targetFilesSection: nil
                    )
                )
            case .unknown, .empty, .clean:
                break
            }
        }
        return items
    }

    private var allDocuments: [AIConfigDocument] {
        aiConfigs.snapshot.projects.flatMap(\.documents)
    }

    private func fileSection(for kind: AIConfigDocumentKind) -> ConfigFilesSection? {
        switch kind {
        case .instruction: .instructions
        case .providerConfig: .providerFiles
        case .plan: .plans
        case .pluginConfig: .pluginManifests
        case .other: nil
        }
    }

    private func manifestCandidateKeys(for document: AIConfigDocument) -> Set<String> {
        var keys = Set<String>()
        if let content = document.contentPreview {
            keys.formUnion(manifestJSONKeys(from: content))
        }

        if let rootURL = manifestRootURL(for: document) {
            let components = rootURL.standardizedFileURL.pathComponents
            if let pluginID = components.dropLast().last {
                keys.insert(normalizedIdentity(pluginID))
            }
            if components.count >= 2 {
                let marketplace = components[components.count - 2]
                let plugin = components[components.count - 1]
                keys.insert(normalizedIdentity("\(marketplace)/\(plugin)"))
            }
        }

        return keys.filter { !$0.isEmpty }
    }

    private func manifestJSONKeys(from content: String) -> Set<String> {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var values: [String] = []
        for key in ["id", "name", "displayName", "plugin", "slug"] {
            if let value = object[key] as? String {
                values.append(value)
            }
        }
        if let interface = object["interface"] as? [String: Any] {
            for key in ["id", "name", "displayName"] {
                if let value = interface[key] as? String {
                    values.append(value)
                }
            }
        }
        return Set(values.map(normalizedIdentity(_:))).filter { !$0.isEmpty }
    }

    private func manifestRootURL(for document: AIConfigDocument) -> URL? {
        let url = URL(fileURLWithPath: document.path).standardizedFileURL
        if url.lastPathComponent == "plugin.json",
           url.deletingLastPathComponent().lastPathComponent == ".codex-plugin" {
            return url.deletingLastPathComponent().deletingLastPathComponent()
        }
        return url.deletingLastPathComponent()
    }

    private func normalizedIdentity(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9/._-]+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"[-_.]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-/._"))
    }

    private func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func severityRank(_ severity: ConfigDiagnosticSeverity) -> Int {
        switch severity {
        case .error: 0
        case .warning: 1
        case .info: 2
        }
    }
}
