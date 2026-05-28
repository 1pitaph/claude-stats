import Foundation

protocol LinuxDoClienting: Sendable {
    func fetchTopicList(feed: LinuxDoFeed, page: Int, now: Date) async throws -> LinuxDoTopicList
    func fetchCategories() async throws -> [LinuxDoCategory]
    func fetchTopic(id: Int, slug: String?, now: Date) async throws -> LinuxDoTopicDetail
    func fetchTopicPage(id: Int, slug: String?, page: Int, now: Date) async throws -> LinuxDoTopicDetail
    func fetchPosts(topicID: Int, postIDs: [Int]) async throws -> [LinuxDoPost]
    func fetchPostReplies(postID: Int) async throws -> [LinuxDoPost]
    func fetchReactionUsers(postID: Int, reactionID: String?) async throws -> [LinuxDoReaction]
    func fetchEmojiCatalog() async throws -> [String: URL]
    func toggleLike(postID: Int, liked: Bool) async throws -> LinuxDoPost
    func toggleReaction(postID: Int, reactionID: String) async throws -> LinuxDoPost
    func createReply(topicID: Int, raw: String, replyToPostNumber: Int?) async throws -> LinuxDoPost
    func createTopic(title: String, raw: String, categoryID: Int?) async throws -> LinuxDoPost
    func fetchCurrentUser() async throws -> LinuxDoCurrentUser
    func fetchUser(username: String) async throws -> LinuxDoCurrentUser
    func fetchUserProfile(username: String) async throws -> LinuxDoUserProfile
    func fetchCSRFToken() async throws -> String
    func fetchNotifications(limit: Int) async throws -> [LinuxDoNotification]
}

struct LinuxDoClient: LinuxDoClienting {
    enum ClientError: Error, Sendable, CustomStringConvertible, Equatable {
        case unauthorized
        case forbidden(String)
        case cloudflareChallenge
        case rateLimited(retryAfter: Date?)
        case http(status: Int)
        case network(String)
        case decoding(String)
        case invalidURL

