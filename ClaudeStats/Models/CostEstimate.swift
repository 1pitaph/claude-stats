import Foundation

enum CostEstimationMode: String, CaseIterable, Sendable, Identifiable, Hashable {
    case standardAPI
    case detailedBilling
    case codexCredits

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standardAPI: L10n.string("cost_mode.api_estimate", defaultValue: "API-equivalent USD")
        case .detailedBilling: L10n.string("cost_mode.detailed_billing", defaultValue: "Detailed billing")
        case .codexCredits: L10n.string("cost_mode.codex_credits", defaultValue: "Codex Credits")
        }
    }
}

struct CostEstimate: Sendable, Hashable {
    var standardAPI: Double
    var detailedBilling: Double
    var codexCredits: Double?

    static let zero = CostEstimate(standardAPI: 0, detailedBilling: 0, codexCredits: nil)

    init(standardAPI: Double, detailedBilling: Double? = nil, codexCredits: Double? = nil) {
        self.standardAPI = standardAPI
        self.detailedBilling = detailedBilling ?? standardAPI
        self.codexCredits = codexCredits
    }

    func value(for mode: CostEstimationMode) -> Double {
        switch mode {
        case .standardAPI: standardAPI
        case .detailedBilling: detailedBilling
        case .codexCredits: codexCredits ?? standardAPI
        }
    }

    func usesCredits(for mode: CostEstimationMode) -> Bool {
        mode == .codexCredits && codexCredits != nil
    }

    static func + (lhs: CostEstimate, rhs: CostEstimate) -> CostEstimate {
        let credits: Double?
        if lhs.codexCredits == nil && rhs.codexCredits == nil {
            credits = nil
        } else {
            credits = (lhs.codexCredits ?? 0) + (rhs.codexCredits ?? 0)
        }
        return CostEstimate(
            standardAPI: lhs.standardAPI + rhs.standardAPI,
            detailedBilling: lhs.detailedBilling + rhs.detailedBilling,
            codexCredits: credits
        )
    }

    static func += (lhs: inout CostEstimate, rhs: CostEstimate) { lhs = lhs + rhs }
}
