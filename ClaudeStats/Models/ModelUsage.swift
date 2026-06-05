import Foundation

/// Per-model token totals plus the cost they imply under a ``ModelPricing``
/// table. Cost is baked in at construction so views never need the pricing
/// table in scope.
struct ModelUsage: Sendable, Hashable, Identifiable {
    let model: String
    let messageCount: Int
    let usage: TokenUsage
    let costEstimate: CostEstimate

    var id: String { model }
    var estimatedCost: Double { costEstimate.standardAPI }

    init(model: String, messageCount: Int, usage: TokenUsage, pricing: ModelPricing) {
        self.model = model
        self.messageCount = messageCount
        self.usage = usage
        self.costEstimate = pricing.costEstimate(model: model, usage: usage)
    }

    init(model: String, messageCount: Int, usage: TokenUsage, estimatedCost: Double) {
        self.init(model: model, messageCount: messageCount, usage: usage, costEstimate: CostEstimate(standardAPI: estimatedCost))
    }

    init(model: String, messageCount: Int, usage: TokenUsage, costEstimate: CostEstimate) {
        self.model = model
        self.messageCount = messageCount
        self.usage = usage
        self.costEstimate = costEstimate
    }

    func estimatedCost(for mode: CostEstimationMode) -> Double {
        costEstimate.value(for: mode)
    }

    func estimatedCostUsesCredits(for mode: CostEstimationMode) -> Bool {
        costEstimate.usesCredits(for: mode)
    }
}

extension Array where Element == ModelUsage {
    var dataRevisionID: String {
        map { model in
            [
                model.model,
                String(model.messageCount),
                model.usage.dataRevisionID,
                String(model.costEstimate.standardAPI.bitPattern),
                String(model.costEstimate.detailedBilling.bitPattern),
                model.costEstimate.codexCredits.map { String($0.bitPattern) } ?? "nil",
            ].joined(separator: ":")
        }
        .joined(separator: "|")
    }

    /// Merge per-model entries by model id, preserving already-computed cost.
    /// Cost may be request-sensitive (for example long-context rates), so it
    /// must be summed rather than recomputed from aggregate tokens.
    func merged(pricing _: ModelPricing) -> [ModelUsage] {
        var byModel: [String: (count: Int, usage: TokenUsage, cost: CostEstimate)] = [:]
        for entry in self {
            var acc = byModel[entry.model] ?? (0, .zero, .zero)
            acc.count += entry.messageCount
            acc.usage += entry.usage
            acc.cost += entry.costEstimate
            byModel[entry.model] = acc
        }
        return byModel
            .map { ModelUsage(model: $0.key, messageCount: $0.value.count, usage: $0.value.usage, costEstimate: $0.value.cost) }
            .sorted { $0.usage.total > $1.usage.total }
    }
}
