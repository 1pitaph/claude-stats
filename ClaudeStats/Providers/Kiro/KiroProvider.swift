import Foundation

struct KiroProvider: Provider {
    let paths: KiroPaths
    let pricing: ModelPricing

    var kind: ProviderKind { .kiro }

    var dataDirectoryExists: Bool {
        [
            paths.homeDirectory,
            paths.applicationSupportDatabase.deletingLastPathComponent(),
            paths.localShareDatabase.deletingLastPathComponent(),
            paths.archiveDirectory,
        ].contains { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    var dataDirectoryPath: String? {
        ProviderStorageHelpers.firstExistingDirectory([
            paths.homeDirectory,
            paths.applicationSupportDatabase.deletingLastPathComponent(),
            paths.localShareDatabase.deletingLastPathComponent(),
            paths.archiveDirectory,
        ])?.path ?? paths.homeDirectory.path
    }

    func discoverSessions() async -> [Session] {
        KiroSessionScanner(paths: paths).scan()
    }

    func parse(_ session: Session) async -> SessionStats? {
        KiroTranscriptParser(pricing: pricing).parse(session)
    }

    func transcriptMessages(for session: Session) async -> [SessionTranscriptMessage] {
        KiroTranscriptParser(pricing: pricing).messages(for: session)
    }

    func executedCommands(for session: Session) async -> [SessionCommandEvent] {
        KiroTranscriptParser(pricing: pricing).executedCommands(for: session)
    }
}
