import Foundation

enum GitReferenceKind: String, Sendable, Hashable {
    case localBranch
    case remoteBranch
    case tag
}

struct GitReferenceAheadBehind: Sendable, Hashable, Equatable {
    let ahead: Int
    let behind: Int

    static let zero = GitReferenceAheadBehind(ahead: 0, behind: 0)

    var isZero: Bool { ahead == 0 && behind == 0 }
}

struct GitRemoteInfo: Sendable, Hashable, Identifiable, Equatable {
    let name: String
    let fetchURL: String?
    let pushURL: String?

    var id: String { name }
}

struct GitReference: Sendable, Hashable, Identifiable, Equatable {
    let kind: GitReferenceKind
    let fullName: String
    let shortName: String
    let objectHash: String
    let peeledHash: String?
    let isCurrent: Bool
    let upstreamShortName: String?
    let upstreamFullName: String?
    let aheadBehind: GitReferenceAheadBehind?

    var id: String { fullName }
    var targetHash: String { peeledHash?.nilIfBlank ?? objectHash }
    var shortHash: String { String(targetHash.prefix(7)) }

    var remoteName: String? {
        guard kind == .remoteBranch else { return nil }
        return shortName.split(separator: "/", maxSplits: 1).first.map(String.init)
    }

    var branchName: String? {
        switch kind {
        case .localBranch:
            return shortName
        case .remoteBranch:
            return shortName.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init)
        case .tag:
            return nil
        }
    }
}

struct GitReflogEntry: Sendable, Hashable, Identifiable, Equatable {
    let id: String
    let selector: String
    let shortSelector: String
    let targetHash: String
    let message: String
    let dateLabel: String?

    var shortHash: String { String(targetHash.prefix(7)) }
}

struct GitReferenceSnapshot: Sendable, Hashable, Equatable {
    let localBranches: [GitReference]
    let remoteGroups: [String: [GitReference]]
    let remotes: [GitRemoteInfo]
    let tags: [GitReference]
    let reflogs: [GitReflogEntry]
    let headHash: String?
    let currentBranchName: String?
    let isDetachedHead: Bool
    let reflogLimit: Int
    let hasMoreReflogs: Bool

    static let empty = GitReferenceSnapshot(
        localBranches: [],
        remoteGroups: [:],
        remotes: [],
        tags: [],
        reflogs: [],
        headHash: nil,
        currentBranchName: nil,
        isDetachedHead: false,
        reflogLimit: 0,
        hasMoreReflogs: false
    )

    var remoteNames: [String] {
        let metadataNames = remotes.map(\.name)
        let groupNames = remoteGroups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var seen = Set<String>()
        return (metadataNames + groupNames).filter { seen.insert($0).inserted }
    }

    var allReferences: [GitReference] {
        localBranches + remoteGroups.values.flatMap { $0 } + tags
    }

    func reference(fullName: String) -> GitReference? {
        allReferences.first { $0.fullName == fullName }
    }

    func reflog(id: String) -> GitReflogEntry? {
        reflogs.first { $0.id == id }
    }
}

enum GitReferenceSelection: Sendable, Hashable, Equatable {
    private static let noneRawValue = "none"
    private static let refPrefix = "ref:"
    private static let reflogPrefix = "reflog:"

    case none
    case reference(String)
    case reflog(String)

    init(rawValue: String) {
        if rawValue.isEmpty || rawValue == Self.noneRawValue {
            self = .none
        } else if rawValue.hasPrefix(Self.refPrefix) {
            let value = String(rawValue.dropFirst(Self.refPrefix.count))
            self = value.isEmpty ? .none : .reference(value)
        } else if rawValue.hasPrefix(Self.reflogPrefix) {
            let value = String(rawValue.dropFirst(Self.reflogPrefix.count))
            self = value.isEmpty ? .none : .reflog(value)
        } else {
            self = .reference(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .none:
            return Self.noneRawValue
        case .reference(let fullName):
            return Self.refPrefix + fullName
        case .reflog(let selector):
            return Self.reflogPrefix + selector
        }
    }

    var referenceFullName: String? {
        if case .reference(let fullName) = self { return fullName }
        return nil
    }

    var reflogSelector: String? {
        if case .reflog(let selector) = self { return selector }
        return nil
    }
}

enum GitReferenceTreeRowKind: String, Sendable, Hashable {
    case section
    case remoteGroup
    case folder
    case reference
    case reflog
}

struct GitReferenceTreeRow: Sendable, Hashable, Identifiable, Equatable {
    let id: String
    let kind: GitReferenceTreeRowKind
    let title: String
    let subtitle: String?
    let detail: String?
    let systemImage: String
    let depth: Int
    let referenceFullName: String?
    let reflogSelector: String?
    let targetHash: String?
    let isExpandable: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let isCurrent: Bool
    let remoteName: String?
}

enum GitReferenceTreeBuilder {
    static let localSectionID = "section:local"
    static let remoteSectionID = "section:remote"
    static let reflogSectionID = "section:reflogs"
    static let tagSectionID = "section:tags"

