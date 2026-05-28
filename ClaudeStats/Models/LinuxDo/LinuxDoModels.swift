import Foundation

enum LinuxDoTopPeriod: String, CaseIterable, Codable, Sendable, Identifiable {
    case daily
    case weekly
    case monthly
    case quarterly
    case yearly
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .yearly: "Yearly"
        case .all: "All Time"
        }
    }
}

enum LinuxDoFeed: Hashable, Codable, Sendable, Identifiable {
    case latest
    case hot
    case top(LinuxDoTopPeriod)
    case category(id: Int, name: String, slug: String)
    case search(String)

    var id: String { key }

    var key: String {
        switch self {
        case .latest: "latest"
        case .hot: "hot"
        case .top(let period): "top:\(period.rawValue)"
        case .category(let id, _, _): "category:\(id)"
        case .search(let query): "search:\(query.lowercased())"
        }
    }

    var title: String {
        switch self {
        case .latest: "Latest"
        case .hot: "Hot"
        case .top(let period): "Top \(period.displayName)"
        case .category(_, let name, _): name
        case .search(let query): "Search: \(query)"
        }
    }

    var cacheTTL: TimeInterval {
        switch self {
        case .latest, .hot: 5 * 60
        case .top: 30 * 60
        case .category: 10 * 60
        case .search: 15 * 60
        }
    }

    var storedValue: String {
        switch self {
        case .latest: "latest"
        case .hot: "hot"
        case .top(let period): "top|\(period.rawValue)"
        case .category(let id, let name, let slug): "category|\(id)|\(name)|\(slug)"
        case .search(let query): "search|\(query)"
        }
    }

    static func stored(_ raw: String) -> LinuxDoFeed? {
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let head = parts.first else { return nil }
        switch head {
        case "latest": return .latest
        case "hot": return .hot
        case "top":
            guard parts.count >= 2, let period = LinuxDoTopPeriod(rawValue: parts[1]) else { return nil }
            return .top(period)
        case "category":
            guard parts.count >= 4, let id = Int(parts[1]) else { return nil }
            return .category(id: id, name: parts[2], slug: parts[3])
        case "search":
            guard parts.count >= 2, !parts[1].isEmpty else { return nil }
            return .search(parts[1])
        default:
            return nil
        }
    }
}

struct LinuxDoCategory: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let slug: String
    let colorHex: String?
    let textColorHex: String?
    let iconName: String?
    let topicCount: Int
}

struct LinuxDoUser: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let username: String
    let name: String?
    let avatarURL: URL?
}

struct LinuxDoUserProfile: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let username: String
    let name: String?
    let avatarURL: URL?
    let title: String?
    let bioExcerpt: String?
    let website: String?
    let location: String?
    let createdAt: Date?
    let lastSeenAt: Date?
    let trustLevel: Int?
    let isAdmin: Bool
    let isModerator: Bool
    let primaryGroupName: String?
    let flairName: String?
    let flairURL: URL?
    let stats: LinuxDoUserProfileStats
    let badges: [LinuxDoUserBadge]
    let groups: [LinuxDoUserGroup]

    init(
        id: Int,
        username: String,
        name: String? = nil,
        avatarURL: URL? = nil,
        title: String? = nil,
        bioExcerpt: String? = nil,
        website: String? = nil,
        location: String? = nil,
        createdAt: Date? = nil,
        lastSeenAt: Date? = nil,
        trustLevel: Int? = nil,
        isAdmin: Bool = false,
        isModerator: Bool = false,
        primaryGroupName: String? = nil,
        flairName: String? = nil,
        flairURL: URL? = nil,
        stats: LinuxDoUserProfileStats = LinuxDoUserProfileStats(),
        badges: [LinuxDoUserBadge] = [],
        groups: [LinuxDoUserGroup] = []
    ) {
        self.id = id
        self.username = username
        self.name = name
        self.avatarURL = avatarURL
        self.title = title
        self.bioExcerpt = bioExcerpt
        self.website = website
        self.location = location
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.trustLevel = trustLevel
        self.isAdmin = isAdmin
        self.isModerator = isModerator
        self.primaryGroupName = primaryGroupName
        self.flairName = flairName
        self.flairURL = flairURL
        self.stats = stats
        self.badges = badges
        self.groups = groups
    }

    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return username
    }

    var plainBioExcerpt: String {
        (bioExcerpt ?? "").htmlStrippedAndDecoded
    }

    var profileURL: URL? {
        guard let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://linux.do/u/\(encodedUsername)")
    }
}

