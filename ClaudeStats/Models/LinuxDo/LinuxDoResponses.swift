import Foundation

enum LinuxDoResponseMapper {
    static func topicList(from response: TopicListResponse, page: Int, now: Date) -> LinuxDoTopicList {
        LinuxDoTopicList(
            topics: response.topicList.topics.map(\.model),
            page: page,
            nextPage: response.topicList.moreTopicsURL == nil ? nil : page + 1,
            fetchedAt: now
        )
    }

    static func topicList(from response: SearchResponse, page: Int, now: Date) -> LinuxDoTopicList {
        LinuxDoTopicList(
            topics: response.topics.map(\.model),
            page: page,
            nextPage: response.groupedSearchResult?.morePosts == true ? page + 1 : nil,
            fetchedAt: now
        )
    }

    static func topicDetail(from response: TopicDetailResponse, now: Date) -> LinuxDoTopicDetail {
        LinuxDoTopicDetail(
            id: response.id,
            title: response.title,
            fancyTitle: response.fancyTitle,
            slug: response.slug,
            categoryID: response.categoryID,
            tags: response.tags?.values ?? [],
            postsCount: response.postsCount ?? response.postStream.posts.count,
            canReply: response.details?.canCreatePost,
            stream: response.postStream.stream ?? response.postStream.posts.map(\.id),
            posts: response.postStream.posts.map(\.model),
            fetchedAt: now
        )
    }

    static func posts(from response: TopicPostsResponse) -> [LinuxDoPost] {
        response.postStream.posts.map(\.model)
    }

    static func reactionUsers(from response: ReactionUsersResponse) -> [LinuxDoReaction] {
        response.reactionUsers.map(\.model)
    }

    static func emojiURLs(from response: EmojiCatalogResponse) -> [String: URL] {
        Dictionary(uniqueKeysWithValues: response.emojis.map { ($0.name, $0.imageURL) })
    }

    static func userProfile(from response: UserProfileResponse) -> LinuxDoUserProfile {
        response.profile
    }
}

struct TopicListResponse: Decodable, Sendable {
    let topicList: TopicList

    enum CodingKeys: String, CodingKey {
        case topicList = "topic_list"
    }

    struct TopicList: Decodable, Sendable {
        let topics: [TopicResponse]
        let moreTopicsURL: String?

        enum CodingKeys: String, CodingKey {
            case topics
            case moreTopicsURL = "more_topics_url"
        }
    }
}

struct CategoriesResponse: Decodable, Sendable {
    let categoryList: CategoryList

    enum CodingKeys: String, CodingKey {
        case categoryList = "category_list"
    }

    var categories: [LinuxDoCategory] {
        categoryList.categories.map(\.model)
    }

    struct CategoryList: Decodable, Sendable {
        let categories: [CategoryResponse]
    }
}

struct SearchResponse: Decodable, Sendable {
    let topics: [TopicResponse]
    let groupedSearchResult: GroupedSearchResult?

    enum CodingKeys: String, CodingKey {
        case topics
        case groupedSearchResult = "grouped_search_result"
    }

    struct GroupedSearchResult: Decodable, Sendable {
        let morePosts: Bool?

        enum CodingKeys: String, CodingKey {
            case morePosts = "more_posts"
        }
    }
}

struct TopicDetailResponse: Decodable, Sendable {
    let id: Int
    let title: String
    let fancyTitle: String?
    let slug: String?
    let categoryID: Int?
    let tags: LinuxDoTagList?
    let postsCount: Int?
    let postStream: PostStream
    let details: Details?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case fancyTitle = "fancy_title"
        case slug
        case categoryID = "category_id"
        case tags
        case postsCount = "posts_count"
        case postStream = "post_stream"
        case details
    }

    struct Details: Decodable, Sendable {
        let canCreatePost: Bool?

        enum CodingKeys: String, CodingKey {
            case canCreatePost = "can_create_post"
        }
    }
}