    static let defaultExpandedIDs: Set<String> = [
        localSectionID,
        remoteSectionID,
        reflogSectionID,
        tagSectionID,
    ]

    static func rows(
        snapshot: GitReferenceSnapshot,
        selection: GitReferenceSelection,
        expandedIDs: Set<String>
    ) -> [GitReferenceTreeRow] {
        var rows: [GitReferenceTreeRow] = []
        appendLocalRows(snapshot: snapshot, selection: selection, expandedIDs: expandedIDs, rows: &rows)
        appendRemoteRows(snapshot: snapshot, selection: selection, expandedIDs: expandedIDs, rows: &rows)
        appendReflogRows(snapshot: snapshot, selection: selection, expandedIDs: expandedIDs, rows: &rows)
        appendTagRows(snapshot: snapshot, selection: selection, expandedIDs: expandedIDs, rows: &rows)
        return rows
    }

    private static func appendLocalRows(
        snapshot: GitReferenceSnapshot,
        selection: GitReferenceSelection,
        expandedIDs: Set<String>,
        rows: inout [GitReferenceTreeRow]
    ) {
        rows.append(sectionRow(
            id: localSectionID,
            title: "Local",
            count: snapshot.localBranches.count,
            systemImage: AppIcon.Workspace.git,
            expandedIDs: expandedIDs
        ))
        guard expandedIDs.contains(localSectionID) else { return }
        let branches = snapshot.localBranches.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            return lhs.shortName.localizedStandardCompare(rhs.shortName) == .orderedAscending
        }
        for branch in branches {
            rows.append(referenceRow(reference: branch, depth: 1, selection: selection))
        }
        if snapshot.isDetachedHead, let headHash = snapshot.headHash {
            rows.append(GitReferenceTreeRow(
                id: "detached-head:\(headHash)",
                kind: .reference,
                title: "Detached HEAD",
                subtitle: String(headHash.prefix(7)),
                detail: nil,
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                depth: 1,
                referenceFullName: nil,
                reflogSelector: nil,
                targetHash: headHash,
                isExpandable: false,
                isExpanded: false,
                isSelected: false,
                isCurrent: true,
                remoteName: nil
            ))
        }
    }

    private static func appendRemoteRows(
        snapshot: GitReferenceSnapshot,
        selection: GitReferenceSelection,
        expandedIDs: Set<String>,
        rows: inout [GitReferenceTreeRow]
    ) {
        rows.append(sectionRow(
            id: remoteSectionID,
            title: "Remote",
            count: snapshot.remoteGroups.values.reduce(0) { $0 + $1.count },
            systemImage: "cloud",
            expandedIDs: expandedIDs
        ))
        guard expandedIDs.contains(remoteSectionID) else { return }
        for remoteName in snapshot.remoteNames {
            let groupID = remoteGroupID(remoteName)
            let refs = snapshot.remoteGroups[remoteName] ?? []
            rows.append(GitReferenceTreeRow(
                id: groupID,
                kind: .remoteGroup,
                title: remoteName,
                subtitle: "\(refs.count)",
                detail: nil,
                systemImage: "cloud",
                depth: 1,
                referenceFullName: nil,
                reflogSelector: nil,
                targetHash: nil,
                isExpandable: !refs.isEmpty,
                isExpanded: expandedIDs.contains(groupID),
                isSelected: false,
                isCurrent: false,
                remoteName: remoteName
            ))
            guard expandedIDs.contains(groupID) else { continue }
            for reference in refs.sorted(by: referenceSort) {
                rows.append(referenceRow(reference: reference, depth: 2, selection: selection))
            }
        }
    }

    private static func appendReflogRows(
        snapshot: GitReferenceSnapshot,
        selection: GitReferenceSelection,
        expandedIDs: Set<String>,
        rows: inout [GitReferenceTreeRow]
    ) {
        rows.append(sectionRow(
            id: reflogSectionID,
            title: "Reflogs",
            count: snapshot.reflogs.count,
            systemImage: AppIcon.Status.history,
            expandedIDs: expandedIDs
        ))
        guard expandedIDs.contains(reflogSectionID) else { return }
        for entry in snapshot.reflogs {
            rows.append(GitReferenceTreeRow(
                id: "reflog:\(entry.id)",
                kind: .reflog,
                title: entry.shortSelector,
                subtitle: entry.message.nilIfBlank,
                detail: entry.shortHash,
                systemImage: AppIcon.Status.history,
                depth: 1,
                referenceFullName: nil,
                reflogSelector: entry.id,
                targetHash: entry.targetHash,
                isExpandable: false,
                isExpanded: false,
                isSelected: selection == .reflog(entry.id),
                isCurrent: false,
                remoteName: nil
            ))
        }
        if snapshot.hasMoreReflogs {
            rows.append(GitReferenceTreeRow(
                id: "reflog:load-more",
                kind: .reflog,
                title: "Load more",
                subtitle: "\(snapshot.reflogLimit) shown",
                detail: nil,
                systemImage: AppIcon.Action.addCircle,
                depth: 1,
                referenceFullName: nil,
                reflogSelector: nil,
                targetHash: nil,
                isExpandable: false,
                isExpanded: false,
                isSelected: false,
                isCurrent: false,
                remoteName: nil
            ))
        }
    }

