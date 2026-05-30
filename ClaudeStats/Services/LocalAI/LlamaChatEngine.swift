import Foundation

enum LlamaChatEngineError: Error, LocalizedError {
    case modelNotInstalled
    case bridgeFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled: "Download a local LLM model to use local chat completions."
        case .bridgeFailed(let message): message
        }
    }
}

struct LocalLLMGeneration: Sendable, Hashable {
    var text: String
    var promptTokenEstimate: Int
    var completionTokenEstimate: Int
}

enum LocalLLMStreamEvent: Sendable, Equatable {
    case delta(String)
    case completed(promptTokenEstimate: Int, completionTokenEstimate: Int)
}

actor LlamaChatEngine {
    let modelID: String
    let modelRevision: String

    private let model: LocalAIModelManifest
    private let modelURL: URL
    private let maxContextTokens: Int
    private var bridge: LlamaChatBridge?

    init(model: LocalAIModelManifest, modelURL: URL, maxContextTokens: Int) {
        self.model = model
        self.modelURL = modelURL
        self.modelID = model.id
        self.modelRevision = model.modelRevision
        self.maxContextTokens = maxContextTokens
    }

    func complete(
        messages: [LocalAIChatMessage],
        maxNewTokens: Int,
        temperature: Double
    ) async throws -> LocalLLMGeneration {
        let runtime = try bridgeInstance()
        let payload = messages.map { message in
            ["role": message.role, "content": message.content]
        }
        var text = ""
        do {
            try runtime.streamMessages(
                payload,
                maxNewTokens: maxNewTokens,
                temperature: temperature
            ) { token in
                guard !Task.isCancelled else { return false }
                text += token
                return true
            }
        } catch {
            throw LlamaChatEngineError.bridgeFailed(error.localizedDescription)
        }
        guard !Task.isCancelled else {
            throw CancellationError()
        }
        return LocalLLMGeneration(
            text: text,
            promptTokenEstimate: Self.estimatedTokens(messages.map(\.content).joined(separator: "\n")),
            completionTokenEstimate: Self.estimatedTokens(text)
        )
    }

    func streamComplete(
        messages: [LocalAIChatMessage],
        maxNewTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<LocalLLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.performStreamComplete(
                        messages: messages,
                        maxNewTokens: maxNewTokens,
                        temperature: temperature,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func performStreamComplete(
        messages: [LocalAIChatMessage],
        maxNewTokens: Int,
        temperature: Double,
        continuation: AsyncThrowingStream<LocalLLMStreamEvent, Error>.Continuation
    ) async throws {
        let runtime = try bridgeInstance()
        let payload = messages.map { message in
            ["role": message.role, "content": message.content]
        }
        var output = ""
        do {
            try runtime.streamMessages(
                payload,
                maxNewTokens: maxNewTokens,
                temperature: temperature
            ) { token in
                guard !Task.isCancelled else { return false }
                output += token
                continuation.yield(.delta(token))
                return true
            }
        } catch {
            throw LlamaChatEngineError.bridgeFailed(error.localizedDescription)
        }
        guard !Task.isCancelled else {
            continuation.finish(throwing: CancellationError())
            return
        }
        continuation.yield(
            .completed(
                promptTokenEstimate: Self.estimatedTokens(messages.map(\.content).joined(separator: "\n")),
                completionTokenEstimate: Self.estimatedTokens(output)
            )
        )
        continuation.finish()
    }

    private func bridgeInstance() throws -> LlamaChatBridge {
        if let bridge { return bridge }
        let runtime: LlamaChatBridge
        do {
            runtime = try LlamaChatBridge(
                modelPath: modelURL.path,
                maxContextTokens: maxContextTokens,
                useMetal: true
            )
        } catch {
            throw LlamaChatEngineError.bridgeFailed(error.localizedDescription)
        }
        bridge = runtime
        return runtime
    }

    private static func estimatedTokens(_ text: String) -> Int {
        max(1, text.utf8.count / 4)
    }
}

enum LocalLLMContextPolicy {
    static func maxContextTokens(
        for model: LocalAIModelManifest,
        memoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> Int {
        let memoryGB = Double(memoryBytes) / 1_073_741_824
        let cap: Int
        if memoryGB >= 31.5 {
            cap = 16_384
        } else if memoryGB >= 15.5 {
            cap = 8_192
        } else {
            cap = 4_096
        }
        return min(max(512, model.maxTokens), cap)
    }
}
