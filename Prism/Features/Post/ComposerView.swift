import SwiftUI

struct ComposerView: View {
    let target: ComposerTarget
    let onPosted: (Thing) -> Void

    @Environment(RedditClient.self) private var client
    @Environment(ActionStore.self) private var actions
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let context = target.context, !context.isEmpty {
                    Text(context)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }
                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(maxHeight: .infinity)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                Text("Markdown works: **bold**, *italic*, [links](https://example.com)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(AmbientBackground())
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        send()
                    } label: {
                        if sending {
                            ProgressView()
                        } else {
                            Text("Post").bold()
                        }
                    }
                    .disabled(text.trimmed.isEmpty || sending)
                }
            }
            .errorAlert($error, title: "Couldn't post")
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(!text.trimmed.isEmpty)
    }

    private func send() {
        guard client.auth.isLoggedIn else {
            dismiss()
            actions.needsLogin = true
            return
        }
        sending = true
        Task {
            do {
                let thing = try await client.reply(to: target.parentName, text: text)
                if let thing {
                    onPosted(thing)
                }
                sending = false
                dismiss()
            } catch {
                sending = false
                self.error = error.localizedDescription
            }
        }
    }
}
