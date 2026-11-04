import Foundation

// MARK: - Media building blocks

struct ImageSource: Decodable {
    let url: String?
    let width: Int?
    let height: Int?
}

struct VariantImage: Decodable {
    let source: ImageSource?
}

struct Variants: Decodable {
    let gif: VariantImage?
    let mp4: VariantImage?
}

struct PreviewImage: Decodable {
    let source: ImageSource?
    let resolutions: [ImageSource]?
    let variants: Variants?
}

struct RedditVideo: Decodable {
    let fallbackUrl: String?
    let hlsUrl: String?
    let width: Int?
    let height: Int?
    let isGif: Bool?
}

struct Preview: Decodable {
    let images: [PreviewImage]?
    let redditVideoPreview: RedditVideo?
}

struct Media: Decodable {
    let redditVideo: RedditVideo?
}

struct GalleryItem: Decodable {
    let mediaId: String
    let caption: String?
}

struct GalleryData: Decodable {
    let items: [GalleryItem]
}

struct MetaSource: Decodable {
    let u: String?
    let gif: String?
    let mp4: String?
    let x: Int?
    let y: Int?
}

struct MediaMetadata: Decodable {
    let status: String?
    let e: String?
    let s: MetaSource?
    let p: [MetaSource]?
}

// MARK: - Things

struct Post: Decodable, Identifiable {
    let id: String
    let name: String
    let title: String
    let author: String
    let subreddit: String
    let subredditNamePrefixed: String?
    let score: Int
    let numComments: Int
    let createdUtc: Double
    let selftext: String?
    let url: String?
    let permalink: String
    let thumbnail: String?
    let isSelf: Bool?
    let isVideo: Bool?
    let over18: Bool?
    let spoiler: Bool?
    let stickied: Bool?
    let locked: Bool?
    let likes: Bool?
    let saved: Bool?
    let domain: String?
    let postHint: String?
    let preview: Preview?
    let media: Media?
    let secureMedia: Media?
    let isGallery: Bool?
    let galleryData: GalleryData?
    let mediaMetadata: [String: MediaMetadata]?
    let linkFlairText: String?
    let upvoteRatio: Double?
    let distinguished: String?
    let crosspostParentList: [Post]?
}

extension Post: Hashable {
    static func == (lhs: Post, rhs: Post) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

struct Comment: Decodable, Identifiable {
    let id: String
    let name: String
    let author: String?
    let body: String?
    let score: Int?
    let createdUtc: Double?
    let depth: Int?
    let likes: Bool?
    let saved: Bool?
    let isSubmitter: Bool?
    let stickied: Bool?
    let distinguished: String?
    let scoreHidden: Bool?
    let linkId: String?
    let linkTitle: String?
    let subreddit: String?
    let permalink: String?
    let parentId: String?
    let authorFlairText: String?
    let collapsed: Bool?
    var replies: Replies?
}

/// Reddit sends `replies` as either an empty string or a nested listing.
struct Replies: Decodable {
    let things: [Thing]

    init(from decoder: Decoder) throws {
        things = (try? ThingListing(from: decoder))?.items ?? []
    }
}

struct More: Decodable {
    let id: String
    let name: String
    let count: Int?
    let children: [String]?
    let depth: Int?
    let parentId: String?
}

struct Message: Decodable, Identifiable {
    let id: String
    let name: String
    let author: String?
    let dest: String?
    let subject: String?
    let body: String?
    let createdUtc: Double?
    var new: Bool?
    let wasComment: Bool?
    let context: String?
    let subreddit: String?
    let linkTitle: String?
}

extension Message: Hashable {
    static func == (lhs: Message, rhs: Message) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

struct Subreddit: Decodable, Identifiable {
    let displayName: String
    let displayNamePrefixed: String?
    let title: String?
    let publicDescription: String?
    let subscribers: Int?
    let iconImg: String?
    let communityIcon: String?
    let bannerBackgroundImage: String?
    let bannerImg: String?
    let primaryColor: String?
    let keyColor: String?
    var userIsSubscriber: Bool?
    let over18: Bool?

    var id: String { displayName }

    var prefixed: String { displayNamePrefixed ?? "r/\(displayName)" }

