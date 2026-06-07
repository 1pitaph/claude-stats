import Foundation

struct HermesPaths: Sendable, Hashable {
    let homeDirectory: URL

    init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
    }

    var databaseURLs: [URL] {
        var urls = [homeDirectory.appendingPathComponent("state.db", isDirectory: false)]
        let profiles = homeDirectory.appendingPathComponent("profiles", isDirectory: true)
        if let profileDirs = try? FileManager.default.contentsOfDirectory(
            at: profiles,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            urls += profileDirs
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                .map { $0.appendingPathComponent("state.db", isDirectory: false) }
        }
        return urls
    }

    static let `default`: HermesPaths = {
        if let override = ProcessInfo.processInfo.environment["HERMES_HOME"], !override.isEmpty {
            return HermesPaths(homeDirectory: URL(fileURLWithPath: override, isDirectory: true))
        }
        return HermesPaths(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".hermes", isDirectory: true)
        )
    }()
}
