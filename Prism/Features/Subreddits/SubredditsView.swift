import SwiftUI

struct SubredditsView: View {
    @Environment(RedditClient.self) private var client
    @Environment(AuthManager.self) private var auth
    @Environment(Router.self) private var router

    @State private var subreddits: [Subreddit] = []
    @State private var loading = false
    @State private var error: String?
    @State private var query = ""

    private var filtered: [Subreddit] {
        query.isEmpty ? subreddits : subreddits.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            Section {
                ForEach([FeedSource.home, .popular, .all], id: \.self) { source in
                    Button {
                        router.push(.feed(source))
                    } label: {
                        Label(source.title, systemImage: source.icon)
                            .font(.body.weight(.medium))
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Rectangle().fill(.ultraThinMaterial))

            if let name = RedditLink.subredditName(from: query) {
                Section {
                    Button {
                        router.push(.feed(.subreddit(name)))
                    } label: {
                        Label("Go to r/\(name)", systemImage: "arrow.right.circle.fill")
                    }
                }
                .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            }

            Section(auth.isLoggedIn ? "Subscribed" : "Popular Communities") {
                if loading && subreddits.isEmpty {
                    LoadingRow()
                }
                ForEach(filtered) { subreddit in
                    Button {
                        router.push(.feed(.subreddit(subreddit.displayName)))
                    } label: {
                        SubredditRow(subreddit: subreddit)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Rectangle().fill(.ultraThinMaterial))
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground())
        .navigationTitle("Subreddits")
        .searchable(text: $query, prompt: "Filter, or go to r/…")
        .onSubmit(of: .search) {
            if let name = RedditLink.subredditName(from: query) {
                router.push(.feed(.subreddit(name)))
            }
        }
        .task(id: auth.isLoggedIn) { await load() }
        .refreshable { await load() }
        .errorAlert($error, title: "Couldn't load subreddits")
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            if auth.isLoggedIn {
                subreddits = try await client.subscriptions()
            } else {
                subreddits = try await client.defaultSubreddits()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SubredditRow: View {
    let subreddit: Subreddit

    var body: some View {
        HStack(spacing: 12) {
            Avatar(url: subreddit.iconURL, size: 34, fallback: "number")
            VStack(alignment: .leading, spacing: 2) {
                Text(subreddit.prefixed)
                    .font(.body.weight(.medium))
                if let count = subreddit.subscribers {
                    Text("\(count.compact) members")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if subreddit.over18 == true {
                Pill(text: "NSFW", color: .red)
            }
        }
        .contentShape(Rectangle())
    }
}

struct SubredditView: View {
    let name: String

    var body: some View {
        FeedView(source: .subreddit(name), header: AnyView(SubredditHeader(name: name)))
    }
}

struct SubredditHeader: View {
    let name: String
    @Environment(RedditClient.self) private var client
    @Environment(AuthManager.self) private var auth
    @State private var about: Subreddit?
    @State private var subscribed = false
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let banner = about?.bannerURL {
                AsyncImage(url: banner) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.12)
                }
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 18))
            }
            HStack(spacing: 12) {
                Avatar(url: about?.iconURL, size: 52, fallback: "number")
                VStack(alignment: .leading, spacing: 2) {
                    Text(about?.prefixed ?? "r/\(name)")
                        .font(.title3.weight(.bold))
                    if let count = about?.subscribers {
                        Text("\(count.compact) members")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if auth.isLoggedIn && about != nil {
                    subscribeButton
                }
            }
            if let description = about?.publicDescription, !description.isEmpty {
                MarkdownText(text: description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 26)
        .task {
            guard about == nil else { return }
            let info = try? await client.about(name)
            if let info {
                about = info
                subscribed = info.userIsSubscriber ?? false
            }
        }
    }

    @ViewBuilder
    private var subscribeButton: some View {
        if subscribed {
            Button("Joined") { toggle() }
                .buttonStyle(.glass)
                .disabled(working)
        } else {
            Button("Join") { toggle() }
                .buttonStyle(.glassProminent)
                .disabled(working)
        }
    }

    private func toggle() {
        let next = !subscribed
        working = true
        subscribed = next
        Task {
            do {
                try await client.subscribe(about?.displayName ?? name, subscribe: next)
            } catch {
                subscribed = !next
            }
            working = false
        }
    }
}
