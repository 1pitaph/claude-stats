import Testing
import Foundation
@testable import ClaudeStats

@Suite("CodexTranscriptParser")
struct CodexTranscriptParserTests {

    private func parseSample() async throws -> SessionStats {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        try TempDir.write(CodexSampleTranscript.text, to: url)
        let stats = await CodexTranscriptParser(pricing: CodexSampleTranscript.pricing)
            .parse(transcriptAt: url, fallbackTitle: "fallback")
        return try #require(stats)
    }

    private func parseLines(_ lines: [String], pricing: ModelPricing) async throws -> SessionStats {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        try TempDir.write(lines.joined(separator: "\n") + "\n", to: url)
        let stats = await CodexTranscriptParser(pricing: pricing)
            .parse(transcriptAt: url, fallbackTitle: "fallback")
        return try #require(stats)
    }

    @Test("Sums turn deltas per model, splitting cached input tokens out")
    func tokenTotals() async throws {
        let stats = try await parseSample()
        #expect(stats.models.count == 1)
        let m = try #require(stats.models.first)
        #expect(m.model == CodexSampleTranscript.model)
        // delta1: input 1100 (1000 cached → 100 uncached), output 200
        // delta2: input 300 (100 cached → 200 uncached), output 50
        #expect(m.usage.inputTokens == 300)
        #expect(m.usage.outputTokens == 250)
        #expect(m.usage.cacheReadTokens == 1100)
        #expect(m.usage.total == 1650)
        // cost = 300/1e6*10 + 250/1e6*20 + 1100/1e6*1
        #expect(abs(m.estimatedCost - (0.003 + 0.005 + 0.0011)) < 1e-9)
    }

    @Test("Codex cache rate uses cached input over total prompt input")
    func codexCacheRate() async throws {
        let stats = try await parseSample()
        let usage = try #require(stats.models.first?.usage)
        let provider = CodexProvider(
            paths: CodexPaths(homeDirectory: URL(fileURLWithPath: "/tmp/codex-test", isDirectory: true)),
            pricing: CodexSampleTranscript.pricing
        )

        let rate = try #require(provider.cacheHitRate(for: usage))
        #expect(abs(rate - (1100.0 / 1400.0)) < 1e-9)
    }

    @Test("Applies GPT-5.4 long-context pricing per turn")
    func gpt54LongContextCostPerTurn() async throws {
        let stats = try await parseLines(Self.gpt54TranscriptLines([
            (timestamp: "2026-01-10T09:00:08.000Z", input: 1_000, cached: 200, output: 100),
            (timestamp: "2026-01-10T09:01:08.000Z", input: 272_001, cached: 100_000, output: 100),
        ]), pricing: Self.gpt54Pricing)

        let model = try #require(stats.models.first)
        #expect(model.model == "gpt-5.4")
        #expect(model.usage.inputTokens == 172_801)
        #expect(model.usage.outputTokens == 200)
        #expect(model.usage.cacheReadTokens == 100_200)
        #expect(model.usage.total == 273_201)

        let shortCost = (800.0 / 1_000_000.0 * 2.5)
            + (100.0 / 1_000_000.0 * 15.0)
            + (200.0 / 1_000_000.0 * 0.25)
        let longCost = (172_001.0 / 1_000_000.0 * 5.0)
            + (100.0 / 1_000_000.0 * 22.5)
            + (100_000.0 / 1_000_000.0 * 0.5)
        #expect(abs(model.estimatedCost - (shortCost + longCost)) < 1e-9)
    }

    @Test("Aggregate GPT-5.4 usage does not trigger long-context pricing")
    func aggregateUsageDoesNotTriggerLongContextPricing() async throws {
        let stats = try await parseLines(Self.gpt54TranscriptLines([
            (timestamp: "2026-01-10T09:00:08.000Z", input: 200_000, cached: 0, output: 0),
            (timestamp: "2026-01-10T09:01:08.000Z", input: 200_000, cached: 0, output: 0),
        ]), pricing: Self.gpt54Pricing)

        let model = try #require(stats.models.first)
        #expect(model.usage.inputTokens == 400_000)
        #expect(abs(model.estimatedCost - 1.0) < 1e-9)
    }

