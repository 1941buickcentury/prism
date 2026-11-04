import Foundation
import Observation

extension Optional where Wrapped == Bool {
    /// Reddit's `likes`: true = upvoted, false = downvoted, nil = no vote.
    var voteValue: Int {
        switch self {
        case .some(true): return 1
        case .some(false): return -1
        case .none: return 0
        }
    }
}

/// Keeps votes and saves in sync across every screen that shows the same post or comment.
@Observable
@MainActor
final class ActionStore {
    let client: RedditClient
    var votes: [String: Int] = [:]
    var saves: [String: Bool] = [:]
    var needsLogin = false

    init(client: RedditClient) {
        self.client = client
    }

    func vote(for name: String, original: Bool?) -> Int {
        votes[name] ?? original.voteValue
    }

    func score(for name: String, base: Int, original: Bool?) -> Int {
        base - original.voteValue + vote(for: name, original: original)
    }

    func isSaved(_ name: String, original: Bool?) -> Bool {
        saves[name] ?? (original ?? false)
    }

    func toggleVote(_ name: String, original: Bool?, direction: Int) {
        guard client.auth.isLoggedIn else {
            needsLogin = true
            return
        }
        let current = vote(for: name, original: original)
        let next = current == direction ? 0 : direction
        votes[name] = next
        Task {
            do {
                try await client.vote(name, dir: next)
            } catch {
                votes[name] = current
            }
        }
    }

    func toggleSave(_ name: String, original: Bool?) {
        guard client.auth.isLoggedIn else {
            needsLogin = true
            return
        }
        let current = isSaved(name, original: original)
        saves[name] = !current
        Task {
            do {
                try await client.setSaved(name, saved: !current)
            } catch {
                saves[name] = current
            }
        }
    }
}