    var iconURL: URL? {
        let raw = [communityIcon, iconImg].compactMap { $0 }.first { !$0.isEmpty }
        return raw.flatMap(URL.init(string:))
    }

    var bannerURL: URL? {
        let raw = [bannerBackgroundImage, bannerImg].compactMap { $0 }.first { !$0.isEmpty }
        return raw.flatMap(URL.init(string:))
    }
}

struct Account: Decodable {
    let name: String
    let iconImg: String?
    let snoovatarImg: String?
    let linkKarma: Int?
    let commentKarma: Int?
    let totalKarma: Int?
    let createdUtc: Double?
    let inboxCount: Int?
    let hasMail: Bool?

    var avatarURL: URL? {
        let raw = [snoovatarImg, iconImg].compactMap { $0 }.first { !$0.isEmpty }
        return raw.flatMap(URL.init(string:))
    }
}

// MARK: - Kind-aware wrapper

enum Thing: Decodable {
    case post(Post)
    case comment(Comment)
    case more(More)
    case message(Message)
    case subreddit(Subreddit)
    case account(Account)
    case other

    enum CodingKeys: String, CodingKey { case kind, data }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        func value<T: Decodable>(_ type: T.Type) -> T? { try? c.decode(type, forKey: .data) }
        switch kind {
        case "t3": self = value(Post.self).map(Thing.post) ?? .other
        case "t1": self = value(Comment.self).map(Thing.comment) ?? .other
        case "more": self = value(More.self).map(Thing.more) ?? .other
        case "t4": self = value(Message.self).map(Thing.message) ?? .other
        case "t5": self = value(Subreddit.self).map(Thing.subreddit) ?? .other
        case "t2": self = value(Account.self).map(Thing.account) ?? .other
        default: self = .other
        }
    }

    var rowID: String {
        switch self {
        case .post(let p): return p.name
        case .comment(let c): return c.name
        case .more(let m): return m.name
        case .message(let m): return m.name
        case .subreddit(let s): return s.displayName
        case .account(let a): return a.name
        case .other: return "other"
        }
    }

    var isOther: Bool {
        if case .other = self { return true }
        return false
    }
}

// MARK: - Listings

/// A child whose `data` is decoded as `T`; a child that fails to decode is skipped instead of failing the page.
struct ListingChild<T: Decodable>: Decodable {
    let value: T?
    enum CodingKeys: String, CodingKey { case data }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try? c.decode(T.self, forKey: .data)
    }
}

struct Listing<T: Decodable>: Decodable {
    let after: String?
    let items: [T]

    enum Outer: String, CodingKey { case data }
    enum Inner: String, CodingKey { case after, children }

    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: Outer.self)
        let inner = try outer.nestedContainer(keyedBy: Inner.self, forKey: .data)
        after = try? inner.decode(String.self, forKey: .after)
        items = try inner.decode([ListingChild<T>].self, forKey: .children).compactMap { $0.value }
    }
}

struct ThingListing: Decodable {
    let after: String?
    let items: [Thing]

    enum Outer: String, CodingKey { case data }
    enum Inner: String, CodingKey { case after, children }

    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: Outer.self)
        let inner = try outer.nestedContainer(keyedBy: Inner.self, forKey: .data)
        after = try? inner.decode(String.self, forKey: .after)
        items = try inner.decode([Thing].self, forKey: .children)
    }
}

struct Wrapped<T: Decodable>: Decodable {
    let data: T
}

/// Shape of `api_type=json` responses (comment, morechildren).
struct ThingsResponse: Decodable {
    let json: Body

    struct Body: Decodable {
        let errors: [String]
        let things: [Thing]

        enum CodingKeys: String, CodingKey { case errors, data }
        struct DataBlock: Decodable { let things: [Thing]? }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            things = (try? c.decode(DataBlock.self, forKey: .data))?.things ?? []
            let raw = (try? c.decode([[String?]].self, forKey: .errors)) ?? []
            errors = raw.map { parts in
                let strings = parts.compactMap { $0 }
                return strings.count > 1 ? strings[1] : strings.joined(separator: " ")
            }
        }
    }
}

struct TokenResponse: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let refreshToken: String?
    let error: String?
}