struct TopicPostsResponse: Decodable, Sendable {
    let postStream: TopicDetailResponse.PostStream

    enum CodingKeys: String, CodingKey {
        case postStream = "post_stream"
    }
}

struct ReactionUsersResponse: Decodable, Sendable {
    let reactionUsers: [ReactionResponse]

    enum CodingKeys: String, CodingKey {
        case reactionUsers = "reaction_users"
    }
}

struct EmojiCatalogResponse: Decodable, Sendable {
    let emojis: [LinuxDoEmoji]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var emojis: [LinuxDoEmoji] = []
        var seen = Set<String>()
        for key in container.allKeys {
            let group = try container.decode([EmojiResponse].self, forKey: key)
            for response in group {
                guard let emoji = response.model, seen.insert(emoji.name).inserted else { continue }
                emojis.append(emoji)
            }
        }
        self.emojis = emojis
    }

    private struct EmojiResponse: Decodable, Sendable {
        let name: String
        let url: String?

        var model: LinuxDoEmoji? {
            guard let imageURL = LinuxDoURLResolver.url(from: url) else { return nil }
            return LinuxDoEmoji(name: name, imageURL: imageURL)
        }
    }

    private struct DynamicCodingKey: CodingKey, Hashable, Sendable {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }
}

extension TopicDetailResponse {
    struct PostStream: Decodable, Sendable {
        let posts: [PostResponse]
        let stream: [Int]?
    }
}

struct NotificationsResponse: Decodable, Sendable {
    let notifications: [NotificationResponse]
    let loadMoreNotifications: String?

    enum CodingKeys: String, CodingKey {
        case notifications
        case loadMoreNotifications = "load_more_notifications"
    }

    var usernameFromPagination: String? {
        guard let loadMoreNotifications,
              let components = URLComponents(string: loadMoreNotifications) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "username" })?.value
    }
}

struct CurrentUserResponse: Decodable, Sendable {
    let currentUser: UserResponse

    enum CodingKeys: String, CodingKey {
        case currentUser = "current_user"
    }
}

struct UserProfileResponse: Decodable, Sendable {
    let user: UserProfileUserResponse
    let badges: [BadgeResponse]?
    let userBadges: [UserBadgeResponse]?
    let groups: [GroupResponse]?

    enum CodingKeys: String, CodingKey {
        case user
        case badges
        case userBadges = "user_badges"
        case groups
    }

    var currentUser: LinuxDoCurrentUser {
        user.currentUser
    }

    var profile: LinuxDoUserProfile {
        user.profile(
            badges: mappedBadges,
            groups: mappedGroups
        )
    }

    private var mappedBadges: [LinuxDoUserBadge] {
        var badgeByID: [Int: BadgeResponse] = [:]
        for badge in badges ?? [] {
            badgeByID[badge.id] = badge
        }
        guard let userBadges, !userBadges.isEmpty else {
            return (badges ?? []).map { $0.model(grantedAt: nil) }
        }
        return userBadges.compactMap { userBadge in
            if let badge = userBadge.badge ?? badgeByID[userBadge.badgeID] {
                return badge.model(grantedAt: userBadge.grantedAt)
            }
            guard let name = userBadge.name, !name.isEmpty else { return nil }
            return LinuxDoUserBadge(
                id: userBadge.badgeID,
                name: name,
                slug: userBadge.slug,
                description: userBadge.description,
                iconName: userBadge.icon,
                imageURL: LinuxDoURLResolver.url(from: userBadge.imageURL),
                grantedAt: userBadge.grantedAt
            )
        }
    }

    private var mappedGroups: [LinuxDoUserGroup] {
        var seen = Set<String>()
        var values: [LinuxDoUserGroup] = []
        for group in (user.groups ?? []) + (groups ?? []) {
            guard seen.insert(group.key).inserted else { continue }
            values.append(group.model)
        }
        return values
    }
}

struct CSRFResponse: Decodable, Sendable {
    let csrf: String
}