    private static func appendTagRows(
        snapshot: GitReferenceSnapshot,
        selection: GitReferenceSelection,
        expandedIDs: Set<String>,
        rows: inout [GitReferenceTreeRow]
    ) {
        rows.append(sectionRow(
            id: tagSectionID,
            title: "Tags",
            count: snapshot.tags.count,
            systemImage: AppIcon.Resource.tag,
            expandedIDs: expandedIDs
        ))
        guard expandedIDs.contains(tagSectionID) else { return }
        var emittedFolders = Set<String>()
        for tag in snapshot.tags.sorted(by: referenceSort) {
            let components = tag.shortName.split(separator: "/").map(String.init)
            guard components.count > 1 else {
                rows.append(referenceRow(reference: tag, depth: 1, selection: selection))
                continue
            }

            var visibleParent = true
            var prefix: [String] = []
            for (index, component) in components.dropLast().enumerated() {
                prefix.append(component)
                let folderID = tagFolderID(prefix.joined(separator: "/"))
                if visibleParent, emittedFolders.insert(folderID).inserted {
                    rows.append(GitReferenceTreeRow(
                        id: folderID,
                        kind: .folder,
                        title: component,
                        subtitle: nil,
                        detail: nil,
                        systemImage: AppIcon.Resource.folder,
                        depth: index + 1,
                        referenceFullName: nil,
                        reflogSelector: nil,
                        targetHash: nil,
                        isExpandable: true,
                        isExpanded: expandedIDs.contains(folderID),
                        isSelected: false,
                        isCurrent: false,
                        remoteName: nil
                    ))
                }
                visibleParent = visibleParent && expandedIDs.contains(folderID)
            }
            if visibleParent {
                rows.append(referenceRow(
                    reference: tag,
                    titleOverride: components.last,
                    depth: components.count,
                    selection: selection
                ))
            }
        }
    }

    private static func sectionRow(
        id: String,
        title: String,
        count: Int,
        systemImage: String,
        expandedIDs: Set<String>
    ) -> GitReferenceTreeRow {
        GitReferenceTreeRow(
            id: id,
            kind: .section,
            title: title,
            subtitle: count > 0 ? "\(count)" : nil,
            detail: nil,
            systemImage: systemImage,
            depth: 0,
            referenceFullName: nil,
            reflogSelector: nil,
            targetHash: nil,
            isExpandable: true,
            isExpanded: expandedIDs.contains(id),
            isSelected: false,
            isCurrent: false,
            remoteName: nil
        )
    }

    private static func referenceRow(
        reference: GitReference,
        titleOverride: String? = nil,
        depth: Int,
        selection: GitReferenceSelection
    ) -> GitReferenceTreeRow {
        GitReferenceTreeRow(
            id: "ref:\(reference.fullName)",
            kind: .reference,
            title: titleOverride ?? displayName(for: reference),
            subtitle: subtitle(for: reference),
            detail: reference.shortHash,
            systemImage: systemImage(for: reference),
            depth: depth,
            referenceFullName: reference.fullName,
            reflogSelector: nil,
            targetHash: reference.targetHash,
            isExpandable: false,
            isExpanded: false,
            isSelected: selection == .reference(reference.fullName),
            isCurrent: reference.isCurrent,
            remoteName: reference.remoteName
        )
    }

    static func remoteGroupID(_ name: String) -> String {
        "remote:\(name)"
    }

    static func tagFolderID(_ path: String) -> String {
        "tag-folder:\(path)"
    }

    private static func displayName(for reference: GitReference) -> String {
        switch reference.kind {
        case .localBranch, .tag:
            return reference.shortName
        case .remoteBranch:
            return reference.branchName ?? reference.shortName
        }
    }

    private static func subtitle(for reference: GitReference) -> String? {
        if reference.isCurrent {
            return "HEAD"
        }
        if let aheadBehind = reference.aheadBehind, !aheadBehind.isZero {
            var parts: [String] = []
            if aheadBehind.ahead > 0 { parts.append("\(aheadBehind.ahead) ahead") }
            if aheadBehind.behind > 0 { parts.append("\(aheadBehind.behind) behind") }
            return parts.joined(separator: ", ")
        }
        return reference.upstreamShortName
    }

    private static func systemImage(for reference: GitReference) -> String {
        switch reference.kind {
        case .localBranch:
            return AppIcon.Workspace.git
        case .remoteBranch:
            return "cloud"
        case .tag:
            return AppIcon.Resource.tag
        }
    }

    private static func referenceSort(_ lhs: GitReference, _ rhs: GitReference) -> Bool {
        if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
        return lhs.shortName.localizedStandardCompare(rhs.shortName) == .orderedAscending
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