        var description: String {
            switch self {
            case .unauthorized:
                "Linux.do rejected the saved login. Sign in again."
            case .forbidden(let message):
                message.isEmpty ? "Linux.do denied this request." : message
            case .cloudflareChallenge:
                "Linux.do is asking for a browser challenge. Open the page in your browser or try again later."
            case .rateLimited(let retryAfter):
                if let retryAfter {
                    "Linux.do rate limited the request. Try again \(Format.relativeDate(retryAfter))."
                } else {
                    "Linux.do rate limited the request. Try again later."
                }
            case .http(let status):
                "Linux.do returned HTTP \(status)."
            case .network:
                "Linux.do is unreachable."
            case .decoding:
                "Linux.do returned an unexpected response."
            case .invalidURL:
                "Could not build a Linux.do request."
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession
    private let credentials: any LinuxDoCredentialStoring

    init(
        baseURL: URL = URL(string: "https://linux.do")!,
        session: URLSession = .shared,
        credentials: any LinuxDoCredentialStoring = LinuxDoKeychainStore.shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.credentials = credentials
    }

    func fetchTopicList(feed: LinuxDoFeed, page: Int = 0, now: Date = .now) async throws -> LinuxDoTopicList {
        switch feed {
        case .latest:
            let response: TopicListResponse = try await get(path: "/latest.json", queryItems: [pageItem(page)])
            return LinuxDoResponseMapper.topicList(from: response, page: page, now: now)
        case .hot:
            let response: TopicListResponse = try await get(path: "/hot.json", queryItems: [pageItem(page)])
            return LinuxDoResponseMapper.topicList(from: response, page: page, now: now)
        case .top(let period):
            let response: TopicListResponse = try await get(
                path: "/top.json",
                queryItems: [
                    URLQueryItem(name: "period", value: period.rawValue),
                    pageItem(page),
                ]
            )
            return LinuxDoResponseMapper.topicList(from: response, page: page, now: now)
        case .category(let id, _, _):
            let response: TopicListResponse = try await get(
                path: "/latest.json",
                queryItems: [
                    URLQueryItem(name: "category", value: "\(id)"),
                    pageItem(page),
                ]
            )
            return LinuxDoResponseMapper.topicList(from: response, page: page, now: now)
        case .search(let query):
            let response: SearchResponse = try await get(
                path: "/search.json",
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    pageItem(page),
                ]
            )
            return LinuxDoResponseMapper.topicList(from: response, page: page, now: now)
        }
    }

    func fetchCategories() async throws -> [LinuxDoCategory] {
        let response: CategoriesResponse = try await get(path: "/categories.json")
        return response.categories
    }

    func fetchTopic(id: Int, slug: String? = nil, now: Date = .now) async throws -> LinuxDoTopicDetail {
        let path = "/t/\(slug?.isEmpty == false ? slug! : "topic")/\(id).json"
        let response: TopicDetailResponse = try await get(path: path)
        return LinuxDoResponseMapper.topicDetail(from: response, now: now)
    }

    func fetchTopicPage(id: Int, slug: String? = nil, page: Int, now: Date = .now) async throws -> LinuxDoTopicDetail {
        let path = "/t/\(slug?.isEmpty == false ? slug! : "topic")/\(id).json"
        let response: TopicDetailResponse = try await get(path: path, queryItems: [pageItem(page)])
        return LinuxDoResponseMapper.topicDetail(from: response, now: now)
    }

    func fetchPosts(topicID: Int, postIDs: [Int]) async throws -> [LinuxDoPost] {
        guard !postIDs.isEmpty else { return [] }
        let queryItems = postIDs.map { URLQueryItem(name: "post_ids[]", value: "\($0)") }
        let response: TopicPostsResponse = try await get(path: "/t/\(topicID)/posts.json", queryItems: queryItems)
        return LinuxDoResponseMapper.posts(from: response)
    }

    func fetchPostReplies(postID: Int) async throws -> [LinuxDoPost] {
        let response: [PostResponse] = try await get(path: "/posts/\(postID)/replies.json")
        return response.map(\.model)
    }

    func fetchReactionUsers(postID: Int, reactionID: String? = nil) async throws -> [LinuxDoReaction] {
        var queryItems = [URLQueryItem(name: "include_likes", value: "true")]
        if let reactionID, !reactionID.isEmpty {
            queryItems.append(URLQueryItem(name: "reaction_value", value: reactionID))
        }
        let response: ReactionUsersResponse = try await get(
            path: "/discourse-reactions/posts/\(postID)/reactions-users.json",
            queryItems: queryItems
        )
        return LinuxDoResponseMapper.reactionUsers(from: response)
    }

    func fetchEmojiCatalog() async throws -> [String: URL] {
        let response: EmojiCatalogResponse = try await get(path: "/emojis.json")
        return LinuxDoResponseMapper.emojiURLs(from: response)
    }

    func toggleLike(postID: Int, liked: Bool) async throws -> LinuxDoPost {
        if liked {
            let response: PostResponse = try await json(
                path: "/post_actions.json",
                method: "POST",
                body: PostActionRequest(id: postID, postActionTypeID: 2),
                requiresWebSession: true
            )
            return response.model
        }
        let response: PostResponse = try await json(
            path: "/post_actions/\(postID).json",
            method: "DELETE",
            body: DeletePostActionRequest(postActionTypeID: 2),
            requiresWebSession: true
        )
        return response.model
    }

    func toggleReaction(postID: Int, reactionID: String) async throws -> LinuxDoPost {
        let encodedReaction = reactionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? reactionID
        let response: PostResponse = try await json(
            path: "/discourse-reactions/posts/\(postID)/custom-reactions/\(encodedReaction)/toggle.json",
            method: "PUT",
            body: EmptyRequest(),
            requiresWebSession: true
        )
        return response.model
    }

    func createReply(topicID: Int, raw: String, replyToPostNumber: Int?) async throws -> LinuxDoPost {
        let response: PostResponse = try await json(
            path: "/posts.json",
            method: "POST",
            body: CreatePostRequest(raw: raw, topicID: topicID, replyToPostNumber: replyToPostNumber),
            requiresWebSession: true
        )
        return response.model
    }

    func createTopic(title: String, raw: String, categoryID: Int?) async throws -> LinuxDoPost {
        let response: PostResponse = try await json(
            path: "/posts.json",
            method: "POST",
            body: CreatePostRequest(title: title, raw: raw, categoryID: categoryID),
            requiresWebSession: true
        )
        return response.model
    }

    func fetchCurrentUser() async throws -> LinuxDoCurrentUser {
        let response: CurrentUserResponse = try await get(path: "/session/current.json", requiresAuthentication: true)
        let currentUser = response.currentUser.currentUser
        guard currentUser.avatarURL == nil else { return currentUser }
        do {
            let profileUser = try await fetchUser(username: currentUser.username)
            return LinuxDoCurrentUser(
                id: currentUser.id,
                username: currentUser.username,
                name: currentUser.name ?? profileUser.name,
                avatarURL: profileUser.avatarURL
            )
        } catch {
            Log.network.notice("LinuxDo profile avatar fallback failed for @\(currentUser.username, privacy: .public): \(String(describing: error), privacy: .public)")
            return currentUser
        }
    }

    func fetchUser(username: String) async throws -> LinuxDoCurrentUser {
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let response: UserProfileResponse = try await get(path: "/u/\(encodedUsername).json")
        return response.currentUser
    }

    func fetchUserProfile(username: String) async throws -> LinuxDoUserProfile {
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let response: UserProfileResponse = try await get(path: "/u/\(encodedUsername).json")
        return LinuxDoResponseMapper.userProfile(from: response)
    }

    func fetchCSRFToken() async throws -> String {
        let response: CSRFResponse = try await get(path: "/session/csrf")
        return response.csrf
    }

    func fetchNotifications(limit: Int = 30) async throws -> [LinuxDoNotification] {
        let response: NotificationsResponse = try await get(
            path: "/notifications.json",
            queryItems: [URLQueryItem(name: "limit", value: "\(limit)")],
            requiresAuthentication: true
        )
        return response.notifications.map(\.model)
    }

    private func get<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        requiresAuthentication: Bool = false
    ) async throws -> T {
        try await request(path: path, queryItems: queryItems, method: "GET", requiresAuthentication: requiresAuthentication)
    }

