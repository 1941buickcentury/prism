import SwiftUI
import UIKit

/// A bottom-docked action menu for a long-pressed comment. Replaces the native context menu,
/// which on the unfolded display throws the lifted comment to one side and the menu to the other.
/// This stays anchored to the bottom of the comments, matching the reply composer.
struct CommentActionMenu: View {
    let comment: Comment
    let isOP: Bool
    let onDismiss: () -> Void
    let onReply: () -> Void
    let onViewUser: (String) -> Void
    @Environment(ActionStore.self) private var actions

    private var permalinkURL: URL? {
        comment.permalink.flatMap { URL(string: "https://www.reddit.com\($0)") }
    }

    var body: some View {
        let vote = actions.vote(for: comment.name, original: comment.likes)
        let saved = actions.isSaved(comment.name, original: comment.saved)

        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text(comment.author ?? "[deleted]")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOP ? Color.blue : .primary)
                    if isOP { Pill(text: "OP", color: .blue) }
                    Spacer(minLength: 0)
                }
                Text(comment.body ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                Divider().padding(.vertical, 10)

                row("arrow.up", "Upvote", tint: vote == 1 ? .orange : nil) {
                    actions.toggleVote(comment.name, original: comment.likes, direction: 1); onDismiss()
                }
                row("arrow.down", "Downvote", tint: vote == -1 ? .blue : nil) {
                    actions.toggleVote(comment.name, original: comment.likes, direction: -1); onDismiss()
                }
                row("arrowshape.turn.up.left", "Reply") { onReply() }
                row(saved ? "bookmark.fill" : "bookmark", saved ? "Unsave" : "Save", tint: saved ? .green : nil) {
                    actions.toggleSave(comment.name, original: comment.saved); onDismiss()
                }
                row("doc.on.doc", "Copy Text") {
                    UIPasteboard.general.string = comment.body; onDismiss()
                }
                if let author = comment.author, author != "[deleted]" {
                    row("person", "View u/\(author)") { onViewUser(author) }
                }
                if let url = permalinkURL {
                    ShareLink(item: url) { rowLabel("square.and.arrow.up", "Share") }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: 680)
            .background(.regularMaterial, in: .rect(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.1)))
            .padding(10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func row(_ icon: String, _ label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(icon, label, tint: tint) }
            .buttonStyle(.plain)
    }

    private func rowLabel(_ icon: String, _ label: String, tint: Color? = nil) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(tint ?? .primary)
            Text(label).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .font(.body)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

struct CommentRow: View {
    let comment: Comment
    let depth: Int
    let isOP: Bool
    let collapsed: Bool
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