    @Test("Counts user + agent messages, prefers thread name as title")
    func messagesAndTitle() async throws {
        let stats = try await parseSample()
        #expect(stats.messageCount == 4)
        #expect(stats.title == CodexSampleTranscript.threadName)
    }

    @Test("Extracts displayable conversation messages")
    func displayMessages() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        try TempDir.write(CodexSampleTranscript.text, to: url)

        let messages = await CodexTranscriptParser(pricing: CodexSampleTranscript.pricing)
            .messages(transcriptAt: url)

        #expect(messages.map(\.role) == [.user, .assistant, .user, .assistant])
        #expect(messages.map(\.text) == ["please refactor the parser", "on it", "more please", "sure"])
        #expect(messages.first?.timestamp == (try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T09:00:02.000Z")))
    }

    @Test("Extracts tolerant executed command schemas and ignores prose")
    func executedCommands() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        let lines = [
            #"{"timestamp":"2026-01-10T09:00:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"I will run bash scripts/run-tests.sh later."}}"#,
            #"{"timestamp":"2026-01-10T09:00:01.000Z","type":"event_msg","payload":{"type":"tool_call","name":"shell","arguments":"{\"command\":\"git status\"}"}}"#,
            #"{"timestamp":"2026-01-10T09:00:02.000Z","type":"exec_command","payload":{"cmd":"npm test"}}"#,
            #"{"timestamp":"2026-01-10T09:00:03.000Z","type":"event_msg","payload":{"type":"tool_call","tool_name":"terminal","input":{"shell_command":"swift test"}}}"#,
        ]
        try TempDir.write(lines.joined(separator: "\n") + "\n", to: url)

        let commands = await CodexTranscriptParser(pricing: CodexSampleTranscript.pricing)
            .executedCommands(transcriptAt: url)

        #expect(commands.map(\.command) == ["git status", "npm test", "swift test"])
    }

    @Test("First/last activity span the transcript; timeline has one bucket per hour")
    func activityWindow() async throws {
        let stats = try await parseSample()
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        #expect(stats.firstActivity == (try iso.parse("2026-01-10T09:00:00.000Z")))
        #expect(stats.lastActivity == (try iso.parse("2026-01-10T10:31:00.000Z")))
        #expect(stats.timeline.count == 2)
        #expect(stats.activityIntervals.count == 2)
    }

    @Test("Empty / metadata-only transcript yields nil")
    func emptyTranscript() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        try TempDir.write(#"{"timestamp":"2026-01-10T09:00:00.000Z","type":"session_meta","payload":{"id":"x","cwd":"/tmp"}}"# + "\n", to: url)
        let stats = await CodexTranscriptParser(pricing: CodexSampleTranscript.pricing)
            .parse(transcriptAt: url, fallbackTitle: "fallback")
        #expect(stats == nil)
    }

    private static let gpt54Pricing = ModelPricing(
        rates: [
            "gpt-5.4": ModelPricing.Rates(
                input: 2.5,
                output: 15.0,
                cacheWrite5m: 2.5,
                cacheWrite1h: 2.5,
                cacheRead: 0.25,
                longContext: ModelPricing.Rates.LongContext(
                    thresholdInputTokens: 272_000,
                    input: 5.0,
                    output: 22.5,
                    cacheWrite5m: 5.0,
                    cacheWrite1h: 5.0,
                    cacheRead: 0.5
                )
            ),
        ],
        defaultRate: ModelPricing.Rates(input: 1, output: 2, cacheWrite5m: 1, cacheWrite1h: 1, cacheRead: 1)
    )

    private static func gpt54TranscriptLines(_ turns: [(timestamp: String, input: Int, cached: Int, output: Int)]) -> [String] {
        var lines = [
            #"{"timestamp":"2026-01-10T09:00:00.000Z","type":"session_meta","payload":{"id":"long-context","cwd":"/tmp"}}"#,
            #"{"timestamp":"2026-01-10T09:00:01.000Z","type":"turn_context","payload":{"turn_id":"t1","cwd":"/tmp","model":"gpt-5.4"}}"#,
        ]
        for turn in turns {
            lines.append(#"{"timestamp":"\#(turn.timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\#(turn.input),"cached_input_tokens":\#(turn.cached),"output_tokens":\#(turn.output),"reasoning_output_tokens":0,"total_tokens":\#(turn.input + turn.output)}}}}"#)
        }
        return lines
    }
}
