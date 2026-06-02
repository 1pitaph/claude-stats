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

    @Test("CLI host defaults include common terminal apps and can be removed")
    func cliHostDefaultsIncludeCommonTerminalsAndCanBeRemoved() {
        let ids = ActivitySurfaceCatalog.effectiveCLIHostBundleIDs(
            added: ["com.example.Terminal"],
            removed: ["com.apple.Terminal"]
        )

        #expect(ids.contains("com.example.Terminal"))
        #expect(ids.contains("dev.warp.Warp-Stable"))
        #expect(ids.contains("com.googlecode.iterm2"))
        #expect(ids.contains("com.mitchellh." + "ghost" + "ty"))
        #expect(ids.contains("com.github.wez.wezterm"))
        #expect(ids.contains("org.alacritty"))
        #expect(ids.contains("net.kovidgoyal.kitty"))
        #expect(!ids.contains("com.apple.Terminal"))
    }
}