struct TopicResponse: Decodable, Sendable {
    let id: Int
    let title: String
    let fancyTitle: String?
    let slug: String?
    let categoryID: Int?
    let tags: LinuxDoTagList?
    let excerpt: String?
    let postsCount: Int?
    let replyCount: Int?
    let views: Int?
    let likeCount: Int?
    let createdAt: Date?
    let bumpedAt: Date?
    let lastPostedAt: Date?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case fancyTitle = "fancy_title"
        case slug
        case categoryID = "category_id"
        case tags
        case excerpt
        case postsCount = "posts_count"
        case replyCount = "reply_count"
        case views
        case likeCount = "like_count"
        case createdAt = "created_at"
        case bumpedAt = "bumped_at"
        case lastPostedAt = "last_posted_at"
        case imageURL = "image_url"
    }

    var model: LinuxDoTopicSummary {
        LinuxDoTopicSummary(
            id: id,
            title: title,
            fancyTitle: fancyTitle,
            slug: slug,
            categoryID: categoryID,
            tags: tags?.values ?? [],
            excerpt: excerpt,
            postsCount: postsCount ?? 0,
            replyCount: replyCount ?? 0,
            views: views ?? 0,
            likeCount: likeCount ?? 0,
            createdAt: createdAt,
            bumpedAt: bumpedAt,
            lastPostedAt: lastPostedAt,
            imageURL: LinuxDoURLResolver.url(from: imageURL)
        )
    }
}

struct LinuxDoTagList: Decodable, Hashable, Sendable {
    let values: [String]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [String] = []
        while !container.isAtEnd {
            if let value = try? container.decode(String.self) {
                if !value.isEmpty {
                    values.append(value)
                }
                continue
            }
            if let object = try? container.decode(TagObject.self) {
                if let name = object.name, !name.isEmpty {
                    values.append(name)
                } else if let slug = object.slug, !slug.isEmpty {
                    values.append(slug)
                }
                continue
            }
            _ = try? container.decode(DiscardedTagValue.self)
        }
        self.values = values
    }

    private struct TagObject: Decodable, Hashable, Sendable {
        let name: String?
        let slug: String?
    }

    private struct DiscardedTagValue: Decodable, Hashable, Sendable {
        init(from decoder: Decoder) throws {
            if var array = try? decoder.unkeyedContainer() {
                while !array.isAtEnd {
                    _ = try? array.decode(DiscardedTagValue.self)
                }
                return
            }
            if let object = try? decoder.container(keyedBy: DynamicCodingKey.self) {
                for key in object.allKeys {
                    _ = try? object.decode(DiscardedTagValue.self, forKey: key)
                }
                return
            }
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { return }
            if (try? container.decode(Bool.self)) != nil { return }
            if (try? container.decode(Double.self)) != nil { return }
            _ = try? container.decode(String.self)
        }
    }

    private struct DynamicCodingKey: CodingKey, Hashable, Sendable {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }
}

struct CategoryResponse: Decodable, Sendable {
    let id: Int
    let name: String
    let slug: String
    let color: String?
    let textColor: String?
    let icon: String?
    let topicCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case color
        case textColor = "text_color"
        case icon
        case topicCount = "topic_count"
    }

    var model: LinuxDoCategory {
        LinuxDoCategory(
            id: id,
            name: name,
            slug: slug,
            colorHex: color,
            textColorHex: textColor,
            iconName: icon,
            topicCount: topicCount ?? 0
        )
    }
}

struct UserResponse: Decodable, Sendable {
    let id: Int
    let username: String
    let name: String?
    let avatarTemplate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case name
        case avatarTemplate = "avatar_template"
    }

    var user: LinuxDoUser {
        LinuxDoUser(
            id: id,
            username: username,
            name: name,
            avatarURL: LinuxDoURLResolver.avatarURL(from: avatarTemplate)
        )
    }

    var currentUser: LinuxDoCurrentUser {
        LinuxDoCurrentUser(
            id: id,
            username: username,
            name: name,
            avatarURL: LinuxDoURLResolver.avatarURL(from: avatarTemplate)
        )
    }
}

