import Foundation
import Testing
@testable import ClaudeStats

@Suite("Codex Track hook installer")
struct CodexTrackHookInstallerTests {
    @Test("Install writes helper, preserves existing hooks, and enables Codex hooks")
    func installWritesHookConfig() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let codexHome = root.appendingPathComponent("codex", isDirectory: true)
        let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        try TempDir.write(
            #"{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"existing-tool-hook","timeout":10}]}]}}"#,
            to: codexHome.appendingPathComponent("hooks.json")
        )
        try TempDir.write("model = \"gpt-5\"\n[features]\njs_repl = false\n", to: codexHome.appendingPathComponent("config.toml"))

        let installer = CodexTrackHookInstaller(
            codexHome: codexHome,
            appSupportDirectory: appSupport,
            hookScriptBody: "console.log('track')\n"
        )
        let result = try installer.install(now: Date(timeIntervalSince1970: 1))

        #expect(result.status.isInstalled)
        #expect(FileManager.default.fileExists(atPath: installer.installedHookURL.path))
        #expect(result.status.eventLogURL.path.contains("ClaudeStats/Track/events.jsonl"))

        let hooksData = try Data(contentsOf: installer.hookConfigURL)
        let hooksRoot = try #require(JSONSerialization.jsonObject(with: hooksData) as? [String: Any])
        let hooks = try #require(hooksRoot["hooks"] as? [String: Any])
        for event in CodexTrackHookInstaller.requiredEvents {
            let groups = try #require(hooks[event] as? [[String: Any]])
            #expect(groups.description.contains("codex-track-hook.js"))
        }
        #expect(String(data: hooksData, encoding: .utf8)?.contains("existing-tool-hook") == true)

        let codexConfig = try String(contentsOf: installer.codexConfigURL, encoding: .utf8)
        #expect(CodexTrackHookInstaller.configHasHooksEnabled(codexConfig))
    }

    @Test("Config patch inserts hooks into existing features section")
    func configPatchUpdatesFeatures() {
        let input = "model = \"gpt-5\"\n[features]\njs_repl = false\n[desktop]\nappearance = \"codex\"\n"
        let output = CodexTrackHookInstaller.configByEnablingHooks(input)

        #expect(output.contains("[features]\nhooks = true\njs_repl = false"))
        #expect(output.contains("[desktop]"))
        #expect(CodexTrackHookInstaller.configHasHooksEnabled(output))
    }
}