    private func json<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        requiresWebSession: Bool
    ) async throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try await request(
            path: path,
            method: method,
            requiresAuthentication: true,
            requiresWebSession: requiresWebSession,
            bodyData: try encoder.encode(body)
        )
    }

    private func request<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        requiresAuthentication: Bool,
        requiresWebSession: Bool = false,
        bodyData: Data? = nil
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ClientError.invalidURL
        }
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { throw ClientError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if method != "GET" || bodyData != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = bodyData
        let credential = try await credential(
            requiresAuthentication: requiresAuthentication,
            requiresWebSession: requiresWebSession,
            method: method
        )
        if requiresAuthentication, credential == nil {
            throw ClientError.unauthorized
        }

        do {
            return try await perform(
                request: request,
                path: path,
                method: method,
                credential: credential
            )
        } catch ClientError.unauthorized where !requiresAuthentication {
            if case .webSession? = credential {
                credentials.deleteWebSession()
                return try await perform(
                    request: request,
                    path: path,
                    method: method,
                    credential: nil
                )
            }
            throw ClientError.unauthorized
        }
    }

    private func perform<T: Decodable>(
        request originalRequest: URLRequest,
        path: String,
        method: String,
        credential: LinuxDoAuthCredential?
    ) async throws -> T {
        var request = originalRequest
        apply(credential: credential, to: &request)

        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw ClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.http(status: -1)
        }
        Log.network.notice("LinuxDo \(method, privacy: .public) \(path, privacy: .public) \(http.statusCode, privacy: .public) in \(Int(Date().timeIntervalSince(started) * 1000))ms")

        try Self.validate(data: data, http: http)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeDate)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let message = Self.decodingMessage(error)
            Log.network.error("LinuxDo decode failed for \(path, privacy: .public): \(message, privacy: .public)")
            throw ClientError.decoding(message)
        }
    }

    private func credential(
        requiresAuthentication: Bool,
        requiresWebSession: Bool,
        method: String
    ) async throws -> LinuxDoAuthCredential? {
        guard requiresWebSession else {
            return credentials.readAuthCredential()
        }
        guard var session = credentials.readWebSession(), session.isAuthenticated else {
            throw ClientError.unauthorized
        }
        if method != "GET", session.csrfToken?.isEmpty != false {
            let csrf = try await fetchCSRFToken(using: session)
            session = session.with(csrfToken: csrf, username: session.username, avatarURL: session.avatarURL)
            try? credentials.saveWebSession(session)
        }
        if requiresAuthentication || session.isAuthenticated {
            return .webSession(session)
        }
        return nil
    }

    private func fetchCSRFToken(using session: LinuxDoWebSession) async throws -> String {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ClientError.invalidURL
        }
        components.path = "/session/csrf"
        guard let url = components.url else { throw ClientError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let response: CSRFResponse = try await perform(
            request: request,
            path: "/session/csrf",
            method: "GET",
            credential: .webSession(session)
        )
        return response.csrf
    }

    private func apply(credential: LinuxDoAuthCredential?, to request: inout URLRequest) {
        switch credential {
        case .webSession(let session):
            if let cookieHeader = session.cookieHeader() {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
                if let csrfToken = session.csrfToken, !csrfToken.isEmpty {
                    request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
                }
                if session.containsCookie(named: "_t") {
                    request.setValue("true", forHTTPHeaderField: "Discourse-Logged-In")
                    request.setValue("true", forHTTPHeaderField: "Discourse-Present")
                }
            }
        case nil:
            break
        }
    }

    private func pageItem(_ page: Int) -> URLQueryItem {
        URLQueryItem(name: "page", value: "\(page)")
    }

    private static func validate(data: Data, http: HTTPURLResponse) throws {
        if isCloudflareChallenge(data: data, http: http) {
            throw ClientError.cloudflareChallenge
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw ClientError.unauthorized
        case 403:
            throw ClientError.forbidden(errorMessage(from: data) ?? "")
        case 429:
            throw ClientError.rateLimited(retryAfter: retryAfter(http: http, now: .now))
        default:
            throw ClientError.http(status: http.statusCode)
        }
    }

    private static func isCloudflareChallenge(data: Data, http: HTTPURLResponse) -> Bool {
        if (http.value(forHTTPHeaderField: "cf-mitigated") ?? "").lowercased() == "challenge" {
            return true
        }
        guard !data.isEmpty,
              let body = String(data: data.prefix(65_536), encoding: .utf8) else {
            return false
        }
        return body.contains("Just a moment...")
            || body.contains("cf-browser-verification")
            || body.contains("__cf_chl_")
    }

    private static func retryAfter(http: HTTPURLResponse, now: Date) -> Date? {
        guard let raw = http.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(raw) {
            return now.addingTimeInterval(seconds)
        }
        return HTTPDateFormatter.shared.date(from: raw)
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let errors = object["errors"] as? [String], let first = errors.first {
            return first
        }
        return object["message"] as? String
    }

    private static func decodingMessage(_ error: Error) -> String {
        func path(_ codingPath: [CodingKey]) -> String {
            let raw = codingPath.map(\.stringValue).joined(separator: ".")
            return raw.isEmpty ? "<root>" : raw
        }

        switch error {
        case DecodingError.typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(path(context.codingPath)): \(context.debugDescription)"
        case DecodingError.valueNotFound(let type, let context):
            return "Missing value for \(type) at \(path(context.codingPath)): \(context.debugDescription)"
        case DecodingError.keyNotFound(let key, let context):
            return "Missing key \(key.stringValue) at \(path(context.codingPath)): \(context.debugDescription)"
        case DecodingError.dataCorrupted(let context):
            return "Corrupt data at \(path(context.codingPath)): \(context.debugDescription)"
        default:
            return String(describing: error)
        }
    }

    private static func decodeDate(from decoder: Decoder) throws -> Date {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) {
            return date
        }
        throw ClientError.decoding("Invalid date \(raw)")
    }

    static let userAgent: String = {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
        return "ClaudeStats/\(version)"
    }()
}

