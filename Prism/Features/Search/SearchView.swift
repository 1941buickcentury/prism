import SwiftUI

enum SearchScope: String, CaseIterable, Identifiable {
    case posts, communities

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct SearchView: View {
    @Environment(RedditClient.self) private var client
    @Environment(Router.self) private var router

    @State private var query = ""
    @State private var submitted = ""
    @State private var scope: SearchScope = .posts
    @State private var posts: [Post] = []
    @State private var subreddits: [Subreddit] = []
    @State private var loading = false
    @State private var error: String?

    private var hasResults: Bool {
        scope == .posts ? !posts.isEmpty : !subreddits.isEmpty
    }

    var body: some View {
        List {
            if let name = RedditLink.subredditName(from: query), !query.contains(" ") {
                Button {
                    router.push(.feed(.subreddit(name)))
                } label: {
                    Label("Go to r/\(name)", systemImage: "arrow.right.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 20)
                }
                .buttonStyle(.plain)
                .plainRow()
            }

            switch scope {
            case .posts:
                ForEach(posts) { post in
                    PostCard(post: post).plainRow()
                }
            case .communities:
                ForEach(subreddits) { subreddit in
                    Button {
                        router.push(.feed(.subreddit(subreddit.displayName)))
                    } label: {
                        SubredditRow(subreddit: subreddit)
                            .padding(12)
                            .glassCard(cornerRadius: 20)
                    }
                    .buttonStyle(.plain)
                    .plainRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AmbientBackground())
        .overlay {
            if loading {
                ProgressView()
            } else if submitted.isEmpty && !hasResults {
                ContentUnavailableView("Search Reddit",
                                       systemImage: "magnifyingglass",
                                       description: Text("Find posts and communities."))
            } else if !submitted.isEmpty && !hasResults {
                ContentUnavailableView.search(text: submitted)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Search Reddit")
        .searchScopes($scope) {
            ForEach(SearchScope.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .onSubmit(of: .search) {
            Task { await search() }
        }
        .onChange(of: scope) {
            if !submitted.isEmpty {
                Task { await search() }
            }
        }
        .errorAlert($error, title: "Search failed")
    }

    private func search() async {
        let text = query.trimmed
        guard !text.isEmpty else { return }
        submitted = text
        loading = true
        defer { loading = false }
        do {
            switch scope {
            case .posts:
                posts = try await client.searchPosts(text, after: nil).items
            case .communities:
                subreddits = try await client.searchSubreddits(text)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
