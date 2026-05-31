import Foundation
import Testing
@testable import ClaudeStats

@Suite("Memory project sorting")
struct MemoryProjectSortingTests {
    @Test("Sort modes order projects with stable fallbacks")
    func sortModesOrderProjectsWithStableFallbacks() throws {
        let alpha = project("/repos/alpha", updatedAt: 100)
        let beta = project("/repos/beta", updatedAt: 300)
        let gamma = project("/repos/gamma", updatedAt: nil)
        let global = project("Global", updatedAt: 500)
        let projects = [gamma, global, alpha, beta]
        let alphaKey = try key("/repos/alpha")
        let betaKey = try key("/repos/beta")
        let gammaKey = try key("/repos/gamma")

        let metadata = MemoryProjectSortMetadata(
            gitCommitDatesByProjectID: [
                alphaKey: Date(timeIntervalSince1970: 1_000),
                betaKey: Date(timeIntervalSince1970: 2_000),
            ],
            sessionActivityDatesByProjectID: [
                gammaKey: Date(timeIntervalSince1970: 3_000),
                alphaKey: Date(timeIntervalSince1970: 1_500),
            ]
        )

        #expect(MemoryProjectSorter.sorted(projects: projects, mode: .recentGitCommit, metadata: metadata).map(\.projectID) == [
            "/repos/beta",
            "/repos/alpha",
            "/repos/gamma",
            "Global",
        ])
        #expect(MemoryProjectSorter.sorted(projects: projects, mode: .recentSessionActivity, metadata: metadata).map(\.projectID) == [
            "/repos/gamma",
            "/repos/alpha",
            "/repos/beta",
            "Global",
        ])
        #expect(MemoryProjectSorter.sorted(projects: projects, mode: .alphabetical, metadata: metadata).map(\.projectID) == [
            "/repos/alpha",
            "/repos/beta",
            "/repos/gamma",
            "Global",
        ])
        #expect(MemoryProjectSorter.sorted(projects: projects, mode: .recentMemoryUpdate, metadata: metadata).map(\.projectID) == [
            "Global",
            "/repos/beta",
            "/repos/alpha",
            "/repos/gamma",
        ])
    }

    @Test("Ties fall back to name then project id")
    func tiesFallBackToNameThenProjectID() {
        let first = project("/repos/duplicate-a", updatedAt: 10)
        let second = project("/work/duplicate-a", updatedAt: 10)
        let alpha = project("/repos/alpha", updatedAt: 10)

        let sorted = MemoryProjectSorter.sorted(
            projects: [second, first, alpha],
            mode: .recentMemoryUpdate,
            metadata: .empty
        )

        #expect(sorted.map(\.projectID) == [
            "/repos/alpha",
            "/repos/duplicate-a",
            "/work/duplicate-a",
        ])
    }

    private func project(_ projectID: String, updatedAt: Double?) -> CodeMemoryProject {
        CodeMemoryProject(
            projectID: projectID,
            memoryCount: 0,
            totalMemoryCount: 0,
            proposalCount: 0,
            updatedAt: updatedAt
        )
    }

    private func key(_ path: String) throws -> String {
        try #require(MemoryProjectIdentity.normalizedPathKey(for: path))
    }
}