private struct EmptyRequest: Encodable {}

private struct PostActionRequest: Encodable {
    let id: Int
    let postActionTypeID: Int

    enum CodingKeys: String, CodingKey {
        case id
        case postActionTypeID = "post_action_type_id"
    }
}

private struct DeletePostActionRequest: Encodable {
    let postActionTypeID: Int

    enum CodingKeys: String, CodingKey {
        case postActionTypeID = "post_action_type_id"
    }
}

private struct CreatePostRequest: Encodable {
    let title: String?
    let raw: String
    let topicID: Int?
    let categoryID: Int?
    let replyToPostNumber: Int?

    init(title: String? = nil, raw: String, topicID: Int? = nil, categoryID: Int? = nil, replyToPostNumber: Int? = nil) {
        self.title = title
        self.raw = raw
        self.topicID = topicID
        self.categoryID = categoryID
        self.replyToPostNumber = replyToPostNumber
    }

    enum CodingKeys: String, CodingKey {
        case title
        case raw
        case topicID = "topic_id"
        case categoryID = "category"
        case replyToPostNumber = "reply_to_post_number"
    }
}

private final class HTTPDateFormatter: @unchecked Sendable {
    static let shared = HTTPDateFormatter()
    private let lock = NSLock()
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }()

    func date(from raw: String) -> Date? {
        lock.withLock { formatter.date(from: raw) }
    }
}
