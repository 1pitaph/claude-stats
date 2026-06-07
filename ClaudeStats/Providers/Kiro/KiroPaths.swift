import Foundation

struct KiroPaths: Sendable, Hashable {
    let homeDirectory: URL
    let applicationSupportDatabase: URL
    let localShareDatabase: URL
    let archiveDirectory: URL

    var cliSessionsDirectory: URL {
        homeDirectory
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("cli", isDirectory: true)
    }

    var databaseURLs: [URL] {
        [
            homeDirectory.appendingPathComponent("data.sqlite3", isDirectory: false),
            applicationSupportDatabase,
            localShareDatabase,
        ]
    }

    init(homeDirectory: URL,
         applicationSupportDatabase: URL,
         localShareDatabase: URL,
         archiveDirectory: URL) {
        self.homeDirectory = homeDirectory
        self.applicationSupportDatabase = applicationSupportDatabase
        self.localShareDatabase = localShareDatabase
        self.archiveDirectory = archiveDirectory
    }

    static let `default`: KiroPaths = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let kiroHome: URL
        if let override = ProcessInfo.processInfo.environment["KIRO_HOME"], !override.isEmpty {
            kiroHome = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            kiroHome = home.appendingPathComponent(".kiro", isDirectory: true)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        return KiroPaths(
            homeDirectory: kiroHome,
            applicationSupportDatabase: appSupport
                .appendingPathComponent("kiro-cli", isDirectory: true)
                .appendingPathComponent("data.sqlite3", isDirectory: false),
            localShareDatabase: home
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("share", isDirectory: true)
                .appendingPathComponent("kiro-cli", isDirectory: true)
                .appendingPathComponent("data.sqlite3", isDirectory: false),
            archiveDirectory: home.appendingPathComponent(".kiro_sessions", isDirectory: true)
        )
    }()
}
