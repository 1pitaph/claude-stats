import Foundation
import Darwin

@main
enum ClaudeStatsLocalAIHelper {
    static func main() async {
        do {
            var arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.first == "serve" else {
                throw HelperCLIError.message("Usage: claude-stats-local-ai serve --config <path>")
            }
            arguments.removeFirst()
            let options = parseOptions(arguments)
            guard let configPath = options["config"], !configPath.isEmpty else {
                throw HelperCLIError.message("Usage: claude-stats-local-ai serve --config <path>")
            }

            let config = try LocalAIHelperRuntimeConfig.load(from: URL(fileURLWithPath: configPath))
            try await MainActor.run {
                let process = LocalAIHelperProcess()
                try process.start(config: config)
                Self.process = process
            }
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 3_600_000_000_000)
            }
        } catch {
            FileHandle.standardError.write(Data("claude-stats-local-ai: \(error.localizedDescription)\n".utf8))
            exit(2)
        }
    }

    @MainActor private static var process: LocalAIHelperProcess?

    private static func parseOptions(_ arguments: [String]) -> [String: String] {
        var output: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--") else {
                index += 1
                continue
            }
            let name = String(key.dropFirst(2))
            if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                output[name] = arguments[index + 1]
                index += 2
            } else {
                output[name] = "true"
                index += 1
            }
        }
        return output
    }
}

@MainActor
private final class LocalAIHelperProcess {
    private var server: LocalAIOpenAIServer?

    func start(config: LocalAIHelperRuntimeConfig) throws {
        let modelStore = LocalAIModelStore()
        modelStore.select(modelID: config.embeddingModelID, kind: .embedding)
        modelStore.select(modelID: config.llmModelID, kind: .llm)
        let metadata = LocalAIServiceRuntimeMetadata(
            schemaVersion: config.schemaVersion,
            configHash: config.configHash,
            port: config.port
        )
        let service = LocalAIOpenAIService(modelStore: modelStore, runtimeMetadata: metadata)
        let server = LocalAIOpenAIServer(service: service, token: config.token, port: config.port, idleTimeout: 120) {
            // Skip ggml/Metal process-wide destructors; normal exit currently aborts in ggml_metal_rsets_free.
            Darwin._exit(0)
        }
        _ = try server.start()
        self.server = server
    }
}

private enum HelperCLIError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let value): value
        }
    }
}
