import Testing
@testable import ClaudeStats

@Suite("Format")
struct FormattersTests {
    @Test("signed token deltas use compact units")
    func signedTokenDeltasUseCompactUnits() {
        #expect(Format.signedTokens(1_234_567) == "+1.23M")
        #expect(Format.signedTokens(-4_560) == "-4.56K")
        #expect(Format.signedTokens(0) == "0")
    }
}
