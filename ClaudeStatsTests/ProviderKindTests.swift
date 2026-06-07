import Foundation
import Testing
@testable import ClaudeStats

@Suite("ProviderKind")
struct ProviderKindTests {

    @Test("Canonical order and full set")
    func allCases() {
        #expect(ProviderKind.allCases == [.claude, .codex, .gemini, .opencode, .kiro, .hermes])
    }

    @Test("Every case has a non-empty asset name, short name, and display name")
    func metadata() {
        for kind in ProviderKind.allCases {
            #expect(!kind.assetName.isEmpty)
            #expect(!kind.monochromeAssetName.isEmpty)
            #expect(!kind.shortName.isEmpty)
            #expect(!kind.displayName.isEmpty)
        }
    }

    @Test("Codable uses raw values")
    func codableRawValueRoundTrip() throws {
        for kind in ProviderKind.allCases {
            let data = try JSONEncoder().encode(kind)
            #expect(String(data: data, encoding: .utf8) == "\"\(kind.rawValue)\"")
            #expect(try JSONDecoder().decode(ProviderKind.self, from: data) == kind)
        }
    }
}
