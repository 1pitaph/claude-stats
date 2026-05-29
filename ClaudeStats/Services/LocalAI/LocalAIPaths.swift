import Foundation

enum LocalAIPaths {
    static let appSupportDirectoryName = "com.claudestats.ClaudeStats"

    static func applicationSupportRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("LocalAI", isDirectory: true)
    }

    static func cachesRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
        return base
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("LocalAI", isDirectory: true)
    }

    static func modelsDirectory(fileManager: FileManager = .default) -> URL {
        applicationSupportRoot(fileManager: fileManager).appendingPathComponent("Models", isDirectory: true)
    }

    static func modelsDirectory(for kind: LocalAIModelKind, fileManager: FileManager = .default) -> URL {
        modelsDirectory(fileManager: fileManager)
            .appendingPathComponent(kind.storageDirectoryName, isDirectory: true)
    }

    static func stateURL(fileManager: FileManager = .default) -> URL {
        applicationSupportRoot(fileManager: fileManager).appendingPathComponent("models-state.json")
    }

    static func helperRuntimeConfigURL(fileManager: FileManager = .default) -> URL {
        applicationSupportRoot(fileManager: fileManager).appendingPathComponent("openai-helper-runtime.json")
    }

    static func helperPIDURL(fileManager: FileManager = .default) -> URL {
        applicationSupportRoot(fileManager: fileManager).appendingPathComponent("openai-helper.pid")
    }

    static func helperMetaURL(fileManager: FileManager = .default) -> URL {
        applicationSupportRoot(fileManager: fileManager).appendingPathComponent("openai-helper-meta.json")
    }

    static func embeddingIndexURL(fileManager: FileManager = .default) -> URL {
        cachesRoot(fileManager: fileManager).appendingPathComponent("embedding-index.sqlite3")
    }
}
