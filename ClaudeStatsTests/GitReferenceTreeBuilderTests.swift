import Testing
@testable import ClaudeStats

@Suite("GitReferenceTreeBuilder")
struct GitReferenceTreeBuilderTests {
    @Test("selection raw values round trip")
    func selectionRoundTrip() {
        let reference = GitReferenceSelection.reference("refs/heads/main")
        let reflog = GitReferenceSelection.reflog("HEAD@{2026-06-30 10:00:00 +0800}#1")

        #expect(GitReferenceSelection(rawValue: reference.rawValue) == reference)
        #expect(GitReferenceSelection(rawValue: reflog.rawValue) == reflog)
        #expect(GitReferenceSelection(rawValue: "") == .none)
        #expect(GitReferenceSelection(rawValue: "refs/tags/v1") == .reference("refs/tags/v1"))
    }

    @Test("tree flattens sections and nested tag paths without OutlineGroup")
    func nestedTagRows() throws {
        let tag = reference(kind: .tag, fullName: "refs/tags/list/github49", shortName: "list/github49")
        let snapshot = snapshot(tags: [tag])
        var expanded = GitReferenceTreeBuilder.defaultExpandedIDs
        expanded.insert(GitReferenceTreeBuilder.tagSectionID)
        expanded.insert(GitReferenceTreeBuilder.tagFolderID("list"))

        let rows = GitReferenceTreeBuilder.rows(snapshot: snapshot, selection: .reference(tag.fullName), expandedIDs: expanded)

        #expect(rows.contains { $0.id == GitReferenceTreeBuilder.tagSectionID && $0.title == "Tags" })
        let folder = try #require(rows.first { $0.id == GitReferenceTreeBuilder.tagFolderID("list") })
        #expect(folder.kind == .folder)
        #expect(folder.depth == 1)
        #expect(folder.isExpanded)

        let tagRow = try #require(rows.first { $0.referenceFullName == tag.fullName })
        #expect(tagRow.title == "github49")
        #expect(tagRow.depth == 2)
        #expect(tagRow.isSelected)
    }

    @Test("reflogs and tags are collapsed by default")
    func reflogsAndTagsCollapsedByDefault() throws {
        let reflog = GitReflogEntry(
            id: "HEAD@{0}",
            selector: "HEAD@{0}",
            shortSelector: "HEAD@{0}",
            targetHash: "abcdef123456",
            message: "commit: Initial",
            dateLabel: nil
        )
        let tag = reference(kind: .tag, fullName: "refs/tags/v1", shortName: "v1")
        let rows = GitReferenceTreeBuilder.rows(
            snapshot: snapshot(tags: [tag], reflogs: [reflog]),
            selection: .none,
            expandedIDs: GitReferenceTreeBuilder.defaultExpandedIDs
        )

        let reflogSection = try #require(rows.first { $0.id == GitReferenceTreeBuilder.reflogSectionID })
        let tagSection = try #require(rows.first { $0.id == GitReferenceTreeBuilder.tagSectionID })
        #expect(!reflogSection.isExpanded)
        #expect(!tagSection.isExpanded)
        #expect(rows.contains { $0.reflogSelector == reflog.id } == false)
        #expect(rows.contains { $0.referenceFullName == tag.fullName } == false)
    }

    @Test("tags sort newest first inside expanded folders")
    func tagsSortNewestFirst() throws {
        let older = reference(kind: .tag, fullName: "refs/tags/list/github40", shortName: "list/github40", sortTimestamp: 40)
        let newer = reference(kind: .tag, fullName: "refs/tags/list/github49", shortName: "list/github49", sortTimestamp: 49)
        let snapshot = snapshot(tags: [older, newer])
        var expanded = GitReferenceTreeBuilder.defaultExpandedIDs
        expanded.insert(GitReferenceTreeBuilder.tagSectionID)
        expanded.insert(GitReferenceTreeBuilder.tagFolderID("list"))

        let rows = GitReferenceTreeBuilder.rows(snapshot: snapshot, selection: .none, expandedIDs: expanded)
        let tagTitles = rows
            .filter { $0.referenceFullName?.hasPrefix("refs/tags/list/") == true }
            .map(\.title)

        #expect(tagTitles == ["github49", "github40"])
    }

