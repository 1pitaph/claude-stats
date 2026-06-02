import Foundation

/// Known app bundle identifiers used by the Activity analysis. Screen Time
/// isn't provider-specific, so this lives in the shared layer.
enum ActivitySurfaceCatalog {
    struct App: Sendable, Hashable, Identifiable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    /// GUI apps that count as "coding surface" focus time.
    static let codingSurfaceDefaults: [App] = [
        App(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
        App(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code"),
        App(bundleID: "com.microsoft.VSCodeInsiders", name: "VS Code Insiders"),
        App(bundleID: "com.visualstudio.code.oss", name: "Code - OSS"),
        App(bundleID: "com.vscodium", name: "VSCodium"),
        App(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        App(bundleID: "com.exafunction.windsurf", name: "Windsurf"),
        App(bundleID: "com.trae.app", name: "Trae"),
        App(bundleID: "cn.trae.app", name: "Trae CN"),
        App(bundleID: "com.qoder.app", name: "Qoder"),
        App(bundleID: "dev.zed.Zed", name: "Zed"),
        App(bundleID: "dev.zed.Zed-Preview", name: "Zed Preview"),
        App(bundleID: "com.jetbrains.intellij", name: "IntelliJ IDEA"),
        App(bundleID: "com.jetbrains.intellij.ce", name: "IntelliJ IDEA CE"),
        App(bundleID: "com.jetbrains.pycharm", name: "PyCharm"),
        App(bundleID: "com.jetbrains.pycharm.ce", name: "PyCharm CE"),
        App(bundleID: "com.jetbrains.goland", name: "GoLand"),
        App(bundleID: "com.jetbrains.WebStorm", name: "WebStorm"),
        App(bundleID: "com.jetbrains.CLion", name: "CLion"),
        App(bundleID: "com.jetbrains.rubymine", name: "RubyMine"),
        App(bundleID: "com.jetbrains.PhpStorm", name: "PhpStorm"),
        App(bundleID: "com.jetbrains.AppCode", name: "AppCode"),
        App(bundleID: "com.jetbrains.datagrip", name: "DataGrip"),
        App(bundleID: "com.jetbrains.rider", name: "Rider"),
        App(bundleID: "com.jetbrains.fleet", name: "Fleet"),
        App(bundleID: "com.google.android.studio", name: "Android Studio"),
        App(bundleID: "com.sublimetext.4", name: "Sublime Text"),
        App(bundleID: "com.sublimetext.3", name: "Sublime Text 3"),
        App(bundleID: "com.panic.Nova", name: "Nova"),
        App(bundleID: "org.vim.MacVim", name: "MacVim"),
        App(bundleID: "io.neovim.neovide", name: "Neovide"),
        App(bundleID: "com.openai.codex", name: "OpenAI Codex"),
        App(bundleID: "com.anthropic.claudefordesktop", name: "Claude"),
    ]

    /// Terminal-style hosts shown separately from coding-surface time.
    static let cliHostDefaults: [App] = [
        App(bundleID: "com.apple.Terminal", name: "Terminal"),
        App(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
        App(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
        App(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
        App(bundleID: "com.github.wez.wezterm", name: "WezTerm"),
        App(bundleID: "org.alacritty", name: "Alacritty"),
        App(bundleID: "net.kovidgoyal.kitty", name: "Kitty"),
        App(bundleID: "co.zeit.hyper", name: "Hyper"),
    ]

    private static let codingSurfaceDefaultIDs = Set(codingSurfaceDefaults.map(\.bundleID))
    private static let cliHostDefaultIDs = Set(cliHostDefaults.map(\.bundleID))

    /// The GUI coding-surface bundle ids actually in effect: defaults plus
    /// user additions, minus user removals.
    static func effectiveCodingSurfaceBundleIDs(added: [String], removed: [String]) -> Set<String> {
        codingSurfaceDefaultIDs.union(added).subtracting(removed)
    }

    /// The CLI-host bundle ids actually in effect: defaults plus user
    /// additions, minus user removals.
    static func effectiveCLIHostBundleIDs(added: [String], removed: [String]) -> Set<String> {
        cliHostDefaultIDs.union(added).subtracting(removed)
    }

    /// Best-effort display name for a bundle id (falls back to the id itself).
    static func displayName(for bundleID: String) -> String {
        (codingSurfaceDefaults + cliHostDefaults).first { $0.bundleID == bundleID }?.name ?? bundleID
    }
}
