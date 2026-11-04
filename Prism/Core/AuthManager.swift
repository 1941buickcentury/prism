import Foundation
import Security
import UIKit
import AuthenticationServices
import Observation

enum RedditError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case auth(String)
    case decoding(String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your Reddit client ID in Settings first."
        case .http(let code, _):
            switch code {
            case 401: return "Reddit rejected the login (401). Check your client ID."
            case 403: return "Reddit refused access (403). The content may be private, or the API key may have lost access."
            case 404: return "Not found."
            case 429: return "Reddit's rate limit was hit. Wait a minute and try again."
            default: return "Reddit returned an error (\(code))."
            }
        case .auth(let message): return message
        case .decoding(let message): return "Couldn't read Reddit's response. \(message)"
        case .api(let message): return message
        }
    }
}

enum Keychain {
    private static let service = "com.shotatredline.prism"

    static func save(_ value: String, for key: String) {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum FormEncoder {
    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ form: [String: String]) -> Data {
        let body = form.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}

final class AuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}

/// Holds the Reddit client ID, the user's refresh token and the current access token.
/// Logged out, it uses Reddit's app-only "installed client" grant so browsing still works.
@Observable
@MainActor
final class AuthManager {
    private(set) var clientID: String
    private(set) var redirectURI: String
    private(set) var refreshToken: String?
    var account: Account?

    var isConfigured: Bool { !clientID.isEmpty }
    var isLoggedIn: Bool { refreshToken != nil }

    var usesCustomScheme: Bool {
        let scheme = URL(string: redirectURI)?.scheme?.lowercased() ?? ""
        return !scheme.isEmpty && scheme != "http" && scheme != "https"
    }

    var userAgent: String {
        "ios:com.shotatredline.prism:v1.0 (by /u/\(account?.name ?? "prism_app"))"
    }

    static let scopes = "identity read vote save submit history mysubreddits privatemessages subscribe edit report"
    static let defaultRedirect = "prism://auth"

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var expiry: Date = .distantPast
    @ObservationIgnored private var tokenTask: Task<String, Error>?
    @ObservationIgnored private var pendingState: String?
    @ObservationIgnored private var presenter: AuthPresenter?
    @ObservationIgnored private var session: ASWebAuthenticationSession?

    init() {
        let defaults = UserDefaults.standard
        clientID = defaults.string(forKey: "clientID") ?? ""
        redirectURI = defaults.string(forKey: "redirectURI") ?? AuthManager.defaultRedirect
        refreshToken = Keychain.read("refreshToken")
    }

    func configure(clientID newID: String, redirectURI newRedirect: String) {
        let id = newID.trimmingCharacters(in: .whitespacesAndNewlines)
        let redirect = newRedirect.trimmingCharacters(in: .whitespacesAndNewlines)
        if id != clientID { signOut() }
        clientID = id
        redirectURI = redirect.isEmpty ? AuthManager.defaultRedirect : redirect
        UserDefaults.standard.set(clientID, forKey: "clientID")
        UserDefaults.standard.set(redirectURI, forKey: "redirectURI")
        invalidateAccessToken()
    }

    func invalidateAccessToken() {
        accessToken = nil
        expiry = .distantPast
    }

    func signOut() {
        refreshToken = nil
        Keychain.delete("refreshToken")
        account = nil
        invalidateAccessToken()
    }

    // MARK: Tokens

    func validAccessToken() async throws -> String {
        if let token = accessToken, expiry > Date().addingTimeInterval(60) { return token }
        if let task = tokenTask { return try await task.value }
        let task = Task { try await self.fetchToken() }
        tokenTask = task
        defer { tokenTask = nil }
        return try await task.value
    }

    private func fetchToken() async throws -> String {
        guard isConfigured else { throw RedditError.notConfigured }
        if let refresh = refreshToken {
            do {
                return try await requestToken(["grant_type": "refresh_token", "refresh_token": refresh])
            } catch RedditError.http(let code, _) where code == 400 || code == 401 {
                signOut()
            } catch RedditError.auth(_) {
                signOut()
            }
        }
        return try await requestToken([
            "grant_type": "https://oauth.reddit.com/grants/installed_client",
            "device_id": "DO_NOT_TRACK_THIS_DEVICE"
        ])
    }

    private func requestToken(_ form: [String: String]) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.reddit.com/api/v1/access_token")!)
        request.httpMethod = "POST"
        let credentials = Data("\(clientID):".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoder.encode(form)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw RedditError.http(code, String(decoding: data, as: UTF8.self))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let token = try decoder.decode(TokenResponse.self, from: data)
        if let error = token.error { throw RedditError.auth("Reddit login error: \(error)") }
        guard let access = token.accessToken else { throw RedditError.auth("Reddit didn't return an access token.") }

        accessToken = access
        expiry = Date().addingTimeInterval(TimeInterval(token.expiresIn ?? 3600))
        if let refresh = token.refreshToken {
            refreshToken = refresh
            Keychain.save(refresh, for: "refreshToken")
        }
        return access
    }

    // MARK: Login

    func makeAuthorizeURL() -> URL {
        let state = UUID().uuidString
        pendingState = state
        var components = URLComponents(string: "https://www.reddit.com/api/v1/authorize.compact")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "duration", value: "permanent"),
            URLQueryItem(name: "scope", value: AuthManager.scopes)
        ]
        return components.url!
    }

    /// Login through the system sheet. Used when the redirect URI is a custom scheme like prism://auth.
    func loginWithSession() async throws {
        guard let scheme = URL(string: redirectURI)?.scheme else {
            throw RedditError.auth("The redirect URI isn't valid.")
        }
        let url = makeAuthorizeURL()
        let presenter = AuthPresenter(anchor: AuthManager.currentAnchor())
        self.presenter = presenter

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? RedditError.auth("Login was cancelled."))
                }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: RedditError.auth("Couldn't open the Reddit login page."))
            }
        }
        session = nil
        try await completeLogin(callback: callback)
    }

    /// Finishes a login from the redirect URL Reddit sent back.
    func completeLogin(callback: URL) async throws {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value: (String) -> String? = { name in items.first(where: { $0.name == name })?.value }

        if let error = value("error") {
            throw RedditError.auth(error == "access_denied" ? "You declined access on Reddit." : "Reddit login error: \(error)")
        }
        guard let code = value("code") else {
            throw RedditError.auth("Reddit's redirect didn't include a login code.")
        }
        if let expected = pendingState, value("state") != expected {
            throw RedditError.auth("Login check failed. Please try again.")
        }
        pendingState = nil
        invalidateAccessToken()
        _ = try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI
        ])
    }

    private static func currentAnchor() -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
        if let window = scenes.first?.windows.first { return window }
        guard let scene = scenes.first else {
            preconditionFailure("Login needs an active window scene.")
        }
        return UIWindow(windowScene: scene)
    }
}
