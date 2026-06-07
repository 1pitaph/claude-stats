import Foundation

struct OpenCodePaths: Sendable, Hashable {
    let dataDirectories: [URL]

    init(dataDirectories: [URL]) {
        self.dataDirectories = dataDirectories
    }

    var databaseURLs: [URL] {
        dataDirectories.flatMap {
            ProviderStorageHelpers.databaseURLs(in: $0, prefix: "opencode")
        }
    }

    static let `default`: OpenCodePaths = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var directories: [URL] = []
        if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdg.isEmpty {
            directories.append(URL(fileURLWithPath: xdg, isDirectory: true).appendingPathComponent("opencode", isDirectory: true))
        }
        directories.append(
            home
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("share", isDirectory: true)
                .appendingPathComponent("opencode", isDirectory: true)
        )
        return OpenCodePaths(dataDirectories: directories)
    }()
}
