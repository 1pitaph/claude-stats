import Foundation

enum TranscriptTermKind: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case language
    case framework
    case api
    case typeName
    case function
    case filePath
    case command
    case configKey
    case error
    case workflow
    case general

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .language: "Language"
        case .framework: "Framework"
        case .api: "API"
        case .typeName: "Type"
        case .function: "Function"
        case .filePath: "File"
        case .command: "Command"
        case .configKey: "Config"
        case .error: "Error"
        case .workflow: "Workflow"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .language: "character.book.closed"
        case .framework: "shippingbox"
        case .api: "point.3.connected.trianglepath.dotted"
        case .typeName: "curlybraces"
        case .function: "function"
        case .filePath: "doc.text"
        case .command: "terminal"
        case .configKey: "slider.horizontal.3"
        case .error: "exclamationmark.triangle"
        case .workflow: "arrow.triangle.branch"
        case .general: "tag"
        }
    }
}

enum TranscriptTermSource: String, Codable, Sendable, Hashable {
    case dictionary
    case naturalLanguage
    case jieba
    case code
    case path
    case command
    case error
    case project
}

struct TranscriptRoleCounts: Codable, Hashable, Sendable {
    var user = 0
    var assistant = 0
    var tool = 0
    var system = 0

    mutating func add(_ role: SessionTranscriptMessage.Role, count: Int = 1) {
        switch role {
        case .user: user += count
        case .assistant: assistant += count
        case .tool: tool += count
        case .system: system += count
        }
    }

    var total: Int { user + assistant + tool + system }
}

struct TranscriptSourceCounts: Codable, Hashable, Sendable {
    var dictionary = 0
    var naturalLanguage = 0
    var jieba = 0
    var code = 0
    var path = 0
    var command = 0
    var error = 0
    var project = 0

    mutating func add(_ source: TranscriptTermSource, count: Int = 1) {
        switch source {
        case .dictionary: dictionary += count
        case .naturalLanguage: naturalLanguage += count
        case .jieba: jieba += count
        case .code: code += count
        case .path: path += count
        case .command: command += count
        case .error: error += count
        case .project: project += count
        }
    }

    var total: Int { dictionary + naturalLanguage + jieba + code + path + command + error + project }
}

struct TranscriptTermExample: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let sessionID: String
    let sessionTitle: String
    let projectName: String
    let role: SessionTranscriptMessage.Role
    let excerpt: String
    let timestamp: Date?
}

struct TranscriptTermStats: Codable, Hashable, Identifiable, Sendable {
    var id: String { canonical }

    let canonical: String
    let displayName: String
    let kind: TranscriptTermKind
    let aliases: [String]
    let frequency: Int
    let documentFrequency: Int
    let tfidf: Double
    let roleCounts: TranscriptRoleCounts
    let sourceCounts: TranscriptSourceCounts
    let examples: [TranscriptTermExample]
}

struct TranscriptSessionTerm: Codable, Hashable, Sendable {
    let canonical: String
    let displayName: String
    let kind: TranscriptTermKind
    let frequency: Int
    let weight: Double
    let roleCounts: TranscriptRoleCounts
    let sourceCounts: TranscriptSourceCounts
    let example: TranscriptTermExample?
}

struct TranscriptSessionAnalysis: Codable, Hashable, Identifiable, Sendable {
    var id: String { sessionID }

    let sessionID: String
    let sessionTitle: String
    let projectName: String
    let terms: [TranscriptSessionTerm]

    var topTerms: [TranscriptSessionTerm] {
        Array(terms.sorted { $0.weightedFrequency > $1.weightedFrequency }.prefix(12))
    }

    var commandTerms: [TranscriptSessionTerm] { terms(for: .command) }
    var fileTerms: [TranscriptSessionTerm] { terms(for: .filePath) }
    var errorTerms: [TranscriptSessionTerm] { terms(for: .error) }

    private func terms(for kind: TranscriptTermKind) -> [TranscriptSessionTerm] {
        Array(terms.filter { $0.kind == kind }.sorted { $0.weightedFrequency > $1.weightedFrequency }.prefix(8))
    }
}

extension TranscriptSessionTerm {
    var weightedFrequency: Double { Double(frequency) * weight }
}

struct TranscriptAnalysisEngineInfo: Codable, Hashable, Sendable {
    let tokenizerID: String
    let dictionaryVersion: String
    let displayName: String
    let embeddingStatus: EmbeddingModelStatus
}

enum TranscriptAnalysisProgressPhase: String, Codable, Sendable, Hashable {
    case idle
    case loadingIndex
    case analyzingTranscripts
    case finalizingRanking
    case completed

    var displayName: String {
        switch self {
        case .idle: "Idle"
        case .loadingIndex: "Loading index"
        case .analyzingTranscripts: "Analyzing transcripts"
        case .finalizingRanking: "Finalizing ranking"
        case .completed: "Completed"
        }
    }
}

struct TranscriptAnalysisProgress: Codable, Hashable, Sendable {
    let phase: TranscriptAnalysisProgressPhase
    let total: Int
    let completed: Int
    let reused: Int
    let newCount: Int
    let changed: Int
    let empty: Int
    let deleted: Int
    let currentSessionTitle: String?

    static let idle = TranscriptAnalysisProgress(
        phase: .idle,
        total: 0,
        completed: 0,
        reused: 0,
        newCount: 0,
        changed: 0,
        empty: 0,
        deleted: 0,
        currentSessionTitle: nil
    )

    var analyzedThisRun: Int { newCount + changed }
}

struct TranscriptAnalysisRunSummary: Codable, Hashable, Sendable {
    let reused: Int
    let newCount: Int
    let changed: Int
    let empty: Int
    let deleted: Int
    let analyzed: Int
    let indexUpdatedAt: Date

    static let empty = TranscriptAnalysisRunSummary(
        reused: 0,
        newCount: 0,
        changed: 0,
        empty: 0,
        deleted: 0,
        analyzed: 0,
        indexUpdatedAt: .distantPast
    )
}

struct TranscriptAnalysisSnapshot: Codable, Hashable, Sendable {
    let provider: ProviderKind
    let generatedAt: Date
    let sessionCount: Int
    let analyzedSessionCount: Int
    let terms: [TranscriptTermStats]
    let sessionAnalyses: [TranscriptSessionAnalysis]
    let engine: TranscriptAnalysisEngineInfo
    let dictionarySignature: String
    let runSummary: TranscriptAnalysisRunSummary

    func sessionAnalysis(for sessionID: String) -> TranscriptSessionAnalysis? {
        sessionAnalyses.first { $0.sessionID == sessionID }
    }
}

struct TranscriptEmbeddingCacheRecord: Codable, Hashable, Sendable {
    let sessionID: String
    let chunkID: String
    let modelID: String
    let textHash: String
    let vector: [Float]
    let createdAt: Date
}
