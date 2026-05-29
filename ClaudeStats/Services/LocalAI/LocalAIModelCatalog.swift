import Foundation

enum LocalAIModelCatalog {
    static let githubReleaseBaseURL = URL(string: "https://github.com/1pitaph/claude-stats/releases/download/local-models-v1")!

    static let builtInEmbeddingModels: [LocalAIModelManifest] = [
        LocalAIModelManifest(
            id: "multilingual-e5-small-gguf-q8",
            displayName: "Multilingual E5 Small",
            subtitle: "Default semantic search model",
            kind: .embedding,
            runtime: .llamaGGUF,
            modelRevision: "gguf-q8-v1",
            sourceRepo: "intfloat/multilingual-e5-small",
            sourceRevision: "main",
            artifact: .github(
                url: githubReleaseBaseURL.appendingPathComponent("multilingual-e5-small-q8_0.gguf"),
                sha256: "0d5a5a0b0ad84faad6357a6145e769b0661f0efbf53acf74598afc34dab454f4",
                byteCount: 131_953_504
            ),
            licenseName: "MIT",
            licenseURL: URL(string: "https://huggingface.co/intfloat/multilingual-e5-small"),
            dimensions: 384,
            maxTokens: 512,
            minMemoryGB: 8,
            parameterCount: "0.1B",
            pooling: .mean,
            recommendedTier: "Apple Silicon 8GB+",
            isExperimental: false
        ),
        LocalAIModelManifest(
            id: "multilingual-e5-base-gguf-q8",
            displayName: "Multilingual E5 Base",
            subtitle: "Balanced quality model",
            kind: .embedding,
            runtime: .llamaGGUF,
            modelRevision: "gguf-q8-v1",
            sourceRepo: "intfloat/multilingual-e5-base",
            sourceRevision: "main",
            artifact: .github(
                url: githubReleaseBaseURL.appendingPathComponent("multilingual-e5-base-q8_0.gguf"),
                sha256: "548c31b068947aa26b86c8bbfc1f2fabe5233f6d0e1241319832b20a01e5968a",
                byteCount: 303_138_624
            ),
            licenseName: "MIT",
            licenseURL: URL(string: "https://huggingface.co/intfloat/multilingual-e5-base"),
            dimensions: 768,
            maxTokens: 512,
            minMemoryGB: 16,
            parameterCount: "0.3B",
            pooling: .mean,
            recommendedTier: "Apple Silicon 16GB+",
            isExperimental: false
        ),
        LocalAIModelManifest(
            id: "bge-m3-gguf",
            displayName: "BGE M3",
            subtitle: "Phase 3 evaluation candidate",
            kind: .embedding,
            runtime: .llamaGGUF,
            modelRevision: "eval-v1",
            sourceRepo: "BAAI/bge-m3",
            sourceRevision: "main",
            artifact: .github(
                url: githubReleaseBaseURL.appendingPathComponent("bge-m3-Q8_0.gguf"),
                sha256: "950f4a8e5e19477a6d3c26d2f162233c20002c601f75e4b002e3239997821167",
                byteCount: 634_553_760
            ),
            licenseName: "MIT",
            licenseURL: URL(string: "https://huggingface.co/BAAI/bge-m3"),
            dimensions: 1024,
            maxTokens: 8192,
            minMemoryGB: 16,
            parameterCount: "0.6B",
            pooling: .mean,
            recommendedTier: "Evaluation only",
            isExperimental: true
        ),
        LocalAIModelManifest(
            id: "qwen3-embedding-0_6b-gguf-q8",
            displayName: "Qwen3 Embedding 0.6B",
            subtitle: "Phase 3 multilingual/code candidate",
            kind: .embedding,
            runtime: .llamaGGUF,
            modelRevision: "gguf-q8-v1",
            sourceRepo: "Qwen/Qwen3-Embedding-0.6B",
            sourceRevision: "main",
            artifact: .github(
                url: githubReleaseBaseURL.appendingPathComponent("Qwen3-Embedding-0.6B-Q8_0.gguf"),
                sha256: "06507c7b42688469c4e7298b0a1e16deff06caf291cf0a5b278c308249c3e439",
                byteCount: 639_150_592
            ),
            licenseName: "Apache-2.0",
            licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3-Embedding-0.6B"),
            dimensions: 1024,
            maxTokens: 32_768,
            minMemoryGB: 16,
            parameterCount: "0.6B",
            pooling: .last,
            recommendedTier: "Evaluation only",
            isExperimental: true
        ),
    ]