struct LinuxDoUserProfileStats: Codable, Hashable, Sendable {
    let topicCount: Int?
    let postCount: Int?
    let likesReceived: Int?
    let likesGiven: Int?
    let solutionsCount: Int?
    let profileViewCount: Int?
    let readTimeSeconds: Int?
    let recentReadTimeSeconds: Int?
    let topicsEntered: Int?
    let postsReadCount: Int?

    init(
        topicCount: Int? = nil,
        postCount: Int? = nil,
        likesReceived: Int? = nil,
        likesGiven: Int? = nil,
        solutionsCount: Int? = nil,
        profileViewCount: Int? = nil,
        readTimeSeconds: Int? = nil,
        recentReadTimeSeconds: Int? = nil,
        topicsEntered: Int? = nil,
        postsReadCount: Int? = nil
    ) {
        self.topicCount = topicCount
        self.postCount = postCount
        self.likesReceived = likesReceived
        self.likesGiven = likesGiven
        self.solutionsCount = solutionsCount
        self.profileViewCount = profileViewCount
        self.readTimeSeconds = readTimeSeconds
        self.recentReadTimeSeconds = recentReadTimeSeconds
        self.topicsEntered = topicsEntered
        self.postsReadCount = postsReadCount
    }
}

struct LinuxDoUserBadge: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let slug: String?
    let description: String?
    let iconName: String?
    let imageURL: URL?
    let grantedAt: Date?

    init(
        id: Int,
        name: String,
        slug: String? = nil,
        description: String? = nil,
        iconName: String? = nil,
        imageURL: URL? = nil,
        grantedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.description = description
        self.iconName = iconName
        self.imageURL = imageURL
        self.grantedAt = grantedAt
    }
}

struct LinuxDoUserGroup: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let fullName: String?
    let title: String?
    let flairURL: URL?
    let flairColorHex: String?
    let flairBackgroundColorHex: String?

    init(
        id: String? = nil,
        name: String,
        fullName: String? = nil,
        title: String? = nil,
        flairURL: URL? = nil,
        flairColorHex: String? = nil,
        flairBackgroundColorHex: String? = nil
    ) {
        self.id = id ?? name
        self.name = name
        self.fullName = fullName
        self.title = title
        self.flairURL = flairURL
        self.flairColorHex = flairColorHex
        self.flairBackgroundColorHex = flairBackgroundColorHex
    }
}

struct LinuxDoTopicSummary: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
    let fancyTitle: String?
    let slug: String?
    let categoryID: Int?
    let tags: [String]
    let excerpt: String?
    let postsCount: Int
    let replyCount: Int
    let views: Int
    let likeCount: Int
    let createdAt: Date?
    let bumpedAt: Date?
    let lastPostedAt: Date?
    let imageURL: URL?

    var displayTitle: String {
        let candidate = (fancyTitle?.isEmpty == false ? fancyTitle : title) ?? title
        return candidate.htmlStrippedAndDecoded
    }

    var displayExcerpt: String {
        (excerpt ?? "").htmlStrippedAndDecoded
    }

    var topicURL: URL? {
        guard let slug else {
            return URL(string: "https://linux.do/t/topic/\(id)")
        }
        return URL(string: "https://linux.do/t/\(slug)/\(id)")
    }
}

