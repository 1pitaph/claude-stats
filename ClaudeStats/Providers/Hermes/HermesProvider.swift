import Foundation

struct HermesProvider: Provider {
    let paths: HermesPaths
    let pricing: ModelPricing

    var kind: ProviderKind { .hermes }

    var dataDirectoryExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: paths.homeDirectory.path, isDirectory: &isDir) && isDir.boolValue
    }

    var dataDirectoryPath: String? { paths.homeDirectory.path }

    func discoverSessions() async -> [Session] {
        HermesSessionScanner(paths: paths).scan()
    }

    func parse(_ session: Session) async -> SessionStats? {
        HermesTranscriptParser(pricing: pricing).parse(session)
    }

    func transcriptMessages(for session: Session) async -> [SessionTranscriptMessage] {
        HermesTranscriptParser(pricing: pricing).messages(for: session)
    }

    func executedCommands(for session: Session) async -> [SessionCommandEvent] {
        HermesTranscriptParser(pricing: pricing).executedCommands(for: session)
    }
}