struct UserProfileUserResponse: Decodable, Sendable {
    let id: Int
    let username: String
    let name: String?
    let avatarTemplate: String?
    let title: String?
    let bioExcerpt: String?
    let website: String?
    let location: String?
    let createdAt: Date?
    let lastSeenAt: Date?
    let trustLevel: Int?
    let admin: Bool?
    let moderator: Bool?
    let primaryGroupName: String?
    let flairName: String?
    let flairURL: String?
    let topicCount: Int?
    let postCount: Int?
    let likesReceived: Int?
    let likesGiven: Int?
    let solutionsCount: Int?
    let acceptedAnswers: Int?
    let solvedCount: Int?
    let profileViewCount: Int?
    let timeRead: Int?
    let recentTimeRead: Int?
    let topicsEntered: Int?
    let postsReadCount: Int?
    let groups: [GroupResponse]?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case name
        case avatarTemplate = "avatar_template"
        case title
        case bioExcerpt = "bio_excerpt"
        case website
        case location
        case createdAt = "created_at"
        case lastSeenAt = "last_seen_at"
        case trustLevel = "trust_level"
        case admin
        case moderator
        case primaryGroupName = "primary_group_name"
        case flairName = "flair_name"
        case flairURL = "flair_url"
        case topicCount = "topic_count"
        case postCount = "post_count"
        case likesReceived = "likes_received"
        case likesGiven = "likes_given"
        case solutionsCount = "solutions_count"
        case acceptedAnswers = "accepted_answers"
        case solvedCount = "solved_count"
        case profileViewCount = "profile_view_count"
        case timeRead = "time_read"
        case recentTimeRead = "recent_time_read"
        case topicsEntered = "topics_entered"
        case postsReadCount = "posts_read_count"
        case groups
    }

    var currentUser: LinuxDoCurrentUser {
        LinuxDoCurrentUser(
            id: id,
            username: username,
            name: name,
            avatarURL: LinuxDoURLResolver.avatarURL(from: avatarTemplate)
        )
    }

    func profile(badges: [LinuxDoUserBadge], groups: [LinuxDoUserGroup]) -> LinuxDoUserProfile {
        LinuxDoUserProfile(
            id: id,
            username: username,
            name: name,
            avatarURL: LinuxDoURLResolver.avatarURL(from: avatarTemplate),
            title: title,
            bioExcerpt: bioExcerpt,
            website: website,
            location: location,
            createdAt: createdAt,
            lastSeenAt: lastSeenAt,
            trustLevel: trustLevel,
            isAdmin: admin ?? false,
            isModerator: moderator ?? false,
            primaryGroupName: primaryGroupName,
            flairName: flairName,
            flairURL: LinuxDoURLResolver.url(from: flairURL),
            stats: LinuxDoUserProfileStats(
                topicCount: topicCount,
                postCount: postCount,
                likesReceived: likesReceived,
                likesGiven: likesGiven,
                solutionsCount: solutionsCount ?? acceptedAnswers ?? solvedCount,
                profileViewCount: profileViewCount,
                readTimeSeconds: timeRead,
                recentReadTimeSeconds: recentTimeRead,
                topicsEntered: topicsEntered,
                postsReadCount: postsReadCount
            ),
            badges: badges,
            groups: groups
        )
    }
}

struct BadgeResponse: Decodable, Sendable {
    let id: Int
    let name: String
    let slug: String?
    let description: String?
    let icon: String?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case description
        case icon
        case imageURL = "image_url"
    }

    func model(grantedAt: Date?) -> LinuxDoUserBadge {
        LinuxDoUserBadge(
            id: id,
            name: name,
            slug: slug,
            description: description,
            iconName: icon,
            imageURL: LinuxDoURLResolver.url(from: imageURL),
            grantedAt: grantedAt
        )
    }
}

