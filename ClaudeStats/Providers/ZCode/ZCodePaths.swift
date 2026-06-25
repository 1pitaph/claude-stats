import Foundation

/// On-disk locations Claude Stats inspects for the ZCode CLI.
///
/// ZCode stores its CLI session/usage data under `~/.zcode/cli/`. The richest
/// source is the per-CLI SQLite database (`db/db.sqlite`) which holds
/// `session`, `model_usage`, `turn_usage`, `tool_usage`, etc. Per-request
/// rollouts (`rollout/model-io-sess_*.jsonl`) are kept around as a fallback
/// when the database is unavailable or hasn't yet been migrated.
///
/// The Electron-side directory (`~/.zcode/v2/`) is intentionally ignored for
/// now — we only adapt the CLI tool here.
struct ZCodePaths: Sendable, Hashable {
    let homeDirectory: URL

    init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
    }

    /// `~/.zcode/cli`
    var cliDirectory: URL {
        homeDirectory.appendingPathComponent("cli", isDirectory: true)
    }

    /// `~/.zcode/cli/db/db.sqlite` — primary structured data source.
    var databaseURL: URL {
        cliDirectory
            .appendingPathComponent("db", isDirectory: true)
            .appendingPathComponent("db.sqlite", isDirectory: false)
    }

    /// `~/.zcode/cli/rollout` — JSONL per-request rollouts used as a fallback
    /// data source.
    var rolloutDirectory: URL {
        cliDirectory.appendingPathComponent("rollout", isDirectory: true)
    }

    static let `default`: ZCodePaths = {
        if let override = ProcessInfo.processInfo.environment["ZCODE_HOME"], !override.isEmpty {
            return ZCodePaths(homeDirectory: URL(fileURLWithPath: override, isDirectory: true))
        }
        return ZCodePaths(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".zcode", isDirectory: true)
        )
    }()
}
