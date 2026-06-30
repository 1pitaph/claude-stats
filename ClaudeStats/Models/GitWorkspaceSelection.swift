import Foundation

enum GitWorkspaceSelection: Equatable, Hashable, Sendable {
    private static let allRawValue = "all"
    private static let repoPrefix = "repo:"

    case all
    case repo(String)

    init(rawValue: String) {
        if rawValue.isEmpty || rawValue == Self.allRawValue {
            self = .all
            return
        }

        if rawValue.hasPrefix(Self.repoPrefix) {
            let repoID = String(rawValue.dropFirst(Self.repoPrefix.count))
            self = repoID.isEmpty ? .all : .repo(repoID)
            return
        }

        // Legacy SceneStorage values were stored as the raw GitRepo.id.
        self = .repo(rawValue)
    }

    var rawValue: String {
        switch self {
        case .all:
            Self.allRawValue
        case .repo(let id):
            Self.repoPrefix + id
        }
    }

    var repoID: String? {
        switch self {
        case .all: nil
        case .repo(let id): id
        }
    }
}
