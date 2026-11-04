import SwiftUI
import Observation

@Observable
@MainActor
final class FeedViewModel {
    let source: FeedSource
    var posts: [Post] = []
    var sort: FeedSort
    var time: TopTime = .day
    var isLoading = false
    var error: String?

    @ObservationIgnored private var after: String?
    @ObservationIgnored private var reachedEnd = false
    @ObservationIgnored private var seen = Set<String>()
    @ObservationIgnored private var generation = 0

    init(source: FeedSource, sort: FeedSort) {
        self.source = source
        self.sort = sort
    }

    func load(client: RedditClient, reset: Bool) async {
        if reset {
            generation += 1
        } else if isLoading || reachedEnd {
            return
        }
        let current = generation
        isLoading = true
        do {
            let page = try await client.feed(source, sort: sort, time: time, after: reset ? nil : after)
            guard current == generation else { return }
            if reset {
                posts = []
                seen = []
            }
            let fresh = page.items.filter { seen.insert($0.name).inserted }
            posts += fresh
            after = page.after
            reachedEnd = page.after == nil
            error = nil
        } catch {
            guard current == generation else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct FeedView: View {
    let source: FeedSource
    private let header: AnyView?

    @State private var model: FeedViewModel
    @Environment(RedditClient.self) private var client
    @Environment(ActionStore.self) private var actions
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(Router.self) private var router
    private let onSelect: ((Post) -> Void)?
    private let selectedName: String?

    init(source: FeedSource,
         initialSort: FeedSort? = nil,
         header: AnyView? = nil,
         onSelect: ((Post) -> Void)? = nil,
         selectedName: String? = nil) {
        self.source = source
        self.header = header
        self.onSelect = onSelect
        self.selectedName = selectedName
        let sort = initialSort ?? (source == .home ? .best : .hot)
        _model = State(initialValue: FeedViewModel(source: source, sort: sort))
    }

    var body: some View {
        Group {
            if onSelect != nil {
                listFeed
            } else if hSize == .regular {
                gridFeed
            } else {
                listFeed
            }
        }
        .background(AmbientBackground())
        .overlay {
            if model.posts.isEmpty {
                if model.isLoading {
                    ProgressView()
                } else if let error = model.error {
                    ContentUnavailableView {
                        Label("Couldn't load posts", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") {
                            Task { await model.load(client: client, reset: true) }
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
        }
        .refreshable {
            await model.load(client: client, reset: true)
        }
        .task {
            if model.posts.isEmpty {
                await model.load(client: client, reset: true)
                openScreenshotScreenIfRequested()
            }
        }
        .onChange(of: model.sort) {
            Task { await model.load(client: client, reset: true) }
        }
        .onChange(of: model.time) {
            Task { await model.load(client: client, reset: true) }
        }
        .navigationTitle(source.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SortMenu(sort: $model.sort, time: $model.time, includeBest: source == .home)
            }
        }
    }

    /// iPhone Duo inner display (regular width): two columns of cards. The gap between
    /// columns lines up with the middle of the screen, so cards don't sit across the fold.
    private var gridFeed: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let header {
                    header
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 36), GridItem(.flexible())],
                          alignment: .center,
                          spacing: 14) {
                    ForEach(model.posts) { post in
                        PostCard(post: post)
                            .contextMenu { postMenu(post) }
                            .onAppear { loadMoreIfLast(post) }
                    }
                }
                if model.isLoading && !model.posts.isEmpty {
                    LoadingRow()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func postMenu(_ post: Post) -> some View {
        Button("Upvote", systemImage: "arrow.up") {
            actions.toggleVote(post.name, original: post.likes, direction: 1)
        }
        Button("Downvote", systemImage: "arrow.down") {
            actions.toggleVote(post.name, original: post.likes, direction: -1)
        }
        Button(actions.isSaved(post.name, original: post.saved) ? "Unsave" : "Save", systemImage: "bookmark") {
            actions.toggleSave(post.name, original: post.saved)
        }
        ShareLink(item: post.permalinkURL)
    }

    /// Used by the cloud screenshot job: launching with `-prismScreen post|media|subreddit`
    /// opens that screen once the Home feed has loaded. Normal launches never set it.
    private func openScreenshotScreenIfRequested() {
        guard source == .home,
              let screen = UserDefaults.standard.string(forKey: "prismScreen"),
              !model.posts.isEmpty else { return }
        let candidates = model.posts.filter { $0.stickied != true && $0.over18 != true && $0.spoiler != true }
        switch screen {
        case "post":
            let post = candidates.first { $0.resolvedMedia.isVisual && $0.numComments > 20 } ?? candidates.first
            if let post { router.push(.post(post)) }
        case "media":
            let post = candidates.first {
                if case .images = $0.resolvedMedia { return true }
                return false
            }
            if let post {
                router.media = MediaPresentation(media: post.resolvedMedia, title: post.title)
            }
        case "subreddit":
            router.push(.feed(.subreddit("pics")))
        default:
            break
        }
    }

    private func loadMoreIfLast(_ post: Post) {
        if post.id == model.posts.last?.id {
            Task { await model.load(client: client, reset: false) }
        }
    }

    private var listFeed: some View {
        List {
            if let header {
                header.plainRow()
            }
            ForEach(model.posts) { post in
                PostCard(post: post,
                         onSelect: onSelect,
                         isSelected: onSelect != nil && post.name == selectedName)
                    .plainRow()
                    .onAppear { loadMoreIfLast(post) }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            actions.toggleVote(post.name, original: post.likes, direction: 1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .tint(.orange)
                        Button {
                            actions.toggleVote(post.name, original: post.likes, direction: -1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            actions.toggleSave(post.name, original: post.saved)
                        } label: {
                            Image(systemName: "bookmark")
                        }
                        .tint(.green)
                    }
            }
            if model.isLoading && !model.posts.isEmpty {
                LoadingRow().plainRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

struct SortMenu: View {
    @Binding var sort: FeedSort
    @Binding var time: TopTime
    let includeBest: Bool

    var body: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(FeedSort.allCases.filter { includeBest || $0 != .best }) { option in
                    Label(option.title, systemImage: option.icon).tag(option)
                }
            }
            if sort.usesTime {
                Picker("Time", selection: $time) {
                    ForEach(TopTime.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: sort.icon)
        }
    }
}

/// Home tab: the front page with floating glass chips for Home, Popular and All.
struct HomeView: View {
    @Environment(AuthManager.self) private var auth
    @State private var source: FeedSource = .home
    @Namespace private var chips

    private let sources: [FeedSource] = [.home, .popular, .all]

    var body: some View {
        FeedView(source: source, initialSort: source == .home && auth.isLoggedIn ? .best : .hot)
            .id([source.key, String(auth.isLoggedIn)])
            .safeAreaInset(edge: .top) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(sources, id: \.self) { option in
                            Button {
                                withAnimation(.bouncy) { source = option }
                            } label: {
                                Label(option.title, systemImage: option.icon)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(
                                source == option
                                    ? .regular.tint(Color.accentColor.opacity(0.55)).interactive()
                                    : .regular.interactive(),
                                in: .capsule
                            )
                            .glassEffectID(option.key, in: chips)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
    }
}