struct LinuxDoTopicDetail: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
    let fancyTitle: String?
    let slug: String?
    let categoryID: Int?
    let tags: [String]
    let postsCount: Int
    let canReply: Bool?
    var stream: [Int]
    var posts: [LinuxDoPost]
    let fetchedAt: Date

    init(
        id: Int,
        title: String,
        fancyTitle: String?,
        slug: String?,
        categoryID: Int?,
        tags: [String],
        postsCount: Int,
        canReply: Bool? = nil,
        stream: [Int],
        posts: [LinuxDoPost],
        fetchedAt: Date
    ) {
        self.id = id
        self.title = title
        self.fancyTitle = fancyTitle
        self.slug = slug
        self.categoryID = categoryID
        self.tags = tags
        self.postsCount = postsCount
        self.canReply = canReply
        self.stream = stream
        self.posts = posts
        self.fetchedAt = fetchedAt
    }

    var displayTitle: String {
        let candidate = (fancyTitle?.isEmpty == false ? fancyTitle : title) ?? title
        return candidate.htmlStrippedAndDecoded
    }

    var topicURL: URL? {
        guard let slug else {
            return URL(string: "https://linux.do/t/topic/\(id)")
        }
        return URL(string: "https://linux.do/t/\(slug)/\(id)")
    }
}

struct LinuxDoReadingPosition: Codable, Hashable, Sendable {
    let topicID: Int
    let postID: Int
    let postNumber: Int
    let updatedAt: Date
}

struct LinuxDoPost: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let topicID: Int?
    let topicSlug: String?
    let postNumber: Int
    let replyToPostNumber: Int?
    let username: String
    let name: String?
    let displayUsername: String?
    let avatarURL: URL?
    let cookedHTML: String
    let raw: String?
    let createdAt: Date?
    let updatedAt: Date?
    let likeCount: Int
    let replyCount: Int
    let reads: Int
    let score: Double?
    let actionsSummary: [LinuxDoPostActionSummary]
    let reactions: [LinuxDoReaction]?
    let currentUserReaction: String?
    let canAct: Bool?
    let canReply: Bool?
    let yours: Bool?
    let postURL: URL?

    init(
        id: Int,
        topicID: Int?,
        topicSlug: String? = nil,
        postNumber: Int,
        replyToPostNumber: Int?,
        username: String,
        name: String?,
        displayUsername: String? = nil,
        avatarURL: URL?,
        cookedHTML: String,
        raw: String? = nil,
        createdAt: Date?,
        updatedAt: Date?,
        likeCount: Int,
        replyCount: Int,
        reads: Int,
        score: Double?,
        actionsSummary: [LinuxDoPostActionSummary],
        reactions: [LinuxDoReaction] = [],
        currentUserReaction: String? = nil,
        canAct: Bool? = nil,
        canReply: Bool? = nil,
        yours: Bool? = nil,
        postURL: URL? = nil
    ) {
        self.id = id
        self.topicID = topicID
        self.topicSlug = topicSlug
        self.postNumber = postNumber
        self.replyToPostNumber = replyToPostNumber
        self.username = username
        self.name = name
        self.displayUsername = displayUsername
        self.avatarURL = avatarURL
        self.cookedHTML = cookedHTML
        self.raw = raw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.likeCount = likeCount
        self.replyCount = replyCount
        self.reads = reads
        self.score = score
        self.actionsSummary = actionsSummary
        self.reactions = reactions
        self.currentUserReaction = currentUserReaction
        self.canAct = canAct
        self.canReply = canReply
        self.yours = yours
        self.postURL = postURL
    }

    var textPreview: String {
        cookedHTML.htmlStrippedAndDecoded
    }

    var displayAuthorName: String {
        if let displayUsername, !displayUsername.isEmpty {
            return displayUsername
        }
        if let name, !name.isEmpty {
            return name
        }
        return "@\(username)"
    }

    var likeActionSummary: LinuxDoPostActionSummary? {
        actionsSummary.first { $0.id == 2 }
    }

    var effectiveLikeCount: Int {
        max(likeCount, likeActionSummary?.count ?? 0)
    }

    var isLikedByCurrentUser: Bool {
        likeActionSummary?.acted == true || currentUserReaction == LinuxDoReactionCatalog.likeReactionID
    }

    var canToggleLike: Bool {
        likeActionSummary?.canAct ?? canAct ?? true
    }

    var visibleReactions: [LinuxDoReaction] {
        reactions ?? []
    }

    func replacingForumState(
        likeCount: Int? = nil,
        replyCount: Int? = nil,
        actionsSummary: [LinuxDoPostActionSummary]? = nil,
        reactions: [LinuxDoReaction]? = nil,
        currentUserReaction: String? = nil,
        clearsCurrentUserReaction: Bool = false
    ) -> LinuxDoPost {
        LinuxDoPost(
            id: id,
            topicID: topicID,
            topicSlug: topicSlug,
            postNumber: postNumber,
            replyToPostNumber: replyToPostNumber,
            username: username,
            name: name,
            displayUsername: displayUsername,
            avatarURL: avatarURL,
            cookedHTML: cookedHTML,
            raw: raw,
            createdAt: createdAt,
            updatedAt: updatedAt,
            likeCount: likeCount ?? self.likeCount,
            replyCount: replyCount ?? self.replyCount,
            reads: reads,
            score: score,
            actionsSummary: actionsSummary ?? self.actionsSummary,
            reactions: reactions ?? visibleReactions,
            currentUserReaction: clearsCurrentUserReaction ? nil : (currentUserReaction ?? self.currentUserReaction),
            canAct: canAct,
            canReply: canReply,
            yours: yours,
            postURL: postURL
        )
    }
}