struct UserBadgeResponse: Decodable, Sendable {
    let badgeID: Int
    let grantedAt: Date?
    let name: String?
    let slug: String?
    let description: String?
    let icon: String?
    let imageURL: String?
    let badge: BadgeResponse?

    enum CodingKeys: String, CodingKey {
        case badgeID = "badge_id"
        case grantedAt = "granted_at"
        case name
        case slug
        case description
        case icon
        case imageURL = "image_url"
        case badge
    }
}

struct GroupResponse: Decodable, Sendable {
    let id: Int?
    let name: String
    let fullName: String?
    let title: String?
    let flairURL: String?
    let flairColor: String?
    let flairBackgroundColor: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case title
        case flairURL = "flair_url"
        case flairColor = "flair_color"
        case flairBackgroundColor = "flair_bg_color"
    }

    var key: String {
        name.lowercased()
    }

    var model: LinuxDoUserGroup {
        LinuxDoUserGroup(
            id: id.map(String.init) ?? name,
            name: name,
            fullName: fullName,
            title: title,
            flairURL: LinuxDoURLResolver.url(from: flairURL),
            flairColorHex: flairColor,
            flairBackgroundColorHex: flairBackgroundColor
        )
    }
}

struct PostResponse: Decodable, Sendable {
    let id: Int
    let topicID: Int?
    let topicSlug: String?
    let postNumber: Int
    let replyToPostNumber: Int?
    let username: String
    let name: String?
    let displayUsername: String?
    let avatarTemplate: String?
    let cooked: String
    let raw: String?
    let createdAt: Date?
    let updatedAt: Date?
    let likeCount: Int?
    let replyCount: Int?
    let reads: Int?
    let score: Double?
    let actionsSummary: [ActionSummary]?
    let reactions: [ReactionResponse]?
    let currentUserReaction: FlexibleReactionValue?
    let canAct: Bool?
    let canReply: Bool?
    let yours: Bool?
    let postURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case topicID = "topic_id"
        case topicSlug = "topic_slug"
        case postNumber = "post_number"
        case replyToPostNumber = "reply_to_post_number"
        case username
        case name
        case displayUsername = "display_username"
        case avatarTemplate = "avatar_template"
        case cooked
        case raw
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case likeCount = "like_count"
        case replyCount = "reply_count"
        case reads
        case score
        case actionsSummary = "actions_summary"
        case reactions
        case currentUserReaction = "current_user_reaction"
        case canAct = "can_act"
        case canReply = "can_reply"
        case yours
        case postURL = "post_url"
    }

    var model: LinuxDoPost {
        let mappedActions = actionsSummary?.map(\.model) ?? []
        let actionLikeCount = mappedActions.first { $0.id == 2 }?.count ?? 0
        return LinuxDoPost(
            id: id,
            topicID: topicID,
            topicSlug: topicSlug,
            postNumber: postNumber,
            replyToPostNumber: replyToPostNumber,
            username: username,
            name: name,
            displayUsername: displayUsername,
            avatarURL: LinuxDoURLResolver.avatarURL(from: avatarTemplate),
            cookedHTML: cooked,
            raw: raw,
            createdAt: createdAt,
            updatedAt: updatedAt,
            likeCount: max(likeCount ?? 0, actionLikeCount),
            replyCount: replyCount ?? 0,
            reads: reads ?? 0,
            score: score,
            actionsSummary: mappedActions,
            reactions: reactions?.map(\.model) ?? [],
            currentUserReaction: currentUserReaction?.id.isEmpty == false ? currentUserReaction?.id : nil,
            canAct: canAct,
            canReply: canReply,
            yours: yours,
            postURL: LinuxDoURLResolver.url(from: postURL)
        )
    }

    struct ActionSummary: Decodable, Sendable {
        let id: Int
        let count: Int?
        let acted: Bool?
        let canAct: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case count
            case acted
            case canAct = "can_act"
        }

        var model: LinuxDoPostActionSummary {
            LinuxDoPostActionSummary(id: id, count: count ?? 0, acted: acted ?? false, canAct: canAct)
        }
    }
}

