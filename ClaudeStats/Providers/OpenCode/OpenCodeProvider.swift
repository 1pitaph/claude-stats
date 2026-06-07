import Foundation

struct OpenCodeProvider: Provider {
    let paths: OpenCodePaths
    let pricing: ModelPricing

    var kind: ProviderKind { .opencode }

    var dataDirectoryExists: Bool {
        !paths.databaseURLs.isEmpty || paths.dataDirectories.contains { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    var dataDirectoryPath: String? {
        ProviderStorageHelpers.firstExistingDirectory(paths.dataDirectories)?.path
            ?? paths.dataDirectories.first?.path
    }

    func discoverSessions() async -> [Session] {
        OpenCodeSessionScanner(paths: paths).scan()
    }

    func parse(_ session: Session) async -> SessionStats? {
        OpenCodeTranscriptParser(pricing: pricing).parse(session)
    }

    func transcriptMessages(for session: Session) async -> [SessionTranscriptMessage] {
        OpenCodeTranscriptParser(pricing: pricing).messages(for: session)
    }

    func executedCommands(for session: Session) async -> [SessionCommandEvent] {
        OpenCodeTranscriptParser(pricing: pricing).executedCommands(for: session)
    }

    func cacheHitRate(for usage: TokenUsage) -> Double? {
        usage.cachedInputRate
    }
}