struct LinuxDoPostActionSummary: Codable, Hashable, Sendable {
    let id: Int
    let count: Int
    let acted: Bool
    let canAct: Bool?

    init(id: Int, count: Int, acted: Bool, canAct: Bool? = nil) {
        self.id = id
        self.count = count
        self.acted = acted
        self.canAct = canAct
    }
}

struct LinuxDoReaction: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let count: Int
    let users: [LinuxDoReactionUserSummary]

    var displayText: String {
        LinuxDoReactionCatalog.displayText(for: id)
    }
}

struct LinuxDoReactionUserSummary: Codable, Hashable, Identifiable, Sendable {
    var id: String { username }

    let username: String
    let name: String?
    let avatarURL: URL?
    let canUndo: Bool
    let createdAt: Date?
}

struct LinuxDoEmoji: Codable, Hashable, Identifiable, Sendable {
    var id: String { name }

    let name: String
    let imageURL: URL
}

enum LinuxDoReactionCatalog {
    static let likeReactionID = "heart"

    static let defaultReactionIDs = [
        "heart",
        "+1",
        "clap",
        "hugs",
        "laughing",
        "open_mouth",
        "eyes",
    ]

    static func displayText(for id: String) -> String {
        switch id {
        case "heart": "❤️"
        case "+1": "👍"
        case "-1": "👎"
        case "clap": "👏"
        case "hugs": "🤗"
        case "laughing", "laugh": "😆"
        case "open_mouth": "😮"
        case "eyes": "👀"
        case "tada": "🎉"
        case "rocket": "🚀"
        default:
            if id.count <= 3 {
                id
            } else {
                ":\(id):"
            }
        }
    }
}

struct LinuxDoTopicList: Codable, Sendable {
    var topics: [LinuxDoTopicSummary]
    var page: Int
    var nextPage: Int?
    var fetchedAt: Date
}

struct LinuxDoNotification: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let notificationType: Int
    let read: Bool
    let createdAt: Date?
    let topicID: Int?
    let postNumber: Int?
    let slug: String?
    let title: String?
    let excerpt: String?

    var displayTitle: String {
        (title?.isEmpty == false ? title : "Linux.do notification") ?? "Linux.do notification"
    }

    var displayBody: String {
        (excerpt ?? "").htmlStrippedAndDecoded
    }

    var topicURL: URL? {
        guard let topicID else { return nil }
        let slug = slug?.isEmpty == false ? slug! : "topic"
        if let postNumber, postNumber > 1 {
            return URL(string: "https://linux.do/t/\(slug)/\(topicID)/\(postNumber)")
        }
        return URL(string: "https://linux.do/t/\(slug)/\(topicID)")
    }
}

