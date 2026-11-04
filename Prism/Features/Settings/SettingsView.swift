import SwiftUI
import WebKit
import AuthenticationServices

// MARK: - First run

struct SetupView: View {
    @Environment(AuthManager.self) private var auth
    @State private var clientID = ""
    @State private var redirect = AuthManager.defaultRedirect

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .pink, .purple, .blue],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 104, height: 104)
                    .glassEffect(.regular, in: .circle)
                    .padding(.top, 40)

                VStack(spacing: 8) {
                    Text("Prism")
                        .font(.largeTitle.bold())
                    Text("A Liquid Glass Reddit client. Bring your own approved Reddit API client ID.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    LabeledField(label: "Client ID", placeholder: "e.g. aBcD1234efGh", text: $clientID)
                    LabeledField(label: "Redirect URI", placeholder: AuthManager.defaultRedirect, text: $redirect)
                    Text("Both come from your installed app at reddit.com/prefs/apps. The redirect URI must match exactly. A custom scheme like prism://auth uses the system login sheet; an http(s) URI uses an in-app login page.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))

                Button {
                    auth.configure(clientID: clientID, redirectURI: redirect)
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .disabled(clientID.trimmed.isEmpty)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AmbientBackground())
    }
}

struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .fontDesign(.monospaced)
                .padding(12)
                .background(.fill.tertiary, in: .rect(cornerRadius: 14))
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @AppStorage("glassCards") private var glassCards = true
    @AppStorage("compactMode") private var compact = false
    @AppStorage("blurNSFW") private var blurNSFW = true
    @AppStorage("openLinksInApp") private var openLinksInApp = true
    @AppStorage("commentSort") private var commentSort = CommentSort.confidence.rawValue

    @State private var clientID = ""
    @State private var redirect = ""

    private var apiChanged: Bool {
        clientID.trimmed != auth.clientID || redirect.trimmed != auth.redirectURI
    }

    var body: some View {
        @Bindable var theme = theme
        Form {
            Section {
                TextField("Client ID", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .fontDesign(.monospaced)
                TextField("Redirect URI", text: $redirect)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .fontDesign(.monospaced)
                Button("Save API Settings") {
                    auth.configure(clientID: clientID, redirectURI: redirect)
                }
                .disabled(!apiChanged || clientID.trimmed.isEmpty)
            } header: {
                Text("Reddit API")
            } footer: {
                Text("From your installed app at reddit.com/prefs/apps. Changing the client ID logs you out.")
            }

            Section("Account") {
                if auth.isLoggedIn {
                    LabeledContent("Logged in as", value: "u/\(auth.account?.name ?? "…")")
                    Button("Log Out", role: .destructive) {
                        auth.signOut()
                    }
                } else {
                    LoginButton()
                        .frame(maxWidth: .infinity)
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $theme.appearanceID) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Accent color")
                    HStack(spacing: 14) {
                        ForEach(AppAccent.allCases) { accent in
                            Button {
                                theme.accentID = accent.id
                            } label: {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if theme.accentID == accent.id {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .overlay {
                                        Circle().strokeBorder(.primary.opacity(theme.accentID == accent.id ? 0.5 : 0), lineWidth: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accent.title)
                        }
                    }
                }
                .padding(.vertical, 4)
                Toggle("Liquid Glass cards", isOn: $glassCards)
                Toggle("Compact layout", isOn: $compact)
                Toggle("Blur NSFW and spoilers", isOn: $blurNSFW)
            }

            Section("Behavior") {
                Picker("Default comment sort", selection: $commentSort) {
                    ForEach(CommentSort.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                Toggle("Open links inside Prism", isOn: $openLinksInApp)
            }

            Section {
                LabeledContent("Version", value: Bundle.main.appVersion)
            } header: {
                Text("About")
            } footer: {
                Text("Reddit plans to close public API access for third-party apps in March 2027. Prism will stop working then.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground())
        .navigationTitle("Settings")
        .onAppear {
            clientID = auth.clientID
            redirect = auth.redirectURI
        }
    }
}

// MARK: - Login

struct LoginButton: View {
    @Environment(AuthManager.self) private var auth
    @Environment(RedditClient.self) private var client
    @State private var webURL: IdentifiedURL?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Button {
            start()
        } label: {
            HStack(spacing: 8) {
                if working { ProgressView() }
                Text("Log in with Reddit")
                    .font(.headline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .disabled(working)
        .sheet(item: $webURL) { item in
            WebLoginSheet(url: item.url, redirectURI: auth.redirectURI) { callback in
                webURL = nil
                finish { try await auth.completeLogin(callback: callback) }
            }
        }
        .errorAlert($error, title: "Login failed")
    }

    private func start() {
        if auth.usesCustomScheme {
            finish { try await auth.loginWithSession() }
        } else {
            webURL = IdentifiedURL(url: auth.makeAuthorizeURL())
        }
    }

    private func finish(_ operation: @escaping () async throws -> Void) {
        working = true
        Task {
            do {
                try await operation()
                await client.refreshAccount()
            } catch let sessionError as ASWebAuthenticationSessionError where sessionError.code == .canceledLogin {
                // User closed the sheet; nothing to report.
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

struct WebLoginSheet: View {
    let url: URL
    let redirectURI: String
    let onCallback: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebLoginView(url: url, redirectURI: redirectURI, onCallback: onCallback)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Log in to Reddit")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

/// In-app login page for http(s) redirect URIs: watches for the redirect and hands the URL back.
struct WebLoginView: UIViewRepresentable {
    let url: URL
    let redirectURI: String
    let onCallback: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(redirectURI: redirectURI, onCallback: onCallback)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let redirectURI: String
        let onCallback: (URL) -> Void
        private var finished = false

        init(redirectURI: String, onCallback: @escaping (URL) -> Void) {
            self.redirectURI = redirectURI
            self.onCallback = onCallback
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let target = navigationAction.request.url, target.absoluteString.hasPrefix(redirectURI) {
                if !finished {
                    finished = true
                    onCallback(target)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
