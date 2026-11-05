import SwiftUI
import UIKit
import Observation

enum CommentItem: Identifiable {
    case comment(Comment, Int)
    case more(More, Int)

    var id: String {
        switch self {
        case .comment(let c, _): return c.name
        case .more(let m, _): return m.name
        }
    }

    var depth: Int {
        switch self {
        case .comment(_, let d): return d
        case .more(_, let d): return d
        }
    }
}

struct ComposerTarget: Identifiable {
    let id = UUID()
    let parentName: String
    let context: String?
    let parentDepth: Int
    let title: String
}

@Observable
@MainActor
final class PostDetailModel {
    let postID: String
    var post: Post?
    var focus: String?
    var items: [CommentItem] = []
    var collapsed: Set<String> = []
    var loadingMore: Set<String> = []
    var sort: CommentSort = .confidence
    var isLoading = false
    var error: String?

    init(postID: String, post: Post?, focus: String?) {
        self.postID = postID
        self.post = post
        self.focus = focus
    }

    /// Comments with collapsed threads' descendants removed.
    var visibleItems: [CommentItem] {
        var result: [CommentItem] = []
        var hideBelow: Int?
        for item in items {
            if let limit = hideBelow {
                if item.depth > limit { continue }
                hideBelow = nil
            }
            result.append(item)
            if case .comment(let c, let depth) = item, collapsed.contains(c.name) {
                hideBelow = depth
            }
        }
        return result
    }

    func load(client: RedditClient) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let (fetched, things) = try await client.comments(postID: postID, sort: sort, focus: focus)
            if let fetched { post = fetched }
            var flat: [CommentItem] = []
            Self.flatten(things, depth: 0, into: &flat)
            items = flat
            collapsed = Set(flat.compactMap { item in
                if case .comment(let c, _) = item, c.collapsed == true { return c.name }
                return nil
            })
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func showAll(client: RedditClient) async {
        focus = nil
        await load(client: client)
    }

    func toggleCollapse(_ name: String) {
        if collapsed.contains(name) {
            collapsed.remove(name)
        } else {
            collapsed.insert(name)
        }
    }

    /// Loads hidden replies in place. Returns a route when Reddit wants the thread opened on its own.
    func loadMore(_ more: More, client: RedditClient) async -> Route? {
        let children = more.children ?? []
        if children.isEmpty || more.id == "_" {
            guard let parent = more.parentId, parent.hasPrefix("t1_") else { return nil }
            return .postID(postID, focus: String(parent.dropFirst(3)))
        }
        loadingMore.insert(more.name)
        defer { loadingMore.remove(more.name) }

        let batch = Array(children.prefix(100))
        let remaining = Array(children.dropFirst(100))
        do {
            let things = try await client.moreChildren(linkName: post?.name ?? "t3_\(postID)", children: batch, sort: sort)
            var flat: [CommentItem] = []
            Self.flatten(things, depth: more.depth ?? 0, into: &flat)
            if !remaining.isEmpty {
                let rest = More(id: more.id, name: more.name + "_rest\(remaining.count)", count: remaining.count,
                                children: remaining, depth: more.depth, parentId: more.parentId)
                flat.append(.more(rest, more.depth ?? 0))
            }
            if let index = items.firstIndex(where: { $0.id == more.name }) {
                items.replaceSubrange(index...index, with: flat)
            }
        } catch {
            self.error = error.localizedDescription
        }
        return nil
    }

    func insertReply(_ thing: Thing, target: ComposerTarget) {
        guard case .comment(let comment) = thing else { return }
        if target.parentDepth < 0 {
            items.insert(.comment(comment, 0), at: 0)
        } else if let index = items.firstIndex(where: { $0.id == target.parentName }) {
            items.insert(.comment(comment, target.parentDepth + 1), at: index + 1)
            collapsed.remove(target.parentName)
        }
    }

    static func flatten(_ things: [Thing], depth: Int, into out: inout [CommentItem]) {
        for thing in things {
            switch thing {
            case .comment(let comment):
                let d = comment.depth ?? depth
                var stripped = comment
                stripped.replies = nil
                out.append(.comment(stripped, d))
                if let replies = comment.replies?.things, !replies.isEmpty {
                    flatten(replies, depth: d + 1, into: &out)
                }
            case .more(let more):
                out.append(.more(more, more.depth ?? depth))
            default:
                break
            }
        }
    }
}

