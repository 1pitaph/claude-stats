import Foundation

/// The set of providers the app reads from. Built once, with the shared
/// ``ModelPricing`` table threaded in so providers can attach cost figures.
///
/// Adding a provider = a new folder under `Providers/`, a `Provider`
/// conformer, and one line in ``init(pricing:)``. The display order in the UI
/// comes from ``ProviderKind/allCases``, not this list.
struct ProviderRegistry: Sendable {
    let providers: [any Provider]

    init(pricing: ModelPricing,
         claudePaths: ClaudePaths = .default,
         codexPaths: CodexPaths = .default,
         openCodePaths: OpenCodePaths = .default,
         kiroPaths: KiroPaths = .default,
         hermesPaths: HermesPaths = .default,
         zcodePaths: ZCodePaths = .default) {
        providers = [
            ClaudeProvider(paths: claudePaths, pricing: pricing),
            CodexProvider(paths: codexPaths, pricing: pricing),
            GeminiProvider(),
            OpenCodeProvider(paths: openCodePaths, pricing: pricing),
            KiroProvider(paths: kiroPaths, pricing: pricing),
            HermesProvider(paths: hermesPaths, pricing: pricing),
            ZCodeProvider(paths: zcodePaths, pricing: pricing),
        ]
    }

    init(providers: [any Provider]) {
        self.providers = providers
    }

    func provider(for kind: ProviderKind) -> (any Provider)? {
        providers.first { $0.kind == kind }
    }
}
