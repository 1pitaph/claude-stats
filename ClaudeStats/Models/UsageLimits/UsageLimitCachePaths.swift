import Foundation

enum UsageLimitCachePaths {
    private static let appSupportFolderName = "Claude Stats"
    private static let usageLimitsFolderName = "UsageLimits"

    static func directory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
            .appendingPathComponent(usageLimitsFolderName, isDirectory: true)
    }

    static func claudeCacheURL(fileManager: FileManager = .default) -> URL {
        directory(fileManager: fileManager)
            .appendingPathComponent("claude-rate-limits.json", isDirectory: false)
    }

    static func claudeBridgeScriptURL(fileManager: FileManager = .default) -> URL {
        directory(fileManager: fileManager)
            .appendingPathComponent("claude-statusline-bridge.sh", isDirectory: false)
    }

    static func historyURL(fileManager: FileManager = .default) -> URL {
        directory(fileManager: fileManager)
            .appendingPathComponent("usage-limit-history.json", isDirectory: false)
    }
}