struct ReactionResponse: Decodable, Sendable {
    let id: String?
    let reactionValue: String?
    let reaction: String?
    let emoji: String?
    let count: Int?
    let reactionUsersCount: Int?
    let users: [ReactionUserResponse]?

    enum CodingKeys: String, CodingKey {
        case id
        case reactionValue = "reaction_value"
        case reaction
        case emoji
        case count
        case reactionUsersCount = "reaction_users_count"
        case users
    }

    var model: LinuxDoReaction {
        let reactionID = id ?? reactionValue ?? reaction ?? emoji ?? LinuxDoReactionCatalog.likeReactionID
        return LinuxDoReaction(
            id: reactionID,
            count: count ?? reactionUsersCount ?? users?.count ?? 0,
            users: users?.map(\.model) ?? []
        )
    }
}

struct ReactionUserResponse: Decodable, Sendable {
    let username: String
    let name: String?
    let avatarTemplate: String?
    let canUndo: Bool?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case username
        case name
        case avatarTemplate = "avatar_template"
        case canUndo = "can_undo"
        case createdAt = "created_at"
    }

    var model: LinuxDoReactionUserSummary {
        LinuxDoReactionUserSummary(
            username: username,
            name: name,
            avatarURL: LinuxDoURLResolver.avatarURL(from: avatarTemplate),
            canUndo: canUndo ?? false,
            createdAt: createdAt
        )
    }
}

struct FlexibleReactionValue: Decodable, Sendable {
    let id: String

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() {
                id = ""
                return
            }
            if let value = try? container.decode(String.self) {
                id = value
                return
            }
        }
        let object = try decoder.container(keyedBy: CodingKeys.self)
        id = try object.decodeIfPresent(String.self, forKey: .id)
            ?? object.decodeIfPresent(String.self, forKey: .reactionValue)
            ?? object.decodeIfPresent(String.self, forKey: .reaction)
            ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case reactionValue = "reaction_value"
        case reaction
    }
}

struct NotificationResponse: Decodable, Sendable {
    let id: Int
    let notificationType: Int
    let read: Bool?
    let createdAt: Date?
    let topicID: Int?
    let postNumber: Int?
    let slug: String?
    let data: DataNode?

    enum CodingKeys: String, CodingKey {
        case id
        case notificationType = "notification_type"
        case read
        case createdAt = "created_at"
        case topicID = "topic_id"
        case postNumber = "post_number"
        case slug
        case data
    }

    var model: LinuxDoNotification {
        LinuxDoNotification(
            id: id,
            notificationType: notificationType,
            read: read ?? false,
            createdAt: createdAt,
            topicID: topicID,
            postNumber: postNumber,
            slug: slug,
            title: data?.topicTitle ?? data?.originalTitle,
            excerpt: data?.excerpt ?? data?.displayUsername
        )
    }

    struct DataNode: Decodable, Sendable {
        let topicTitle: String?
        let originalTitle: String?
        let excerpt: String?
        let displayUsername: String?

        enum CodingKeys: String, CodingKey {
            case topicTitle = "topic_title"
            case originalTitle = "original_title"
            case excerpt
            case displayUsername = "display_username"
        }
    }
}

enum LinuxDoURLResolver {
    static let baseURL = URL(string: "https://linux.do")!

    static func url(from raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") {
            return URL(string: "https:\(raw)")
        }
        if raw.hasPrefix("/") {
            return URL(string: raw, relativeTo: baseURL)?.absoluteURL
        }
        return URL(string: raw)
    }

    static func avatarURL(from template: String?) -> URL? {
        guard let template else { return nil }
        return url(from: template.replacingOccurrences(of: "{size}", with: "96"))
    }
}
