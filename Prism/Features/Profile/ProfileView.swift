import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        Group {
            if let name = auth.account?.name {
                UserView(name: name, isSelf: true)
            } else if auth.isLoggedIn {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AmbientBackground())
            } else {
                LoginPromptView(title: "Your Profile",
                                message: "Log in to see your posts, comments, saved items and upvotes.")
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }
}

enum UserSection: String, CaseIterable, Identifiable {
    case overview, submitted, comments, saved, upvoted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "All"
        case .submitted: return "Posts"
        case .comments: return "Comments"
        case .saved: return "Saved"
        case .upvoted: return "Upvoted"
        }
    }

    static func available(isSelf: Bool) -> [UserSection] {
        isSelf ? allCases : [.overview, .submitted, .comments]
    }
}

struct UserView: View {
    let name: String
    let isSelf: Bool

    @Environment(RedditClient.self) private var client
    @State private var account: Account?
    @State private var section: UserSection = .overview
    @State private var things: [Thing] = []
    @State private var after: String?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            Group {
                UserHeader(name: name, account: account)
                Picker("Section", selection: $section) {
                    ForEach(UserSection.available(isSelf: isSelf)) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
            .plainRow()

            ForEach(things, id: \.rowID) { thing in
                row(for: thing)
                    .plainRow()
                    .onAppear {
                        if thing.rowID == things.last?.rowID, after != nil {
                            Task { await load(reset: false) }
                        }
                    }
            }

            if loading {
                LoadingRow().plainRow()
            } else if things.isEmpty {
                Text(error ?? "Nothing here yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .plainRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AmbientBackground())
        .navigationTitle(isSelf ? "Profile" : "u/\(name)")
        .navigationBarTitleDisplayMode(isSelf ? .large : .inline)
        .task {
            if account == nil {
                account = try? await client.user(name)
            }
        }
        .task(id: section) { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    @ViewBuilder
    private func row(for thing: Thing) -> some View {
        switch thing {
        case .post(let post):
            PostCard(post: post)
        case .comment(let comment):
            UserCommentCard(comment: comment)
        default:
            EmptyView()
        }
    }

    private func load(reset: Bool) async {
        if loading && !reset { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await client.userListing(name, section: section.rawValue, after: reset ? nil : after)
            let fresh = page.items.filter { !$0.isOther }
            if reset {
                things = fresh
            } else {
                let existing = Set(things.map(\.rowID))
                things += fresh.filter { !existing.contains($0.rowID) }
            }
            after = page.after
            error = nil
        } catch {
            if reset { things = [] }
            self.error = error.localizedDescription
        }
    }
}

struct UserHeader: View {
    let name: String
    let account: Account?

    var body: some View {
        HStack(spacing: 14) {
            Avatar(url: account?.avatarURL, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("u/\(name)")
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                if let account {
                    HStack(spacing: 12) {
                        Label((account.linkKarma ?? 0).compact, systemImage: "doc.text")
                        Label((account.commentKarma ?? 0).compact, systemImage: "bubble.left")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let created = account.createdUtc {
                        Label("Joined \(Date(timeIntervalSince1970: created).formatted(date: .abbreviated, time: .omitted))",
                              systemImage: "birthday.cake")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(cornerRadius: 26)
    }
}

struct UserCommentCard: View {
    let comment: Comment
    @Environment(Router.self) private var router
    @Environment(ActionStore.self) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = comment.linkTitle {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
            }
            HStack(spacing: 4) {
                Text("r/\(comment.subreddit ?? "")")
                Text("•")
                Text(actions.score(for: comment.name, base: comment.score ?? 0, original: comment.likes).compact)
                Text("points")
                if let created = comment.createdUtc {
                    Text("•")
                    Text(Date(timeIntervalSince1970: created).shortAgo)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            MarkdownText(text: comment.body ?? "")
                .font(.subheadline)
                .lineLimit(6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
        .contentShape(.rect(cornerRadius: 22))
        .onTapGesture {
            if let link = comment.linkId, link.hasPrefix("t3_") {
                router.push(.postID(String(link.dropFirst(3)), focus: comment.id))
            }
        }
    }
}
