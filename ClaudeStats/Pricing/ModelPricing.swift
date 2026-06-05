import Foundation

/// Immutable per-million-token pricing table. Loaded once at launch from the
/// bundled `default-pricing.json`, optionally overlaid by a user file at
/// `~/.claude-stats/pricing.json`. Being a value type with only `let`
/// storage it is `Sendable` and safe to use from the off-main parsers.
struct ModelPricing: Sendable, Hashable {
    enum ServiceTier: Sendable, Hashable {
        case standard
        case priority
        case fast

        static func parse(serviceTier: String?, speed: String?, fast: Bool?) -> ServiceTier? {
            if fast == true { return .fast }
            for raw in [serviceTier, speed] {
                switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "priority":
                    return .priority
                case "fast":
                    return .fast
                case "standard", "default":
                    return .standard
                default:
                    continue
                }
            }
            return nil
        }
    }

    /// Per-1,000,000-token rates for each token category. Base, priority, and
    /// fast rates are USD; `codexCredits` and `codexCreditsFast` use OpenAI's
    /// Codex credit units.
    struct Rates: Sendable, Hashable, Codable {
        struct LongContext: Sendable, Hashable, Codable {
            var thresholdInputTokens: Int
            var input: Double
            var output: Double
            var cacheWrite5m: Double
            var cacheWrite1h: Double
            var cacheRead: Double
        }

        struct Tier: Sendable, Hashable, Codable {
            var input: Double
            var output: Double
            var cacheWrite5m: Double
            var cacheWrite1h: Double
            var cacheRead: Double
            var longContext: LongContext? = nil

            static func derived(input: Double, output: Double) -> Tier {
                Tier(input: input, output: output,
                     cacheWrite5m: input * 1.25, cacheWrite1h: input * 2.0, cacheRead: input * 0.1)
            }
        }

        var input: Double
        var output: Double
        var cacheWrite5m: Double
        var cacheWrite1h: Double
        var cacheRead: Double
        var longContext: LongContext? = nil
        var priority: Tier? = nil
        var fast: Tier? = nil
        var codexCredits: Tier? = nil
        var codexCreditsFast: Tier? = nil

        var standard: Tier {
            Tier(input: input,
                 output: output,
                 cacheWrite5m: cacheWrite5m,
                 cacheWrite1h: cacheWrite1h,
                 cacheRead: cacheRead,
                 longContext: longContext)
        }

        /// Derive cache rates from the input rate using Anthropic's ratios
        /// (5m write = 1.25×, 1h write = 2×, read = 0.1×) when a config file
        /// only specifies input/output.
        static func derived(input: Double, output: Double) -> Rates {
            Rates(input: input, output: output,
                  cacheWrite5m: input * 1.25, cacheWrite1h: input * 2.0, cacheRead: input * 0.1)
        }
    }

    let rates: [String: Rates]
    let defaultRate: Rates

    init(rates: [String: Rates], defaultRate: Rates) {
        self.rates = rates
        self.defaultRate = defaultRate
    }

    // MARK: Lookup

    /// Exact match if we have one, otherwise a fuzzy fallback by family
    /// (`opus` / `sonnet` / `haiku` / `gpt` / `gemini`), otherwise the
    /// configured default.
    func rate(for model: String) -> Rates {
        if let exact = rates[model] { return exact }
        let lower = model.lowercased()
        if let prefixed = rates
            .keys
            .sorted(by: { $0.count > $1.count })
            .first(where: {
                let key = $0.lowercased()
                guard lower.hasPrefix(key + "-") else { return false }
                let suffix = lower.dropFirst(key.count + 1)
                let yearPrefix = suffix.prefix(4)
                return yearPrefix.count == 4 && yearPrefix.allSatisfy(\.isNumber)
            }),
           let r = rates[prefixed] {
            return r
        }
        func first(containing needle: String) -> Rates? {
            rates.first { $0.key.lowercased().contains(needle) }?.value
        }
        if lower.contains("opus"), let r = first(containing: "opus") { return r }
        if lower.contains("haiku"), let r = first(containing: "haiku") { return r }
        if lower.contains("sonnet"), let r = first(containing: "sonnet") { return r }
        if lower.contains("gpt") || lower.contains("o1") || lower.contains("o3") || lower.contains("o4") || lower.contains("codex"),
           let r = first(containing: "gpt") { return r }
        if lower.contains("gemini"), let r = first(containing: "gemini") { return r }
        if lower.contains("kimi") || lower.contains("moonshot"), let r = first(containing: "kimi") { return r }
        if lower.contains("minimax") || lower.contains("abab"), let r = first(containing: "minimax") { return r }
        return defaultRate
    }

    func hasExactRate(for model: String) -> Bool { rates[model] != nil }

    /// Estimated USD cost for a chunk of usage attributed to `model`.
    func cost(model: String, usage: TokenUsage) -> Double {
        cost(model: model, usage: usage, serviceTier: .standard) ?? 0
    }

    func costEstimate(model: String, usage: TokenUsage) -> CostEstimate {
        let standard = cost(model: model, usage: usage)
        return CostEstimate(
            standardAPI: standard,
            codexCredits: creditCost(model: model, usage: usage, contextInputTokens: nil)
        )
    }

    /// Claude Code writes enough metadata for a slightly richer estimate on a
    /// few request types. Keep the standard API estimate as the baseline, then
    /// add only billable details that are explicit in the transcript.
    func claudeCostEstimate(model: String,
                            usage: TokenUsage,
                            speed: String?,
                            webSearchRequests: Int) -> CostEstimate {
        let standard = cost(model: model, usage: usage)
        var detailed = standard

        if ServiceTier.parse(serviceTier: nil, speed: speed, fast: nil) == .fast,
           let fast = rate(for: model).fast {
            detailed = cost(usage: usage, rates: fast, contextInputTokens: nil)
        }

        detailed += Double(webSearchRequests) * Self.claudeWebSearchUSD
        return CostEstimate(standardAPI: standard, detailedBilling: detailed)
    }

    /// Estimated cost for a Codex turn. The standard USD estimate always uses
    /// the public API rate; detailed billing switches to a provider tier only
    /// when the transcript exposed it; credits use OpenAI's Codex rate card.
    func codexCostEstimate(model: String,
                           usage: TokenUsage,
                           contextInputTokens: Int,
                           serviceTier: ServiceTier?) -> CostEstimate {
        let standard = cost(model: model, usage: usage, contextInputTokens: contextInputTokens)
        let detailed: Double
        switch serviceTier {
        case .priority:
            detailed = cost(model: model, usage: usage, serviceTier: .priority, contextInputTokens: contextInputTokens) ?? standard
        case .fast:
            detailed = cost(model: model, usage: usage, serviceTier: .fast, contextInputTokens: contextInputTokens) ?? standard
        case .standard, .none:
            detailed = standard
        }
        return CostEstimate(
            standardAPI: standard,
            detailedBilling: detailed,
            codexCredits: creditCost(model: model,
                                     usage: usage,
                                     contextInputTokens: contextInputTokens,
                                     serviceTier: serviceTier)
        )
    }

    /// Estimated USD cost for one request/turn, using long-context rates when
    /// the raw prompt input for that turn crosses the model's published
    /// threshold.
    func cost(model: String, usage: TokenUsage, contextInputTokens: Int) -> Double {
        cost(usage: usage, rates: rate(for: model).standard, contextInputTokens: contextInputTokens)
    }

    private func cost(model: String,
                      usage: TokenUsage,
                      serviceTier: ServiceTier,
                      contextInputTokens: Int? = nil) -> Double? {
        let r = rate(for: model)
        let tier: Rates.Tier?
        switch serviceTier {
        case .standard: tier = r.standard
        case .priority: tier = r.priority
        case .fast: tier = r.fast
        }
        guard let tier else { return nil }
        return cost(usage: usage, rates: tier, contextInputTokens: contextInputTokens)
    }

    private func creditCost(model: String,
                            usage: TokenUsage,
                            contextInputTokens: Int?,
                            serviceTier: ServiceTier? = nil) -> Double? {
        let rate = rate(for: model)
        let credits: Rates.Tier?
        if serviceTier == .fast {
            credits = rate.codexCreditsFast ?? rate.codexCredits
        } else {
            credits = rate.codexCredits
        }
        guard let credits else { return nil }
        return cost(usage: usage, rates: credits, contextInputTokens: contextInputTokens)
    }

    private func cost(usage: TokenUsage, rates: Rates.Tier, contextInputTokens: Int?) -> Double {
        let effective = effectiveRates(rates, contextInputTokens: contextInputTokens)
        let perMillion = 1_000_000.0
        return Double(usage.inputTokens) / perMillion * effective.input
            + Double(usage.outputTokens) / perMillion * effective.output
            + Double(usage.cacheReadTokens) / perMillion * effective.cacheRead
            + Double(usage.cacheCreation5mTokens) / perMillion * effective.cacheWrite5m
            + Double(usage.cacheCreation1hTokens) / perMillion * effective.cacheWrite1h
    }

    private func effectiveRates(_ rates: Rates.Tier, contextInputTokens: Int?) -> Rates.Tier {
        guard let contextInputTokens,
              let long = rates.longContext,
              contextInputTokens > long.thresholdInputTokens else {
            return rates
        }
        return Rates.Tier(input: long.input,
                          output: long.output,
                          cacheWrite5m: long.cacheWrite5m,
                          cacheWrite1h: long.cacheWrite1h,
                          cacheRead: long.cacheRead)
    }

    private static let claudeWebSearchUSD = 10.0 / 1_000.0

    // MARK: Loading

    private struct File: Codable {
        var _comment: String?
        var models: [String: Rates]
        var defaultPricing: Rates?

        enum CodingKeys: String, CodingKey {
            case _comment = "comment"
            case models
            case defaultPricing = "default_pricing"
        }
    }

    /// Hard-coded last-resort table so the app still works if the bundled
    /// resource is missing.
    static let fallback = ModelPricing(
        rates: [
            "claude-opus-4-8": Rates(input: 5,
                                     output: 25,
                                     cacheWrite5m: 6.25,
                                     cacheWrite1h: 10,
                                     cacheRead: 0.5,
                                     fast: Rates.Tier(input: 10,
                                                      output: 50,
                                                      cacheWrite5m: 12.5,
                                                      cacheWrite1h: 20,
                                                      cacheRead: 1)),
            "claude-opus-4-7": Rates.derived(input: 5, output: 25),
            "claude-sonnet-4-6": Rates.derived(input: 3, output: 15),
            "claude-haiku-4-5": Rates.derived(input: 1, output: 5),
        ],
        defaultRate: Rates.derived(input: 3, output: 15)
    )

    /// Load the bundled defaults, then overlay `~/.claude-stats/pricing.json`
    /// if the user has one. Never throws — falls back to ``fallback``.
    static func loadDefault(bundle: Bundle = .main,
                            userFile: URL? = userPricingFileURL()) -> ModelPricing {
        var merged = decode(bundle.url(forResource: "default-pricing", withExtension: "json")) ?? fallback.asFile()
        if let userFile, let user = decode(userFile) {
            merged.models.merge(user.models) { _, override in override }
            if let d = user.defaultPricing { merged.defaultPricing = d }
        }
        return ModelPricing(rates: merged.models, defaultRate: merged.defaultPricing ?? fallback.defaultRate)
    }

    static func userPricingFileURL() -> URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-stats", isDirectory: true)
            .appendingPathComponent("pricing.json")
    }

    private static func decode(_ url: URL?) -> File? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }

    private func asFile() -> File { File(_comment: nil, models: rates, defaultPricing: defaultRate) }
}
