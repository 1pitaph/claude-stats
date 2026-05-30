import Testing
@testable import ClaudeStats

@Suite("ActivitySurfaceCatalog")
struct ActivitySurfaceCatalogTests {
    @Test("Coding surface defaults include Codex and Claude GUI but not ChatGPT")
    func codingSurfaceDefaults() {
        let ids = ActivitySurfaceCatalog.effectiveCodingSurfaceBundleIDs(added: [], removed: [])

        #expect(ids.contains("com.openai.codex"))
        #expect(ids.contains("com.anthropic.claudefordesktop"))
        #expect(!ids.contains("com.openai.chat"))
    }

    @Test("CLI host defaults can be removed")
    func cliHostDefaultsCanBeRemoved() {
        let ids = ActivitySurfaceCatalog.effectiveCLIHostBundleIDs(
            added: ["com.example.Terminal"],
            removed: ["com.apple.Terminal"]
        )

        #expect(ids.contains("com.example.Terminal"))
        #expect(ids.contains("com.mitchellh.ghostty"))
        #expect(ids.contains("dev.warp.Warp-Stable"))
        #expect(!ids.contains("com.apple.Terminal"))
    }
}
