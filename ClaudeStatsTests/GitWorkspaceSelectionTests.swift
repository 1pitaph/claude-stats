import Testing
@testable import ClaudeStats

@Suite("GitWorkspaceSelection")
struct GitWorkspaceSelectionTests {
    @Test("all selection round-trips through SceneStorage raw value")
    func allRoundTrip() {
        let selection = GitWorkspaceSelection.all

        #expect(selection.rawValue == "all")
        #expect(GitWorkspaceSelection(rawValue: selection.rawValue) == .all)
        #expect(selection.repoID == nil)
    }

    @Test("repo selection round-trips through prefixed raw value")
    func repoRoundTrip() {
        let selection = GitWorkspaceSelection.repo("/Users/dev/project")
        let reloaded = GitWorkspaceSelection(rawValue: selection.rawValue)

        #expect(selection.rawValue == "repo:/Users/dev/project")
        #expect(reloaded == selection)
        #expect(reloaded.repoID == "/Users/dev/project")
    }

    @Test("legacy repo raw value remains compatible")
    func legacyRepoRawValue() {
        let selection = GitWorkspaceSelection(rawValue: "/Users/dev/legacy")

        #expect(selection == .repo("/Users/dev/legacy"))
        #expect(selection.rawValue == "repo:/Users/dev/legacy")
    }

    @Test("invalid empty raw values fall back to all repos")
    func invalidRawFallback() {
        #expect(GitWorkspaceSelection(rawValue: "") == .all)
        #expect(GitWorkspaceSelection(rawValue: "repo:") == .all)
    }
}
