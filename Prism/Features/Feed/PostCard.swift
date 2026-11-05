import SwiftUI

struct PostCard: View {
    let post: Post
    var onSelect: ((Post) -> Void)? = nil
    var isSelected: Bool = false
    @Environment(Router.self) private var router
    @AppStorage("compactMode") private var compact = true

    private var radius: CGFloat { compact ? 16 : 26 }

    private func open() {
        if let onSelect { onSelect(post) } else { router.push(.post(post)) }
    }

    var body: some View {
        Group {
            if compact { CompactPostRow(post: post, onOpen: open) }
            else { LargePostCard(post: post) }
        }
        .padding(compact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: radius)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(.tint, lineWidth: 2)
            }
        }
        .contentShape(.rect(cornerRadius: radius))
        .onTapGesture { open() }
    }
}

/// The roomy card: full-width media, used when Compact layout is off.
struct LargePostCard: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PostMetaLine(post: post)
            Text(post.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            PostBadges(post: post)
            MediaBlock(post: post, isDetail: false, interactiveLinks: false)
            if post.isSelf == true, let text = post.selftext, !text.isEmpty {
                MarkdownText(text: text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            PostActionsRow(post: post)
        }
    }
}

/// The dense row: title and meta beside a small thumbnail, in the spirit of Apollo/Boost/Sync
/// compact modes. Tapping an image or video opens the viewer; everything else opens the comments.
struct CompactPostRow: View {
    let post: Post
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 5) {
                CompactMetaLine(post: post)
                Text(post.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                PostBadges(post: post)
                PostActionsRow(post: post, compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CompactThumbnail(post: post, onOpenPost: onOpen)
        }
    }
}

struct CompactMetaLine: View {
    let post: Post
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 4) {
            Button { router.push(.feed(.subreddit(post.subreddit))) } label: {
                Text(post.subredditPrefixed).fontWeight(.semibold).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Text("• \(post.created.shortAgo)")
            if post.stickied == true { Image(systemName: "pin.fill").foregroundStyle(.green) }
            if post.locked == true { Image(systemName: "lock.fill").foregroundStyle(.yellow) }
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// Small square preview for the compact row. Images and video open the viewer; link and
/// text posts fall through to the row's tap, which opens the comments.
struct CompactThumbnail: View {
    let post: Post
    let onOpenPost: () -> Void

    @Environment(Router.self) private var router
    @AppStorage("blurNSFW") private var blurNSFW = true

    private var media: PostMedia { post.resolvedMedia }
    private var hidden: Bool { blurNSFW && (post.over18 == true || post.spoiler == true) }
    private let side: CGFloat = 78

    var body: some View {
        switch media {
        case .images(let images):
            thumb(url: post.previewURL ?? images.first?.url, glyph: images.count > 1 ? "square.stack.fill" : nil)
                .onTapGesture { openViewer() }
        case .video:
            thumb(url: post.previewURL, glyph: "play.fill")
                .onTapGesture { openViewer() }
        case .link:
            thumb(url: post.thumbnailURL, glyph: "link", corner: "arrow.up.right")
                .onTapGesture { onOpenPost() }
        case .none:
            EmptyView()
        }
    }

    private func openViewer() {
        if hidden { onOpenPost() } else { router.media = MediaPresentation(media: media, title: post.title) }
    }

    @ViewBuilder
    private func thumb(url: URL?, glyph: String?, corner: String? = nil) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.secondary.opacity(0.12))
            .frame(width: side, height: side)
            .overlay {
                if let url, !hidden {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                } else if url == nil {
                    Image(systemName: "link").font(.title3).foregroundStyle(.secondary)
                }
            }
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                if hidden {
                    Image(systemName: "eye.slash.fill").foregroundStyle(.white)
                } else if let glyph, glyph != "link" {
                    Image(systemName: glyph)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.4), in: .circle)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let corner, !hidden {
                    Image(systemName: corner)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.45), in: .circle)
                        .padding(4)
                }
            }
            .blur(radius: hidden ? 18 : 0)
            .contentShape(.rect(cornerRadius: 12))
    }
}

