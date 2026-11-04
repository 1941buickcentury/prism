import Foundation
import Observation

@Observable
@MainActor
final class RedditClient {
    let auth: AuthManager

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(auth: AuthManager) {
        self.auth = auth
    }

    // MARK: Transport

    func request(_ path: String,
                 query: [String: String] = [:],
                 method: String = "GET",
                 form: [String: String]? = nil,
                 retry: Bool = true) async throws -> Data {
        let token = try await auth.validAccessToken()
        guard var components = URLComponents(string: "https://oauth.reddit.com" + path) else {
            throw RedditError.api("Invalid request path.")
        }
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "raw_json", value: "1"))
        components.queryItems = items
        guard let url = components.url else { throw RedditError.api("Invalid request.") }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(auth.userAgent, forHTTPHeaderField: "User-Agent")
        if let form {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = FormEncoder.encode(form)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && retry {
            auth.invalidateAccessToken()
            return try await request(path, query: query, method: method, form: form, retry: false)
        }
        guard (200..<300).contains(code) else {
            throw RedditError.http(code, String(decoding: data, as: UTF8.self))
        }
        return data
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let data = try await request(path, query: query)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw RedditError.decoding("\(path): \(error.localizedDescription)")
        }
    }

    // MARK: Account

    func refreshAccount() async {
        guard auth.isLoggedIn else {
            auth.account = nil
            return
        }
        let me: Account? = try? await get("/api/v1/me")
        if let me {
            auth.account = me
        }
    }

    func user(_ name: String) async throws -> Account {
        let wrapped: Wrapped<Account> = try await get("/user/\(name)/about")
        return wrapped.data
    }

    func userListing(_ name: String, section: String, after: String?) async throws -> ThingListing {
        var q = ["limit": "25"]
        if let after { q["after"] = after }
        return try await get("/user/\(name)/\(section)", query: q)
    }

    // MARK: Feeds

    func feed(_ source: FeedSource, sort: FeedSort, time: TopTime, after: String?) async throws -> Listing<Post> {
        var q = ["limit": "25"]
        if let after { q["after"] = after }
        if sort.usesTime { q["t"] = time.rawValue }
        return try await get(source.path + "/" + sort.rawValue, query: q)
    }

    func comments(postID: String, sort: CommentSort, focus: String?) async throws -> (Post?, [Thing]) {
        var q = ["sort": sort.rawValue, "limit": "200"]
        if let focus {
            q["comment"] = focus
            q["context"] = "3"
        }
        let listings: [ThingListing] = try await get("/comments/\(postID)", query: q)
        var post: Post?
        if let first = listings.first, case .post(let p)? = first.items.first { post = p }
        let comments = listings.count > 1 ? listings[1].items : []
        return (post, comments)
    }

    func moreChildren(linkName: String, children: [String], sort: CommentSort) async throws -> [Thing] {
        let response: ThingsResponse = try await get("/api/morechildren", query: [
            "api_type": "json",
            "link_id": linkName,
            "children": children.joined(separator: ","),
            "sort": sort.rawValue,
            "limit_children": "false"
        ])
        return response.json.things
    }

    // MARK: Actions

    func vote(_ name: String, dir: Int) async throws {
        _ = try await request("/api/vote", method: "POST", form: ["id": name, "dir": String(dir)])
    }

    func setSaved(_ name: String, saved: Bool) async throws {
        _ = try await request(saved ? "/api/save" : "/api/unsave", method: "POST", form: ["id": name])
    }

    /// Posts a comment or a message reply. Returns the new thing Reddit sends back.
    func reply(to parent: String, text: String) async throws -> Thing? {
        let data = try await request("/api/comment", method: "POST", form: [
            "api_type": "json",
            "thing_id": parent,
            "text": text
        ])
        let response = try decoder.decode(ThingsResponse.self, from: data)
        if let error = response.json.errors.first { throw RedditError.api(error) }
        return response.json.things.first
    }

    // MARK: Inbox

    func inbox(_ box: InboxBox, after: String?) async throws -> Listing<Message> {
        var q = ["limit": "25", "mark": "false"]
        if let after { q["after"] = after }
        return try await get("/message/\(box.rawValue)", query: q)
    }

    func markRead(_ names: [String]) async throws {
        _ = try await request("/api/read_message", method: "POST", form: ["id": names.joined(separator: ",")])
    }

    func markAllRead() async throws {
        _ = try await request("/api/read_all_messages", method: "POST", form: [:])
    }

    // MARK: Subreddits

    func subscriptions() async throws -> [Subreddit] {
        var all: [Subreddit] = []
        var after: String?
        for _ in 0..<10 {
            var q = ["limit": "100"]
            if let after { q["after"] = after }
            let page: Listing<Subreddit> = try await get("/subreddits/mine/subscriber", query: q)
            all += page.items
            after = page.after
            if after == nil { break }
        }
        return all.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func defaultSubreddits() async throws -> [Subreddit] {
        let page: Listing<Subreddit> = try await get("/subreddits/default", query: ["limit": "50"])
        return page.items
    }

    func about(_ subreddit: String) async throws -> Subreddit {
        let wrapped: Wrapped<Subreddit> = try await get("/r/\(subreddit)/about")
        return wrapped.data
    }

    func subscribe(_ subreddit: String, subscribe: Bool) async throws {
        _ = try await request("/api/subscribe", method: "POST", form: [
            "action": subscribe ? "sub" : "unsub",
            "sr_name": subreddit
        ])
    }

    // MARK: Search

    func searchSubreddits(_ query: String) async throws -> [Subreddit] {
        let page: Listing<Subreddit> = try await get("/subreddits/search", query: ["q": query, "limit": "25"])
        return page.items
    }

    func searchPosts(_ query: String, after: String?) async throws -> Listing<Post> {
        var q = ["q": query, "limit": "25", "type": "link", "sort": "relevance"]
        if let after { q["after"] = after }
        return try await get("/search", query: q)
    }
}