    @Test("collapsed sections hide child rows")
    func collapseSections() {
        let branch = reference(kind: .localBranch, fullName: "refs/heads/main", shortName: "main", isCurrent: true)
        let snapshot = snapshot(localBranches: [branch])
        var expanded = GitReferenceTreeBuilder.defaultExpandedIDs
        expanded.remove(GitReferenceTreeBuilder.localSectionID)

        let rows = GitReferenceTreeBuilder.rows(snapshot: snapshot, selection: .none, expandedIDs: expanded)

        #expect(rows.contains { $0.id == GitReferenceTreeBuilder.localSectionID })
        #expect(rows.contains { $0.referenceFullName == branch.fullName } == false)
    }

    @Test("remote groups expand independently")
    func remoteGroupsExpandIndependently() throws {
        let remote = reference(kind: .remoteBranch, fullName: "refs/remotes/origin/main", shortName: "origin/main")
        let snapshot = snapshot(remoteGroups: ["origin": [remote]])
        let collapsed = GitReferenceTreeBuilder.rows(
            snapshot: snapshot,
            selection: .none,
            expandedIDs: GitReferenceTreeBuilder.defaultExpandedIDs
        )
        #expect(collapsed.contains { $0.referenceFullName == remote.fullName } == false)

        var expanded = GitReferenceTreeBuilder.defaultExpandedIDs
        expanded.insert(GitReferenceTreeBuilder.remoteGroupID("origin"))
        let rows = GitReferenceTreeBuilder.rows(snapshot: snapshot, selection: .none, expandedIDs: expanded)
        let remoteRow = try #require(rows.first { $0.referenceFullName == remote.fullName })
        #expect(remoteRow.title == "main")
        #expect(remoteRow.depth == 2)
    }

    @Test("large tag list keeps stable row identity")
    func largeTagListStableIDs() {
        let tags = Array(0..<120).map { value -> GitReference in
            let suffix = String(value)
            return reference(
                kind: .tag,
                fullName: "refs/tags/list/github\(suffix)",
                shortName: "list/github\(suffix)",
                hash: "hash\(suffix)",
                sortTimestamp: value
            )
        }
        let snapshot = snapshot(tags: tags)
        var expanded = GitReferenceTreeBuilder.defaultExpandedIDs
        expanded.insert(GitReferenceTreeBuilder.tagSectionID)
        expanded.insert(GitReferenceTreeBuilder.tagFolderID("list"))

        let first = GitReferenceTreeBuilder.rows(snapshot: snapshot, selection: .none, expandedIDs: expanded).map(\.id)
        let second = GitReferenceTreeBuilder.rows(snapshot: snapshot, selection: .none, expandedIDs: expanded).map(\.id)

        #expect(first == second)
        #expect(Set(first).count == first.count)
        #expect(first.contains("ref:refs/tags/list/github49"))
    }
}

private func snapshot(
    localBranches: [GitReference] = [],
    remoteGroups: [String: [GitReference]] = [:],
    tags: [GitReference] = [],
    reflogs: [GitReflogEntry] = []
) -> GitReferenceSnapshot {
    GitReferenceSnapshot(
        localBranches: localBranches,
        remoteGroups: remoteGroups,
        remotes: remoteGroups.keys.map { GitRemoteInfo(name: $0, fetchURL: nil, pushURL: nil) },
        tags: tags,
        reflogs: reflogs,
        headHash: nil,
        currentBranchName: localBranches.first(where: { $0.isCurrent })?.shortName,
        isDetachedHead: false,
        reflogLimit: reflogs.count,
        hasMoreReflogs: false
    )
}

private func reference(
    kind: GitReferenceKind,
    fullName: String,
    shortName: String,
    hash: String = "abcdef123456",
    peeledHash: String? = nil,
    isCurrent: Bool = false,
    sortTimestamp: Int? = nil
) -> GitReference {
    GitReference(
        kind: kind,
        fullName: fullName,
        shortName: shortName,
        objectHash: hash,
        peeledHash: peeledHash,
        isCurrent: isCurrent,
        upstreamShortName: nil,
        upstreamFullName: nil,
        aheadBehind: nil,
        sortTimestamp: sortTimestamp
    )
}
