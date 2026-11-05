import SwiftUI
import UIKit

struct CommentRow: View {
    let comment: Comment
    let depth: Int
    let isOP: Bool
    let collapsed: Bool
    var selected: Bool = false
    var onReply: (() -> Void)? = nil
    var onCollapse: (() -> Void)? = nil
    var onViewUser: ((String) -> Void)? = nil
    @Environment(ActionStore.self) private var actions

    static let depthColors: [Color] = [.orange, .yellow, .green, .teal, .blue, .indigo, .purple, .pink]

    static func depthColor(_ depth: Int) -> Color {
        depthColors[(max(depth, 1) - 1) % depthColors.count]
    }

    private var isMod: Bool { comment.distinguished == "moderator" }

    private var authorColor: Color {
        if isOP { return .blue }
        if isMod { return .green }
        return .primary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if depth > 0 {
                Color.clear.frame(width: CGFloat(depth - 1) * 12)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Self.depthColor(depth))
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .padding(.trailing, 10)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(comment.author ?? "[deleted]")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(authorColor)
                        .lineLimit(1)
                    if isOP { Pill(text: "OP", color: .blue) }
                    if isMod { Pill(text: "MOD", color: .green) }
                    if comment.stickied == true {
                        Image(systemName: "pin.fill").foregroundStyle(.green)
                    }
                    scoreView
                    if let created = comment.createdUtc {
                        Text(Date(timeIntervalSince1970: created).shortAgo)
                    }
                    Spacer(minLength: 0)
                    if collapsed {
                        Image(systemName: "chevron.down.circle.fill")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                if !collapsed {
                    MarkdownText(text: comment.body ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }

                if selected && !collapsed {
                    CommentActionBar(
                        comment: comment,
                        onReply: onReply,
                        onCollapse: onCollapse,
                        onViewUser: onViewUser
                    )
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 10)
        }
        .overlay(alignment: .top) {
            if depth == 0 {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 0.5)
            }
        }
        .opacity(collapsed ? 0.75 : 1)
    }

    @ViewBuilder
    private var scoreView: some View {
        if comment.scoreHidden == true {
            Text("•")
        } else {
            let vote = actions.vote(for: comment.name, original: comment.likes)
            let score = actions.score(for: comment.name, base: comment.score ?? 0, original: comment.likes)
            HStack(spacing: 2) {
                Image(systemName: vote == -1 ? "arrow.down" : "arrow.up")
                Text(score.compact).monospacedDigit()
            }
            .foregroundStyle(PostActionsRow.color(for: vote))
        }
    }
}

/// The comment's controls, revealed inline directly beneath it when it's tapped — in the thread
/// flow, aligned to the comment, rather than in a floating box. Reads as the comment's own strip.
struct CommentActionBar: View {
    let comment: Comment
    var onReply: (() -> Void)? = nil
    var onCollapse: (() -> Void)? = nil
    var onViewUser: ((String) -> Void)? = nil
    @Environment(ActionStore.self) private var actions

    private var permalinkURL: URL? {
        comment.permalink.flatMap { URL(string: "https://www.reddit.com\($0)") }
    }

    var body: some View {
        let vote = actions.vote(for: comment.name, original: comment.likes)
        let saved = actions.isSaved(comment.name, original: comment.saved)

        HStack(spacing: 2) {
            Button {
                actions.toggleVote(comment.name, original: comment.likes, direction: 1)
            } label: {
                Image(systemName: vote == 1 ? "arrow.up.circle.fill" : "arrow.up")
                    .foregroundStyle(vote == 1 ? Color.orange : Color.secondary)
                    .frame(width: 38, height: 34).contentShape(Rectangle())
            }
            Button {
                actions.toggleVote(comment.name, original: comment.likes, direction: -1)
            } label: {
                Image(systemName: vote == -1 ? "arrow.down.circle.fill" : "arrow.down")
                    .foregroundStyle(vote == -1 ? Color.blue : Color.secondary)
                    .frame(width: 38, height: 34).contentShape(Rectangle())
            }
            Button { onReply?() } label: {
                Image(systemName: "arrowshape.turn.up.left")
                    .frame(width: 38, height: 34).contentShape(Rectangle())
            }
            Button {
                actions.toggleSave(comment.name, original: comment.saved)
            } label: {
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(saved ? Color.green : Color.secondary)
                    .frame(width: 38, height: 34).contentShape(Rectangle())
            }
            if let url = permalinkURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 38, height: 34).contentShape(Rectangle())
                }
            }
            if let author = comment.author, author != "[deleted]" {
                Button { onViewUser?(author) } label: {
                    Image(systemName: "person")
                        .frame(width: 38, height: 34).contentShape(Rectangle())
                }
            }
            Spacer(minLength: 0)
            Button { onCollapse?() } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 38, height: 34).contentShape(Rectangle())
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
        .sensoryFeedback(.selection, trigger: vote)
    }
}

struct MoreRow: View {
    let more: More
    let depth: Int
    let loading: Bool
    let action: () -> Void

    private var label: String {
        let count = more.count ?? 0
        let hasChildren = !(more.children ?? []).isEmpty
        if count > 0 && hasChildren {
            return "\(count) more \(count == 1 ? "reply" : "replies")"
        }
        return "Continue this thread"
    }

    var body: some View {
        HStack(spacing: 0) {
            if depth > 0 {
                Color.clear.frame(width: CGFloat(depth) * 12)
            }
            Button(action: action) {
                HStack(spacing: 6) {
                    if loading {
                        ProgressView().controlSize(.mini)
                    }
                    Text(label)
                }
                .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(loading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}
