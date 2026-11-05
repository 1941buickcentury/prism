import SwiftUI

/// A bottom-docked reply composer: the parent comment condensed into a tappable quote,
/// a growing editor that rides the keyboard, and a one-tap Markdown formatting row.
/// Docks to the bottom on both the outer phone and the unfolded inner display.
struct ComposerOverlay: View {
    let target: ComposerTarget
    let onDismiss: () -> Void
    let onPosted: (Thing) -> Void

    @Environment(RedditClient.self) private var client
    @Environment(ActionStore.self) private var actions
    @State private var text = ""
    @State private var selection: TextSelection?
    @State private var sending = false
    @State private var error: String?
    @State private var quoteExpanded = false
    @FocusState private var focused: Bool

    private var canPost: Bool { !text.trimmed.isEmpty && !sending }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { if text.trimmed.isEmpty { onDismiss() } }

            VStack(spacing: 12) {
                header
                if let context = target.context, !context.isEmpty {
                    quote(context)
                }
                TextEditor(text: $text, selection: $selection)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96, maxHeight: 220)
                    .padding(8)
                    .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 16))
                formatBar
            }
            .padding(14)
            .frame(maxWidth: 680)
            .background(.regularMaterial, in: .rect(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.1)))
            .padding(10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .errorAlert($error, title: "Couldn't post")
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack {
            Button("Cancel", action: onDismiss)
                .foregroundStyle(.secondary)
            Spacer()
            Text(target.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Button(action: send) {
                if sending { ProgressView() }
                else { Text("Post").fontWeight(.bold) }
            }
            .disabled(!canPost)
        }
    }

    private func quote(_ context: String) -> some View {
        Button {
            withAnimation(.snappy) { quoteExpanded.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "text.quote")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text(context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(quoteExpanded ? 10 : 1)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: quoteExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var formatBar: some View {
        HStack(spacing: 4) {
            fmt("bold", wrap: "**")
            fmt("italic", wrap: "*")
            fmt("strikethrough", wrap: "~~")
            fmt("link", prefix: "[", suffix: "](https://)", placeholder: "label")
            Divider().frame(height: 20)
            fmt("text.quote", line: "> ")
            fmt("list.bullet", line: "- ")
            Spacer(minLength: 0)
        }
        .font(.system(size: 18))
        .foregroundStyle(.tint)
    }

    private func fmt(_ icon: String, wrap: String) -> some View {
        fmt(icon, prefix: wrap, suffix: wrap, placeholder: icon)
    }

    private func fmt(_ icon: String, prefix: String, suffix: String, placeholder: String) -> some View {
        Button {
            apply(prefix: prefix, suffix: suffix, placeholder: placeholder)
        } label: {
            Image(systemName: icon).frame(width: 36, height: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fmt(_ icon: String, line: String) -> some View {
        Button {
            insertLine(line)
        } label: {
            Image(systemName: icon).frame(width: 36, height: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Markdown insertion

    private func apply(prefix: String, suffix: String, placeholder: String) {
        if let sel = selection, case let .selection(range) = sel.indices, !range.isEmpty,
           range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex {
            let chosen = String(text[range])
            text.replaceSubrange(range, with: prefix + chosen + suffix)
        } else {
            if !text.isEmpty && !text.hasSuffix(" ") && !text.hasSuffix("\n") { text += " " }
            text += prefix + placeholder + suffix
        }
        selection = nil
    }

    private func insertLine(_ marker: String) {
        text += (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + marker
        selection = nil
    }

    private func send() {
        guard client.auth.isLoggedIn else {
            onDismiss()
            actions.needsLogin = true
            return
        }
        sending = true
        Task {
            do {
                let thing = try await client.reply(to: target.parentName, text: text)
                if let thing { onPosted(thing) }
                sending = false
                onDismiss()
            } catch {
                sending = false
                self.error = error.localizedDescription
            }
        }
    }
}

extension View {
    /// Presents the bottom-docked composer over this view when `target` is set.
    func composer(_ target: Binding<ComposerTarget?>, onPosted: @escaping (Thing, ComposerTarget) -> Void) -> some View {
        overlay {
            if let current = target.wrappedValue {
                ComposerOverlay(
                    target: current,
                    onDismiss: { target.wrappedValue = nil },
                    onPosted: { thing in onPosted(thing, current) }
                )
            }
        }
        .animation(.spring(duration: 0.3), value: target.wrappedValue?.id)
    }
}