struct PostDetailView: View {
    @State private var model: PostDetailModel
    @State private var composer: ComposerTarget?
    @Environment(RedditClient.self) private var client
    @Environment(ActionStore.self) private var actions
    @Environment(Router.self) private var router
    @AppStorage("commentSort") private var defaultSort = CommentSort.confidence.rawValue
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(ThemeManager.self) private var theme
    private let preferStacked: Bool

    init(post: Post, preferStacked: Bool = false) {
        self.preferStacked = preferStacked
        _model = State(initialValue: PostDetailModel(postID: post.id, post: post, focus: nil))
    }

    init(id: String, focus: String?, preferStacked: Bool = false) {
        self.preferStacked = preferStacked
        _model = State(initialValue: PostDetailModel(postID: id, post: nil, focus: focus))
    }

    var body: some View {
        Group {
            if hSize == .regular && !preferStacked {
                splitLayout
            } else {
                stackedLayout
            }
        }
        .background(AmbientBackground())
        .navigationTitle(model.post?.subredditPrefixed ?? "Post")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $composer) { target in
            ComposerView(target: target) { thing in
                model.insertReply(thing, target: target)
            }
        }
        .task {
            if model.items.isEmpty {
                model.sort = CommentSort(rawValue: defaultSort) ?? .confidence
                await model.load(client: client)
            }
        }
        .onChange(of: model.sort) {
            Task { await model.load(client: client) }
        }
    }

    /// Outer display and regular iPhones: post on top, comments below, one scrolling list.
    private var stackedLayout: some View {
        List {
            Group { postSection }.plainRow()
            commentSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load(client: client) }
        .safeAreaInset(edge: .bottom) { actionBar }
    }

    /// iPhone Duo inner display: the post and comments side by side. ArrangementView's split
    /// style places each pane on its own side of the fold.
    private var splitLayout: some View {
        ArrangementView {
            ScrollView {
                VStack(spacing: 12) {
                    postSection
                }
                .padding(16)
            }
            .refreshable { await model.load(client: client) }
            .safeAreaInset(edge: .bottom) { actionBar }
        } secondary: {
            List {
                commentSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await model.load(client: client) }
        }
        .arrangementViewStyle(.split)
    }

    @ViewBuilder
    private var actionBar: some View {
        if let post = model.post {
            PostActionBar(post: post) {
                composer = ComposerTarget(parentName: post.name, context: post.title, parentDepth: -1, title: "Comment")
            }
        }
    }

    @ViewBuilder
    private var postSection: some View {
        if let post = model.post {
            PostDetailHeader(post: post)
        } else if model.isLoading {
            LoadingRow()
        } else if let error = model.error {
            ContentUnavailableView("Couldn't load this post",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        }
        if model.focus != nil {
            Button {
                Task { await model.showAll(client: client) }
            } label: {
                Label("Single thread · show all comments", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
    }

    @ViewBuilder
    private var commentSection: some View {
        if model.post != nil {
            commentHeader.plainRow()
        }

        ForEach(model.visibleItems) { item in
            commentRow(item)
        }
        if model.isLoading && model.post != nil && model.items.isEmpty {
            LoadingRow().plainRow()
        } else if !model.isLoading && model.post != nil && model.items.isEmpty && model.error == nil {
            Text("No comments yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .plainRow()
        }
    }

    private var commentHeader: some View {
        HStack {
            Text("Comments")
                .font(.headline)
            Spacer()
            Menu {
                Picker("Sort comments", selection: $model.sort) {
                    ForEach(CommentSort.allCases) { option in
                        Label(option.title, systemImage: option.icon).tag(option)
                    }
                }
            } label: {
                Label(model.sort.title, systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.top, 6)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func commentRow(_ item: CommentItem) -> some View {
        switch item {
        case .comment(let comment, let depth):
            CommentRow(comment: comment,
                       depth: depth,
                       isOP: comment.author != nil && comment.author == model.post?.author,
                       collapsed: model.collapsed.contains(comment.name))
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy) { model.toggleCollapse(comment.name) }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        actions.toggleVote(comment.name, original: comment.likes, direction: 1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .tint(.orange)
                    Button {
                        actions.toggleVote(comment.name, original: comment.likes, direction: -1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        reply(to: comment, depth: depth)
                    } label: {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                    }
                    .tint(theme.accent)
                    Button {
                        withAnimation(.snappy) { model.toggleCollapse(comment.name) }
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                    .tint(.gray)
                }
                .contextMenu {
                    commentMenu(comment, depth: depth)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        case .more(let more, let depth):
            MoreRow(more: more, depth: depth, loading: model.loadingMore.contains(more.name)) {
                Task {
                    if let route = await model.loadMore(more, client: client) {
                        router.push(route)
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }

    @ViewBuilder
    private func commentMenu(_ comment: Comment, depth: Int) -> some View {
        Button("Upvote", systemImage: "arrow.up") {
            actions.toggleVote(comment.name, original: comment.likes, direction: 1)
        }
        Button("Downvote", systemImage: "arrow.down") {
            actions.toggleVote(comment.name, original: comment.likes, direction: -1)
        }
        Button("Reply", systemImage: "arrowshape.turn.up.left") {
            reply(to: comment, depth: depth)
        }
        Button(actions.isSaved(comment.name, original: comment.saved) ? "Unsave" : "Save", systemImage: "bookmark") {
            actions.toggleSave(comment.name, original: comment.saved)
        }
        Button("Copy Text", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = comment.body
        }
        if let author = comment.author, author != "[deleted]" {
            Button("View u/\(author)", systemImage: "person") {
                router.push(.user(author))
            }
        }
        if let permalink = comment.permalink, let url = URL(string: "https://www.reddit.com\(permalink)") {
            ShareLink(item: url)
        }
    }

    private func reply(to comment: Comment, depth: Int) {
        composer = ComposerTarget(parentName: comment.name,
                                  context: comment.body,
                                  parentDepth: depth,
                                  title: "Reply to u/\(comment.author ?? "deleted")")
    }
}

struct PostDetailHeader: View {
    let post: Post
    @Environment(ActionStore.self) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PostMetaLine(post: post)
            Text(post.title)
                .font(.title3.weight(.bold))
            PostBadges(post: post)
            // For a link/webpage post this is a slim source row, so the comments sit right below.
            MediaBlock(post: post, isDetail: true)
            if let text = post.selftext, !text.isEmpty {
                MarkdownText(text: text)
                    .font(.body)
                    .textSelection(.enabled)
            }
            HStack(spacing: 14) {
                Label(actions.score(for: post.name, base: post.score, original: post.likes).compact, systemImage: "arrow.up")
                if let ratio = post.upvoteRatio {
                    Label("\(Int(ratio * 100))%", systemImage: "hand.thumbsup")
                }
                Label(post.numComments.compact, systemImage: "bubble.left.and.bubble.right")
                Spacer(minLength: 0)
                if post.isSelf != true, let domain = post.domain {
                    Text(domain).lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 28)
    }
}

/// The floating Liquid Glass bar at the bottom of a post.
struct PostActionBar: View {
    let post: Post
    let onReply: () -> Void
    @Environment(ActionStore.self) private var actions

    var body: some View {
        let saved = actions.isSaved(post.name, original: post.saved)
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                VoteCapsule(name: post.name, likes: post.likes, score: post.score)
                Button(action: onReply) {
                    Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                Spacer(minLength: 0)
                Button {
                    actions.toggleSave(post.name, original: post.saved)
                } label: {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark")
                        .font(.headline)
                        .foregroundStyle(saved ? Color.green : Color.primary)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                ShareLink(item: post.permalinkURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

struct VoteCapsule: View {
    let name: String
    let likes: Bool?
    let score: Int
    @Environment(ActionStore.self) private var actions

    var body: some View {
        let vote = actions.vote(for: name, original: likes)
        HStack(spacing: 2) {
            Button {
                actions.toggleVote(name, original: likes, direction: 1)
            } label: {
                Image(systemName: vote == 1 ? "arrow.up.circle.fill" : "arrow.up")
                    .frame(width: 40, height: 46)
            }
            Text(actions.score(for: name, base: score, original: likes).compact)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 30)
            Button {
                actions.toggleVote(name, original: likes, direction: -1)
            } label: {
                Image(systemName: vote == -1 ? "arrow.down.circle.fill" : "arrow.down")
                    .frame(width: 40, height: 46)
            }
        }
        .font(.headline)
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .glassEffect(glass(for: vote), in: .capsule)
        .sensoryFeedback(.selection, trigger: vote)
    }

    private func glass(for vote: Int) -> Glass {
        switch vote {
        case 1: return .regular.tint(Color.orange.opacity(0.55)).interactive()
        case -1: return .regular.tint(Color.blue.opacity(0.5)).interactive()
        default: return .regular.interactive()
        }
    }
}