    static let builtInLLMModels: [LocalAIModelManifest] = [
        LocalAIModelManifest(
            id: "qwen3-4b-gguf-q4-k-m",
            displayName: "Qwen3 4B Q4_K_M",
            subtitle: "Small instruction model for low-memory Macs",
            kind: .llm,
            runtime: .llamaGGUF,
            modelRevision: "gguf-q4-k-m-v1",
            sourceRepo: "Qwen/Qwen3-4B",
            sourceRevision: "main",
            artifact: .huggingFace(
                repo: "Qwen/Qwen3-4B-GGUF",
                file: "Qwen3-4B-Q4_K_M.gguf"
            ),
            licenseName: "Apache-2.0",
            licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3-4B"),
            dimensions: 0,
            maxTokens: 32_768,
            minMemoryGB: 8,
            parameterCount: "4B",
            pooling: .mean,
            recommendedTier: "Apple Silicon 8GB+",
            isExperimental: false
        ),
        LocalAIModelManifest(
            id: "qwen3-8b-gguf-q5-k-m",
            displayName: "Qwen3 8B Q5_K_M",
            subtitle: "Balanced local instruction model",
            kind: .llm,
            runtime: .llamaGGUF,
            modelRevision: "gguf-q5-k-m-v1",
            sourceRepo: "Qwen/Qwen3-8B",
            sourceRevision: "main",
            artifact: .huggingFace(
                repo: "Qwen/Qwen3-8B-GGUF",
                file: "Qwen3-8B-Q5_K_M.gguf",
                sha256: "068bae163faa96ad48032daf4e071a6a28fe67d8dcc95367609c2ff165e52738"
            ),
            licenseName: "Apache-2.0",
            licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3-8B"),
            dimensions: 0,
            maxTokens: 32_768,
            minMemoryGB: 16,
            parameterCount: "8B",
            pooling: .mean,
            recommendedTier: "Apple Silicon 16GB+",
            isExperimental: false
        ),
        LocalAIModelManifest(
            id: "qwen3-30b-a3b-instruct-2507-q4-k-m",
            displayName: "Qwen3 30B-A3B 2507 Q4_K_M",
            subtitle: "MoE instruction model for memory extraction",
            kind: .llm,
            runtime: .llamaGGUF,
            modelRevision: "2507-q4-k-m-v1",
            sourceRepo: "Qwen/Qwen3-30B-A3B-Instruct-2507",
            sourceRevision: "main",
            artifact: .huggingFace(
                repo: "bartowski/Qwen_Qwen3-30B-A3B-Instruct-2507-GGUF",
                file: "Qwen_Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf",
                sha256: "382b4f5a164d200f93790ee0e339fae12852896d23485cfb203ce868fea33a95"
            ),
            licenseName: "Apache-2.0",
            licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct-2507"),
            dimensions: 0,
            maxTokens: 262_144,
            minMemoryGB: 32,
            parameterCount: "30B-A3B",
            pooling: .mean,
            recommendedTier: "Apple Silicon 32GB+",
            isExperimental: false
        ),
        LocalAIModelManifest(
            id: "qwen3-30b-a3b-instruct-2507-q5-k-m",
            displayName: "Qwen3 30B-A3B 2507 Q5_K_M",
            subtitle: "Higher-quality MoE instruction model",
            kind: .llm,
            runtime: .llamaGGUF,
            modelRevision: "2507-q5-k-m-v1",
            sourceRepo: "Qwen/Qwen3-30B-A3B-Instruct-2507",
            sourceRevision: "main",
            artifact: .huggingFace(
                repo: "bartowski/Qwen_Qwen3-30B-A3B-Instruct-2507-GGUF",
                file: "Qwen_Qwen3-30B-A3B-Instruct-2507-Q5_K_M.gguf",
                sha256: "3233326af36eddfa675de49ba0d6098cd043f86ddc6de40cdef2b3ac64992581"
            ),
            licenseName: "Apache-2.0",
            licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct-2507"),
            dimensions: 0,
            maxTokens: 262_144,
            minMemoryGB: 48,
            parameterCount: "30B-A3B",
            pooling: .mean,
            recommendedTier: "Apple Silicon 48GB+",
            isExperimental: false
        ),
    ]

    static let builtInModels: [LocalAIModelManifest] = builtInEmbeddingModels + builtInLLMModels

    static func recommendedModelID(memoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String {
        recommendedEmbeddingModelID(memoryBytes: memoryBytes)
    }

    static func recommendedEmbeddingModelID(memoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String {
        let memoryGB = Double(memoryBytes) / 1_073_741_824
        if memoryGB >= 15.5 {
            return "multilingual-e5-base-gguf-q8"
        }
        return "multilingual-e5-small-gguf-q8"
    }

    static func recommendedLLMModelID(memoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String {
        let memoryGB = Double(memoryBytes) / 1_073_741_824
        if memoryGB >= 47.5 {
            return "qwen3-30b-a3b-instruct-2507-q5-k-m"
        }
        if memoryGB >= 31.5 {
            return "qwen3-30b-a3b-instruct-2507-q4-k-m"
        }
        if memoryGB >= 15.5 {
            return "qwen3-8b-gguf-q5-k-m"
        }
        return "qwen3-4b-gguf-q4-k-m"
    }
}