struct LinuxDoTopicRoute: Hashable, Sendable {
    let id: Int
    let slug: String?
    let postNumber: Int?

    init(id: Int, slug: String?, postNumber: Int?) {
        self.id = id
        self.slug = slug?.isEmpty == false ? slug : nil
        self.postNumber = postNumber
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(),
              host == "linux.do" || host.hasSuffix(".linux.do") else {
            return nil
        }

        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.first == "t" else { return nil }

        if parts.count >= 2, let topicID = Int(parts[1]) {
            self.init(id: topicID, slug: nil, postNumber: parts.indices.contains(2) ? Int(parts[2]) : nil)
            return
        }

        if parts.count >= 3, let topicID = Int(parts[2]) {
            self.init(id: topicID, slug: parts[1], postNumber: parts.indices.contains(3) ? Int(parts[3]) : nil)
            return
        }

        return nil
    }
}

struct LinuxDoCurrentUser: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let username: String
    let name: String?
    let avatarURL: URL?
}

struct LinuxDoStoredCookie: Codable, Hashable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresAt: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool

    init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        expiresAt: Date? = nil,
        isSecure: Bool = true,
        isHTTPOnly: Bool = false
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresAt = expiresAt
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }

    init(cookie: HTTPCookie) {
        self.init(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            expiresAt: cookie.expiresDate,
            isSecure: cookie.isSecure,
            isHTTPOnly: cookie.isHTTPOnly
        )
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    var isLinuxDoCookie: Bool {
        let normalized = domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return normalized == "linux.do" || normalized.hasSuffix(".linux.do")
    }
}

struct LinuxDoWebSession: Codable, Hashable, Sendable {
    var cookies: [LinuxDoStoredCookie]
    var csrfToken: String?
    var username: String?
    var avatarURL: URL?
    var savedAt: Date

    init(
        cookies: [LinuxDoStoredCookie],
        csrfToken: String? = nil,
        username: String? = nil,
        avatarURL: URL? = nil,
        savedAt: Date = .now
    ) {
        self.cookies = cookies
        self.csrfToken = csrfToken
        self.username = username
        self.avatarURL = avatarURL
        self.savedAt = savedAt
    }

    var isAuthenticated: Bool {
        containsCookie(named: "_t")
    }

    func containsCookie(named name: String) -> Bool {
        cookies.contains { $0.name == name && !$0.isExpired && $0.isLinuxDoCookie && !$0.value.isEmpty }
    }

