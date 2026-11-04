import SwiftUI

struct InboxView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        if auth.isLoggedIn {
            InboxList()
        } else {
            LoginPromptView(title: "Your Inbox",
                            message: "Log in to see replies, mentions and messages.")
                .navigationTitle("Inbox")
        }
    }
}

struct InboxList: View {
    @Environment(RedditClient.self) private var client
    @Environment(Router.self) private var router

    @State private var box: InboxBox = .inbox
    @State private var messages: [Message] = []
    @State private var after: String?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            ForEach(messages) { message in
                MessageRow(message: message, sent: box == .sent)
                    .plainRow()
                    .onTapGesture { open(message) }
                    .onAppear {
                        if message.id == messages.last?.id, after != nil {
                            Task { await load(reset: false) }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if message.new == true {
                            Button {
                                markRead(message)
                            } label: {
                                Image(systemName: "envelope.open")
                            }
                            .tint(.accentColor)
                        }
                    }
            }
            if loading && !messages.isEmpty {
                LoadingRow().plainRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AmbientBackground())
        .overlay {
            if messages.isEmpty {
                if loading {
                    ProgressView()
                } else {
                    ContentUnavailableView("Nothing here",
                                           systemImage: "tray",
                                           description: Text(box == .unread ? "You're all caught up." : "No messages yet."))
                }
            }
        }
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mailbox", selection: $box) {
                    ForEach(InboxBox.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    markAllRead()
                } label: {
                    Label("Mark All Read", systemImage: "checkmark.circle")
                }
            }
        }
        .task(id: box) { await load(reset: true) }
        .refreshable { await load(reset: true) }
        .errorAlert($error, title: "Inbox error")
    }

    private func load(reset: Bool) async {
        if loading && !reset { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await client.inbox(box, after: reset ? nil : after)
            messages = reset ? page.items : messages + page.items
            after = page.after
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func open(_ message: Message) {
        if message.new == true { markRead(message) }
        if message.wasComment == true,
           let context = message.context,
           let url = URL(string: "https://www.reddit.com\(context)"),
           let route = RedditLink.route(for: url) {
            router.push(route)
        } else {
            router.push(.message(message))
        }
    }

    private func markRead(_ message: Message) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index].new = false
        }
        Task {
            try? await client.markRead([message.name])
            await client.refreshAccount()
        }
    }

    private func markAllRead() {
        for index in messages.indices { messages[index].new = false }
        Task {
            try? await client.markAllRead()
            await client.refreshAccount()
        }
    }
}

struct MessageRow: View {
    let message: Message
    let sent: Bool

    private var unread: Bool { message.new == true }

    private var headline: String {
        if message.wasComment == true {
            return message.linkTitle ?? message.subject ?? "Comment reply"
        }
        return message.subject ?? "Message"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.wasComment == true ? "bubble.left.and.bubble.right.fill" : "envelope.fill")
                .font(.title3)
                .foregroundStyle(unread ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(headline)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let created = message.createdUtc {
                        Text(Date(timeIntervalSince1970: created).shortAgo)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(sent ? "to u/\(message.dest ?? "")" : "from u/\(message.author ?? "reddit")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(message.body ?? "")
                    .font(.subheadline)
                    .lineLimit(3)
            }
            if unread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
        .contentShape(.rect(cornerRadius: 22))
    }
}

struct MessageDetailView: View {
    let message: Message
    @State private var composer: ComposerTarget?
    @State private var sent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(message.subject ?? "Message")
                    .font(.title3.weight(.bold))
                HStack {
                    Text("u/\(message.author ?? "reddit")")
                    if let created = message.createdUtc {
                        Text("•")
                        Text(Date(timeIntervalSince1970: created).shortAgo)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                MarkdownText(text: message.body ?? "")
                    .font(.body)
                    .textSelection(.enabled)
                if sent {
                    Label("Reply sent", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.top, 6)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 26)
            .padding()
        }
        .background(AmbientBackground())
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    composer = ComposerTarget(parentName: message.name,
                                              context: message.body,
                                              parentDepth: 0,
                                              title: "Reply")
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
            }
        }
        .sheet(item: $composer) { target in
            ComposerView(target: target) { _ in sent = true }
        }
    }
}
