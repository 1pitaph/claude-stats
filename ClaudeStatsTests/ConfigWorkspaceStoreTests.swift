import Foundation
import Testing
@testable import ClaudeStats

@MainActor
@Suite("Config workspace store")
struct ConfigWorkspaceStoreTests {
    @Test("Legacy main pages migrate into Config sections")
    func legacyMainPageMigration() {
        let store = makeEmptyStore()

        #expect(store.migrateLegacyMainPage(rawValue: "configurations"))
        #expect(store.section == .providers)

        #expect(store.migrateLegacyMainPage(rawValue: "skills"))
        #expect(store.section == .files)
        #expect(store.filesSection == .skillFiles)

        #expect(!store.migrateLegacyMainPage(rawValue: "usage"))
        #expect(store.section == .files)
    }

    @Test("Counts, diagnostics, and plugin related skills aggregate across modules")
    func countsDiagnosticsAndPluginRelatedSkills() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let claudeHome = root.appendingPathComponent(".claude", isDirectory: true)
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let project = root.appendingPathComponent("Projects/App", isDirectory: true)

        try TempDir.write("# App agents\n", to: project.appendingPathComponent("AGENTS.md"))
        try TempDir.write(#"{"broken": true"#, to: project.appendingPathComponent(".claude/settings.local.json"))
        try TempDir.write(
            #"{"name":"build-macos-apps","interface":{"displayName":"Build macOS Apps"}}"#,
            to: codexHome.appendingPathComponent("plugins/build-macos-apps/plugin.json")
        )

        try TempDir.write(
            """
            ---
            name: Alpha Skill
            description: First local copy
            ---
            """,
            to: codexHome.appendingPathComponent("skills/alpha/SKILL.md")
        )
        try TempDir.write(
            """
            ---
            name: Alpha Skill
            description: Second local copy
            ---
            """,
            to: claudeHome.appendingPathComponent("skills/alpha/SKILL.md")
        )

        let pluginVersion = codexHome.appendingPathComponent("plugins/cache/openai-curated/build-macos-apps/2.0.0", isDirectory: true)
        try TempDir.write(
            #"{"name":"build-macos-apps","version":"2.0.0","interface":{"displayName":"Build macOS Apps"},"enabled":true}"#,
            to: pluginVersion.appendingPathComponent(".codex-plugin/plugin.json")
        )
        try TempDir.write(
            """
            ---
            name: SwiftUI Patterns
            description: Plugin skill
            ---
            """,
            to: pluginVersion.appendingPathComponent("skills/swiftui-patterns/SKILL.md")
        )

        let sessions = [makeSession(provider: .codex, cwd: project.path)]
        let aiConfigs = AIConfigsViewModel(scanner: makeScanner(claudeHome: claudeHome, codexHome: codexHome))
        await aiConfigs.loadIfNeeded(sessions: sessions)

        let cliEnvironment = CLIEnvironmentViewModel(
            checker: FakeCLIEnvironmentChecker(
                snapshot: CLIEnvironmentSnapshot(
                    statuses: [
                        CLIToolStatus(
                            cli: .claude,
                            command: "claude",
                            version: "1.0.0",
                            latestVersion: "2.0.0",
                            error: nil,
                            diagnostic: nil,
                            envType: .macOS,
                            executablePath: "/usr/local/bin/claude"
                        ),
                    ],
                    conflicts: [
                        CLIEnvironmentConflict(
                            cli: .codex,
                            varName: "OPENAI_API_KEY",
                            varValue: "sk-test",
                            sourceType: .file,
                            sourcePath: "~/.zshrc",
                            lineNumber: 12,
                            isDeletable: true
                        ),
                    ]
                )
            )
        )
        await cliEnvironment.loadIfNeeded()

        let fakeClient = FakeSkillsShClient()
        let remote = RemoteSkillSummary(
            id: "owner/repo/alpha-skill",
            slug: "alpha-skill",
            name: "Alpha Skill",
            source: "owner/repo",
            installURL: "https://example.com/alpha"
        )
        fakeClient.searchResults = [remote]
        fakeClient.details[remote.id] = remoteDetail(id: remote.id, hash: "remote-hash")
        let skills = SkillsStore(
            scanner: SkillsLocalScanner(homeDirectory: root),
            client: fakeClient,
            credentials: InMemorySkillsShCredentialStore(apiKey: "sk_test")
        )
        await skills.loadIfNeeded(sessions: sessions)
        skills.selectedTab = .discover
        skills.searchText = "alpha"
        await skills.searchOrLoadTrending()
        skills.selectRemoteSkill(remote)
        await skills.loadRemoteDetail(id: remote.id)
        await skills.waitForLocalHashRefresh()

        let store = ConfigWorkspaceStore(
            apiProviders: APIProviderSwitcherViewModel(),
            cliEnvironment: cliEnvironment,
            aiConfigs: aiConfigs,
            skills: skills
        )

        #expect(store.counts.configFileCount == aiConfigs.snapshot.summary.existingDocumentCount + skills.snapshot.skills.count)
        #expect(store.counts.skillCount == skills.snapshot.summary.groupCount)
        #expect(store.counts.diagnosticCount == store.diagnostics.count)
        #expect(store.fileCount(for: .pluginManifests) == 1)
        #expect(store.diagnostics.contains { $0.source == .files && $0.title == "Missing expected file" })
        #expect(store.diagnostics.contains { $0.source == .files && $0.severity == .error })
        #expect(store.diagnostics.contains { $0.source == .environment && $0.title == "Environment variable conflict" })
        #expect(store.diagnostics.contains { $0.source == .skills && $0.title == "Duplicate installed skill" })
        #expect(store.diagnostics.contains { $0.source == .skills && $0.title == "Skill update available" })

        let manifest = try #require(
            aiConfigs.snapshot.projects
                .flatMap(\.documents)
                .first { $0.kind == .pluginConfig && $0.path.contains("build-macos-apps/plugin.json") }
        )
        let related = store.relatedPluginSkills(for: manifest)
        #expect(related.map(\.name).contains("SwiftUI Patterns"))
    }

    @Test("Skills remote errors appear in Config diagnostics")
    func skillsRemoteErrorDiagnostic() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let skills = SkillsStore(
            scanner: SkillsLocalScanner(homeDirectory: root),
            client: FakeSkillsShClient(),
            credentials: InMemorySkillsShCredentialStore()
        )
        await skills.loadIfNeeded(sessions: [])
        skills.selectedTab = .discover
        await skills.searchOrLoadTrending()

        let store = ConfigWorkspaceStore(
            apiProviders: APIProviderSwitcherViewModel(),
            cliEnvironment: CLIEnvironmentViewModel(checker: FakeCLIEnvironmentChecker(snapshot: CLIEnvironmentSnapshot(statuses: [], conflicts: []))),
            aiConfigs: AIConfigsViewModel(scanner: AIConfigScanner(registry: ProviderRegistry(providers: []))),
            skills: skills
        )

        #expect(store.diagnostics.contains { $0.source == .skills && $0.title == "skills.sh request failed" })
    }

    @Test("Missing expected config file exposes template metadata")
    func missingExpectedFileTemplate() {
        let document = AIConfigDocument(
            id: "codex:global:config",
            provider: .codex,
            title: "config.toml",
            path: "/tmp/missing-config.toml",
            kind: .providerConfig,
            fileKind: .toml,
            location: .global,
            exists: false,
            isExpected: true,
            fileSize: nil,
            modifiedAt: nil,
            contentPreview: nil,
            isPreviewTruncated: false,
            assignedProjectPath: nil,
            stats: .empty,
            diagnostics: []
        )

        #expect(document.canCreateFromTemplate)
        #expect(document.templateContent?.contains("sandbox_mode") == true)
    }

    private func makeEmptyStore() -> ConfigWorkspaceStore {
        ConfigWorkspaceStore(
            apiProviders: APIProviderSwitcherViewModel(),
            cliEnvironment: CLIEnvironmentViewModel(checker: FakeCLIEnvironmentChecker(snapshot: CLIEnvironmentSnapshot(statuses: [], conflicts: []))),
            aiConfigs: AIConfigsViewModel(scanner: AIConfigScanner(registry: ProviderRegistry(providers: []))),
            skills: SkillsStore()
        )
    }

    private func makeScanner(claudeHome: URL, codexHome: URL) -> AIConfigScanner {
        let registry = ProviderRegistry(
            providers: [
                ClaudeProvider(paths: ClaudePaths(configDirectory: claudeHome), pricing: TestPricing.table),
                CodexProvider(paths: CodexPaths(homeDirectory: codexHome), pricing: TestPricing.table),
            ]
        )
        return AIConfigScanner(registry: registry)
    }

    private func makeSession(provider: ProviderKind, cwd: String) -> Session {
        Session(
            id: "\(provider.rawValue)::\(cwd)",
            externalID: "test",
            provider: provider,
            projectDirectoryName: cwd.replacingOccurrences(of: "/", with: "-"),
            filePath: "\(cwd)/session.jsonl",
            cwd: cwd,
            lastModified: Date(timeIntervalSince1970: 100),
            fileSize: 100,
            stats: nil
        )
    }

    private func remoteDetail(id: String, hash: String?) -> RemoteSkillDetail {
        let data = Data(
            """
            {
              "id": "\(id)",
              "source": "owner/repo",
              "slug": "alpha-skill",
              "installs": 10,
              "hash": \(hash.map { "\"\($0)\"" } ?? "null"),
              "files": [
                { "path": "SKILL.md", "contents": "---\\nname: Alpha Skill\\n---\\n" }
              ]
            }
            """.utf8
        )
        return try! JSONDecoder().decode(RemoteSkillDetail.self, from: data)
    }
}

private struct FakeCLIEnvironmentChecker: CLIEnvironmentChecking {
    let snapshot: CLIEnvironmentSnapshot

    func checkAll() async throws -> CLIEnvironmentSnapshot {
        snapshot
    }

    func deleteConflicts(_ conflicts: [CLIEnvironmentConflict]) async throws -> CLIEnvironmentCleanupResult {
        CLIEnvironmentCleanupResult(backupDirectory: URL(fileURLWithPath: "/tmp"), deletedConflictIDs: conflicts.map(\.id), skippedConflicts: [])
    }
}
