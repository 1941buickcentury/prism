import SwiftUI
import Observation

enum FeedSource: Hashable {
    case home
    case popular
    case all
    case subreddit(String)

    var path: String {
        switch self {
        case .home: return ""
        case .popular: return "/r/popular"
        case .all: return "/r/all"
        case .subreddit(let name): return "/r/\(name)"
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .popular: return "Popular"
        case .all: return "All"
        case .subreddit(let name): return "r/\(name)"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .popular: return "flame.fill"
        case .all: return "globe"
        case .subreddit: return "number"
        }
    }

    var key: String { path.isEmpty ? "home" : path }
}

enum FeedSort: String, CaseIterable, Identifiable {
    case best, hot, new, top, rising, controversial

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var usesTime: Bool { self == .top || self == .controversial }

    var icon: String {
        switch self {
        case .best: return "rosette"
        case .hot: return "flame"
        case .new: return "sparkles"
        case .top: return "chart.bar"
        case .rising: return "chart.line.uptrend.xyaxis"
        case .controversial: return "bolt"
        }
    }
}

enum TopTime: String, CaseIterable, Identifiable {
    case hour, day, week, month, year, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hour: return "Past Hour"
        case .day: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        case .year: return "This Year"
        case .all: return "All Time"
        }
    }
}

enum CommentSort: String, CaseIterable, Identifiable {
    case confidence, top, new, controversial, old, qa

    var id: String { rawValue }

    var title: String {
        switch self {
        case .confidence: return "Best"
        case .top: return "Top"
        case .new: return "New"
        case .controversial: return "Controversial"
        case .old: return "Old"
        case .qa: return "Q&A"
        }
    }

    var icon: String {
        switch self {
        case .confidence: return "rosette"
        case .top: return "chart.bar"
        case .new: return "sparkles"
        case .controversial: return "bolt"
        case .old: return "clock.arrow.circlepath"
        case .qa: return "questionmark.bubble"
        }
    }
}

enum InboxBox: String, CaseIterable, Identifiable {
    case inbox, unread, sent

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum Route: Hashable {
    case feed(FeedSource)
    case post(Post)
    case postID(String, focus: String?)
    case user(String)
    case message(Message)
    case settings
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct MediaPresentation: Identifiable {
    let id = UUID()
    let media: PostMedia
    let title: String
}

/// One per tab: its navigation path, plus the in-app browser and media viewer it presents.
@Observable
final class Router {
    var path = NavigationPath()
    var safari: IdentifiedURL?
    var media: MediaPresentation?

    func push(_ route: Route) {
        path.append(route)
    }

    func open(_ url: URL, inApp: Bool) -> OpenURLAction.Result {
        if let route = RedditLink.route(for: url) {
            push(route)
            return .handled
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .systemAction
        }
        if inApp {
            safari = IdentifiedURL(url: url)
            return .handled
        }
        return .systemAction
    }
}

/// Turns reddit.com links (and bare /r/ and /u/ links from comments) into in-app routes.
enum RedditLink {
    static func route(for url: URL) -> Route? {
        let host = url.host()?.lowercased() ?? ""
        let isReddit = host == "reddit.com" || host.hasSuffix(".reddit.com")
        if !host.isEmpty && !isReddit && host != "redd.it" { return nil }

        if host == "redd.it" {
            let id = url.lastPathComponent
            return id.isEmpty || id == "/" ? nil : .postID(id, focus: nil)
        }

        let parts = url.path().split(separator: "/").map(String.init)
        guard let first = parts.first?.lowercased() else { return nil }
        if host.isEmpty && !["r", "u", "user"].contains(first) { return nil }

        switch first {
        case "r":
            guard parts.count >= 2 else { return nil }
            if parts.count >= 4, parts[2] == "comments" {
                return .postID(parts[3], focus: parts.count >= 6 ? parts[5] : nil)
            }
            if parts.count >= 3, parts[2] == "s" { return nil } // share links need a redirect; open in browser
            return .feed(.subreddit(parts[1]))
        case "u", "user":
            guard parts.count >= 2 else { return nil }
            if parts.count >= 4, parts[2] == "comments" {
                return .postID(parts[3], focus: nil)
            }
            return .user(parts[1])
        case "comments":
            guard parts.count >= 2 else { return nil }
            return .postID(parts[1], focus: parts.count >= 4 ? parts[3] : nil)
        default:
            return nil
        }
    }

    /// Cleans up typed subreddit names: "/r/Pics " → "Pics".
    static func subredditName(from input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["/r/", "r/"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        let cleaned = text.filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return cleaned.isEmpty ? nil : cleaned
    }
}
