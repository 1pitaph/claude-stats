import Testing
@testable import ClaudeStats

@Suite("WarpWorkspaceSection")
struct WarpWorkspaceSectionTests {
    @Test("Stored raw values resolve with sessions fallback")
    func storedRawValuesResolve() {
        #expect(WarpWorkspaceSection(storedRawValue: "sessions") == .sessions)
        #expect(WarpWorkspaceSection(storedRawValue: "agents") == .agents)
        #expect(WarpWorkspaceSection(storedRawValue: "missing") == .sessions)
    }

    @Test("First pass sections stay stable")
    func firstPassSectionsStayStable() {
        #expect(WarpWorkspaceSection.allCases == [.sessions, .agents, .files, .settings])
    }
}
