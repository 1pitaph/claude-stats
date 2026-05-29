import Foundation

enum LocalAIOpenAIServiceError: Error, LocalizedError {
    case unsupportedStreaming
    case modelNotFound(String)
    case modelNotInstalled(String)
    case invalidRequest(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedStreaming:
            "Streaming responses are not supported by the local OpenAI-compatible service yet."
        case .modelNotFound(let model):
            "Local AI model not found: \(model)."
        case .modelNotInstalled(let model):
            "Local AI model is not installed: \(model)."
        case .invalidRequest(let message):
            message
        }
    }
}

@MainActor
final class LocalAIOpenAIService {
    private let modelStore: LocalAIModelStore
    private let runtimeMetadata: LocalAIServiceRuntimeMetadata?
    private var embeddingEngines: [String: any EmbeddingEngine] = [:]
    private var chatEngines: [String: LlamaChatEngine] = [:]

    init(modelStore: LocalAIModelStore, runtimeMetadata: LocalAIServiceRuntimeMetadata? = nil) {
        self.modelStore = modelStore
        self.runtimeMetadata = runtimeMetadata
    }

    func modelsResponse() -> LocalAIModelsResponse {
        let created = Int(Date().timeIntervalSince1970)
        return LocalAIModelsResponse(
            data: modelStore.allModels.map {
                LocalAIModelsResponse.Model(id: $0.id, created: created)
            }
        )
    }

    func embeddingsResponse(_ request: LocalAIEmbeddingsRequest) async throws -> LocalAIEmbeddingsResponse {
        guard !request.input.isEmpty else {
            throw LocalAIOpenAIServiceError.invalidRequest("Embedding input must not be empty.")
        }
        let model = try resolveModel(id: request.model, kind: .embedding)
        guard let url = modelStore.installedModelURL(for: model) else {
            throw LocalAIOpenAIServiceError.modelNotInstalled(model.id)
        }
        let engine = embeddingEngines[model.id] ?? LlamaEmbeddingEngine(model: model, modelURL: url)
        embeddingEngines[model.id] = engine
        let vectors = try await engine.embed(request.input)
        let promptTokens = request.input.reduce(0) { $0 + Self.estimatedTokens($1) }
        return LocalAIEmbeddingsResponse(
            data: vectors.enumerated().map { index, vector in
                LocalAIEmbeddingsResponse.Embedding(embedding: vector, index: index)
            },
            model: model.id,
            usage: LocalAIEmbeddingsResponse.Usage(promptTokens: promptTokens, totalTokens: promptTokens)
        )
    }

    func chatResponse(_ request: LocalAIChatCompletionsRequest) async throws -> LocalAIChatCompletionsResponse {
        if request.stream == true {
            throw LocalAIOpenAIServiceError.unsupportedStreaming
        }
        guard !request.messages.isEmpty else {
            throw LocalAIOpenAIServiceError.invalidRequest("Chat completion requires at least one message.")
        }
        let model = try resolveModel(id: request.model, kind: .llm)
        guard let url = modelStore.installedModelURL(for: model) else {
            throw LocalAIOpenAIServiceError.modelNotInstalled(model.id)
        }
        let engine = chatEngines[model.id] ?? LlamaChatEngine(
            model: model,
            modelURL: url,
            maxContextTokens: LocalLLMContextPolicy.maxContextTokens(for: model)
        )
        chatEngines[model.id] = engine
        let generation = try await engine.complete(
            messages: request.messages,
            maxNewTokens: min(max(request.maxTokens ?? 512, 1), 2048),
            temperature: request.temperature ?? 0.2
        )
        let created = Int(Date().timeIntervalSince1970)
        return LocalAIChatCompletionsResponse(
            id: "chatcmpl-local-\(UUID().uuidString)",
            created: created,
            model: model.id,
            choices: [
                LocalAIChatCompletionsResponse.Choice(
                    index: 0,
                    message: LocalAIChatMessage(role: "assistant", content: generation.text),
                    finishReason: "stop"
                ),
            ],
            usage: LocalAIChatCompletionsResponse.Usage(
                promptTokens: generation.promptTokenEstimate,
                completionTokens: generation.completionTokenEstimate,
                totalTokens: generation.promptTokenEstimate + generation.completionTokenEstimate
            )
        )
    }

    func health() -> [String: String] {
        let embeddingInstalled = modelStore.installedModelURL(for: modelStore.selectedEmbeddingModel) != nil
        let llmInstalled = modelStore.installedModelURL(for: modelStore.selectedLLMModel) != nil
        var payload = [
            "status": embeddingInstalled && llmInstalled ? "ok" : "degraded",
            "embedding_model": modelStore.selectedEmbeddingModel.id,
            "embedding_installed": embeddingInstalled ? "true" : "false",
            "llm_model": modelStore.selectedLLMModel.id,
            "llm_installed": llmInstalled ? "true" : "false",
        ]
        if let runtimeMetadata {
            payload["helper"] = "claude-stats-local-ai"
            payload["schema_version"] = "\(runtimeMetadata.schemaVersion)"
            payload["config_hash"] = runtimeMetadata.configHash
            payload["port"] = "\(runtimeMetadata.port)"
        }
        return payload
    }

    private func resolveModel(id: String?, kind: LocalAIModelKind) throws -> LocalAIModelManifest {
        let selected = kind == .embedding ? modelStore.selectedEmbeddingModel : modelStore.selectedLLMModel
        guard let id, !id.isEmpty, id != selected.id else { return selected }
        guard let model = modelStore.model(id: id, kind: kind) else {
            throw LocalAIOpenAIServiceError.modelNotFound(id)
        }
        return model
    }

    private static func estimatedTokens(_ text: String) -> Int {
        max(1, text.utf8.count / 4)
    }
}