    func cookieHeader(now: Date = .now) -> String? {
        let liveCookies = cookies
            .filter { cookie in
                cookie.isLinuxDoCookie && !cookie.value.isEmpty && (cookie.expiresAt.map { $0 > now } ?? true)
            }
            .sorted { lhs, rhs in
                Self.cookieSortRank(lhs.name) < Self.cookieSortRank(rhs.name)
            }
        guard !liveCookies.isEmpty else { return nil }
        return liveCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func with(csrfToken: String?, username: String?, avatarURL: URL? = nil) -> LinuxDoWebSession {
        LinuxDoWebSession(
            cookies: cookies,
            csrfToken: csrfToken ?? self.csrfToken,
            username: username ?? self.username,
            avatarURL: avatarURL ?? self.avatarURL,
            savedAt: .now
        )
    }

    private static func cookieSortRank(_ name: String) -> Int {
        switch name {
        case "_t": 0
        case "_forum_session": 1
        case "cf_clearance": 2
        default: 10
        }
    }
}

enum LinuxDoAuthCredential: Equatable, Sendable {
    case webSession(LinuxDoWebSession)
}

struct LinuxDoContentBlock: Hashable, Sendable, Identifiable {
    let id: String
    let kind: LinuxDoContentBlockKind
}

enum LinuxDoContentBlockKind: Hashable, Sendable {
    case paragraph([LinuxDoInlineNode])
    case heading(level: Int, content: [LinuxDoInlineNode])
    case quote(attribution: LinuxDoQuoteAttribution?, blocks: [LinuxDoContentBlock])
    case callout(LinuxDoCallout)
    case event(LinuxDoPostEvent)
    case codeBlock(language: String?, code: String)
    case list(ordered: Bool, items: [LinuxDoListItem])
    case image(url: URL, alt: String?, width: Int?, height: Int?, linkURL: URL?)
    case onebox(LinuxDoOnebox)
    case table(headers: [LinuxDoTableCell], rows: [LinuxDoTableRow])
    case details(summary: [LinuxDoInlineNode], blocks: [LinuxDoContentBlock])
    case spoiler([LinuxDoContentBlock])
    case divider
    case rawHTML(String)
}

enum LinuxDoInlineNode: Hashable, Sendable {
    case text(String)
    case strong([LinuxDoInlineNode])
    case emphasis([LinuxDoInlineNode])
    case strikethrough([LinuxDoInlineNode])
    case code(String)
    case highlight([LinuxDoInlineNode])
    case keyboard([LinuxDoInlineNode])
    case `subscript`([LinuxDoInlineNode])
    case superscript([LinuxDoInlineNode])
    case link(url: URL, children: [LinuxDoInlineNode])
    case image(url: URL, alt: String?, width: Int?, height: Int?, isEmoji: Bool)
    case mention(username: String, url: URL?)
    case hashtag(text: String, url: URL?)
    case spoiler([LinuxDoInlineNode])
    case lineBreak
}

enum LinuxDoTaskState: Hashable, Sendable {
    case checked
    case unchecked
}

struct LinuxDoListItem: Hashable, Sendable, Identifiable {
    let id: String
    let taskState: LinuxDoTaskState?
    let blocks: [LinuxDoContentBlock]

    init(id: String = UUID().uuidString, taskState: LinuxDoTaskState? = nil, blocks: [LinuxDoContentBlock]) {
        self.id = id
        self.taskState = taskState
        self.blocks = blocks
    }
}

struct LinuxDoTableCell: Hashable, Sendable, Identifiable {
    let id: String
    let blocks: [LinuxDoContentBlock]
}

struct LinuxDoTableRow: Hashable, Sendable, Identifiable {
    let id: String
    let cells: [LinuxDoTableCell]
}

struct LinuxDoCallout: Hashable, Sendable {
    let style: LinuxDoCalloutStyle
    let title: String?
    let blocks: [LinuxDoContentBlock]
}

enum LinuxDoCalloutStyle: String, Hashable, Sendable {
    case note
    case tip
    case important
    case warning
    case danger
    case generic
}

struct LinuxDoPostEvent: Hashable, Sendable {
    let name: String?
    let startsAt: String?
    let endsAt: String?
    let timezone: String?
    let status: String?
}

struct LinuxDoQuoteAttribution: Hashable, Sendable {
    let username: String?
    let displayName: String?
    let avatarURL: URL?
    let topicTitle: String?
    let topicURL: URL?
    let postNumber: Int?
    let postURL: URL?
    let source: LinuxDoQuoteSource

    init(
        username: String?,
        displayName: String? = nil,
        avatarURL: URL?,
        topicTitle: String?,
        topicURL: URL?,
        postNumber: Int? = nil,
        postURL: URL? = nil,
        source: LinuxDoQuoteSource = .blockquote
    ) {
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.topicTitle = topicTitle
        self.topicURL = topicURL
        self.postNumber = postNumber
        self.postURL = postURL
        self.source = source
    }
}

enum LinuxDoQuoteSource: Hashable, Sendable {
    case blockquote
    case discourseAside
}

struct LinuxDoOnebox: Hashable, Sendable {
    let url: URL?
    let title: String?
    let description: String?
    let imageURL: URL?
    let faviconURL: URL?
}

extension String {
    var htmlStrippedAndDecoded: String {
        let withoutTags = replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