struct PostMetaLine: View {
    let post: Post
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 4) {
            Button {
                router.push(.feed(.subreddit(post.subreddit)))
            } label: {
                Text(post.subredditPrefixed)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            Text("•")
            Button {
                router.push(.user(post.author))
            } label: {
                Text("u/\(post.author)").lineLimit(1)
            }
            .buttonStyle(.plain)
            Text("•")
            Text(post.created.shortAgo)
            Spacer(minLength: 0)
            if post.stickied == true {
                Image(systemName: "pin.fill").foregroundStyle(.green)
            }
            if post.locked == true {
                Image(systemName: "lock.fill").foregroundStyle(.yellow)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct PostBadges: View {
    let post: Post
    @Environment(ThemeManager.self) private var theme

    private var flair: String? {
        guard let text = post.linkFlairText?.trimmed, !text.isEmpty else { return nil }
        return text
    }

    var body: some View {
        if post.over18 == true || post.spoiler == true || flair != nil {
            HStack(spacing: 6) {
                if post.over18 == true { Pill(text: "NSFW", color: .red) }
                if post.spoiler == true { Pill(text: "Spoiler", color: .gray) }
                if let flair { Pill(text: flair, color: theme.accent) }
            }
        }
    }
}

struct PostActionsRow: View {
    let post: Post
    var compact: Bool = false
    @Environment(ActionStore.self) private var actions

    var body: some View {
        let vote = actions.vote(for: post.name, original: post.likes)
        let saved = actions.isSaved(post.name, original: post.saved)
        let score = actions.score(for: post.name, base: post.score, original: post.likes)

        HStack(spacing: compact ? 14 : 18) {
            HStack(spacing: compact ? 6 : 8) {
                Button {
                    actions.toggleVote(post.name, original: post.likes, direction: 1)
                } label: {
                    Image(systemName: vote == 1 ? "arrow.up.circle.fill" : "arrow.up")
                        .foregroundStyle(vote == 1 ? Color.orange : Color.secondary)
                        .contentShape(Rectangle())
                }
                Text(score.compact)
                    .monospacedDigit()
                    .foregroundStyle(Self.color(for: vote))
                Button {
                    actions.toggleVote(post.name, original: post.likes, direction: -1)
                } label: {
                    Image(systemName: vote == -1 ? "arrow.down.circle.fill" : "arrow.down")
                        .foregroundStyle(vote == -1 ? Color.blue : Color.secondary)
                        .contentShape(Rectangle())
                }
            }
            Label(post.numComments.compact, systemImage: "bubble.left")
            Spacer(minLength: 0)
            Button {
                actions.toggleSave(post.name, original: post.saved)
            } label: {
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(saved ? Color.green : Color.secondary)
                    .contentShape(Rectangle())
            }
            if !compact {
                ShareLink(item: post.permalinkURL) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: vote)
    }

    static func color(for vote: Int) -> Color {
        switch vote {
        case 1: return .orange
        case -1: return .blue
        default: return .secondary
        }
    }
}

/// Image, gallery, video or link preview for a post. Tapping an image or video opens the
/// full-screen viewer. In the feed, link previews are non-interactive so the card tap opens
/// the comments; in the post detail they're buttons that open the link.
struct MediaBlock: View {
    let post: Post
    let isDetail: Bool
    var interactiveLinks: Bool = true

    @Environment(Router.self) private var router
    @AppStorage("blurNSFW") private var blurNSFW = true
    @State private var revealed = false

    private var media: PostMedia { post.resolvedMedia }

    private var hidden: Bool {
        blurNSFW && !revealed && (post.over18 == true || post.spoiler == true)
    }

    var body: some View {
        switch media {
        case .images(let images):
            preview(url: post.previewURL ?? images.first?.url)
                .overlay(alignment: .topTrailing) {
                    if images.count > 1 && !hidden {
                        Label("\(images.count)", systemImage: "square.stack.fill")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: .capsule)
                            .padding(10)
                    }
                }
                .onTapGesture { open() }
        case .video:
            preview(url: post.previewURL)
                .overlay {
                    if !hidden {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .frame(width: 58, height: 58)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                }
                .onTapGesture { open() }
        case .link(let url):
            LinkCard(url: url, thumbnail: post.thumbnailURL, hidden: hidden, interactive: interactiveLinks)
        case .none:
            EmptyView()
        }
    }

    private func open() {
        if hidden {
            withAnimation(.easeOut) { revealed = true }
        } else {
            router.media = MediaPresentation(media: media, title: post.title)
        }
    }

    @ViewBuilder
    private func preview(url: URL?) -> some View {
        let aspect = isDetail ? max(post.previewAspect, 0.56) : min(max(post.previewAspect, 0.8), 2.2)
        Color.secondary.opacity(0.12)
            .aspectRatio(CGFloat(aspect), contentMode: .fit)
            .overlay {
                if let url {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else if phase.error != nil {
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
                }
            }
            .blur(radius: hidden ? 40 : 0)
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                if hidden {
                    Label(post.over18 == true ? "NSFW" : "Spoiler", systemImage: "eye.slash.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassEffect(.regular, in: .capsule)
                }
            }
            .contentShape(.rect(cornerRadius: 18))
    }
}

struct LinkCard: View {
    let url: URL
    let thumbnail: URL?
    var hidden = false
    var interactive: Bool = true

    @Environment(\.openURL) private var openURL

    var body: some View {
        if interactive {
            Button { openURL(url) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail, !hidden {
                    AsyncImage(url: thumbnail) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.15)
                    }
                } else {
                    Image(systemName: "link")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.12))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(url.host() ?? url.absoluteString)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: interactive ? "arrow.up.right" : "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
    }
}
