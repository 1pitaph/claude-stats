import Foundation
import Testing
@testable import ClaudeStats

@Suite("Skills local scanner")
struct SkillsLocalScannerTests {
    @Test("Discovers SKILL.md directories, hidden system skills, plugin cache, and groups duplicates")
    func discoversSkillsAndPlugins() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let codexSkills = root.appendingPathComponent(".codex/skills", isDirectory: true)
        let sharedSkill = codexSkills.appendingPathComponent("hatch-pet", isDirectory: true)
        try TempDir.write(
            """
            ---
            name: Hatch Pet
            description: |
              Create animated pets
            creator: Codex
            allowed-tools:
              - imagegen
            ---
            # Hatch Pet
            """,
            to: sharedSkill.appendingPathComponent("SKILL.md")
        )
        try TempDir.write("reference", to: sharedSkill.appendingPathComponent("references/ref.md"))
        try TempDir.write("loose markdown", to: codexSkills.appendingPathComponent("notes.md"))

        let systemSkill = codexSkills.appendingPathComponent(".system/imagegen", isDirectory: true)
        try TempDir.write(
            """
            ---
            name: Imagegen
            description: Generate images
            ---
            """,
            to: systemSkill.appendingPathComponent("SKILL.md")
        )

        let symlinkURL = codexSkills.appendingPathComponent("hatch-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: sharedSkill)

        let pluginVersion = root.appendingPathComponent(".codex/plugins/cache/openai-curated/build-macos-apps/2.0.0", isDirectory: true)
        try TempDir.write(
            #"{"name":"build-macos-apps","version":"2.0.0","interface":{"displayName":"Build macOS Apps"},"category":"development","author":"OpenAI"}"#,
            to: pluginVersion.appendingPathComponent(".codex-plugin/plugin.json")
        )
        try TempDir.write(
            """
            ---
            name: SwiftUI Patterns
            description: Build native macOS SwiftUI views
            ---
            """,
            to: pluginVersion.appendingPathComponent("skills/swiftui-patterns/SKILL.md")
        )

        let roots = [
            SkillRootDefinition(
                provider: SkillProviderDefinition(id: "codex", displayName: "Codex"),
                scope: .global,
                url: codexSkills,
                maxDepth: 4
            ),
        ]

        let snapshot = SkillsLocalScanner.scanSync(
            roots: roots,
            codexPluginCacheURL: root.appendingPathComponent(".codex/plugins/cache", isDirectory: true),
            scannedAt: Date(timeIntervalSince1970: 1)
        )

        #expect(snapshot.summary.skillCount == 3)
        #expect(snapshot.groups.map(\.name).contains("Hatch Pet"))
        #expect(snapshot.groups.map(\.name).contains("Imagegen"))
        #expect(snapshot.groups.map(\.name).contains("SwiftUI Patterns"))

        let hatch = try #require(snapshot.groups.first { $0.name == "Hatch Pet" }?.primarySkill)
        #expect(hatch.stats.referencesCount == 1)
        #expect(hatch.frontmatter.creator == "Codex")
        #expect(hatch.frontmatter.allowedTools == "imagegen")
        #expect(hatch.description == "Create animated pets")
        #expect(hatch.contentHash != nil)

        let plugin = try #require(snapshot.skills.first { $0.name == "SwiftUI Patterns" })
        #expect(plugin.scope == .plugin)
        #expect(plugin.plugin?.id == "openai-curated/build-macos-apps")
        #expect(plugin.plugin?.displayName == "Build macOS Apps")
        #expect(plugin.plugin?.version == "2.0.0")
        #expect(plugin.folderPath.contains("build-macos-apps/2.0.0/skills/swiftui-patterns"))

        #expect(!snapshot.skills.contains { $0.folderName == "hatch-link" })

        let indexOnlySnapshot = SkillsLocalScanner.scanSync(
            roots: roots,
            codexPluginCacheURL: root.appendingPathComponent(".codex/plugins/cache", isDirectory: true),
            scannedAt: Date(timeIntervalSince1970: 2),
            mode: .indexOnly
        )
        let indexOnlyHatch = try #require(indexOnlySnapshot.groups.first { $0.name == "Hatch Pet" }?.primarySkill)
        #expect(indexOnlyHatch.stats.referencesCount == 1)
        #expect(indexOnlyHatch.files.contains { $0.path == "SKILL.md" })
        #expect(indexOnlyHatch.contentHash == nil)
        #expect(indexOnlySnapshot.scanMode == .indexOnly)
    }

    @Test("Default roots include project cwd skill directories")
    func defaultRootsIncludeProjectCWDs() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("Projects/App", isDirectory: true)
        try TempDir.write(
            """
            ---
            name: Project Skill
            description: Project local skill
            ---
            """,
            to: project.appendingPathComponent(".agents/skills/project-skill/SKILL.md")
        )

        let scanner = SkillsLocalScanner(homeDirectory: root)
        let snapshot = await scanner.scan(sessions: [makeSession(cwd: project.path)])

        let skill = try #require(snapshot.skills.first { $0.name == "Project Skill" })
        #expect(skill.scope == .project(path: project.path))
        #expect(snapshot.summary.projectRootCount == 1)
    }

    private func makeSession(cwd: String) -> Session {
        Session(
            id: "codex::skill-test",
            externalID: "skill-test",
            provider: .codex,
            projectDirectoryName: cwd.replacingOccurrences(of: "/", with: "-"),
            filePath: "\(cwd)/session.jsonl",
            cwd: cwd,
            lastModified: Date(timeIntervalSince1970: 100),
            fileSize: 100,
            stats: nil
        )
    }
}
