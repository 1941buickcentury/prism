import Foundation

/// Dictionary-backed autocorrect and next-word prediction. The bundled word list is ordered
/// by frequency (line 0 = most common), so a word's index is a usable rank.
final class WordEngine {
    private var rank: [String: Int] = [:]
    private var ranked: [String] = []
    private var prefixIndex: [String: [String]] = [:]   // first two letters → words, by rank
    private let letters = "abcdefghijklmnopqrstuvwxyz"

    init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for (i, raw) in text.split(separator: "\n").enumerated() {
            let w = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if w.isEmpty || rank[w] != nil { continue }
            rank[w] = i
            ranked.append(w)
            let key = String(w.prefix(2))
            prefixIndex[key, default: []].append(w)
        }
    }

    func isWord(_ w: String) -> Bool { rank[w.lowercased()] != nil }

    /// Words that begin with `prefix`, best first.
    func predictions(prefix: String, limit: Int = 3) -> [String] {
        let p = prefix.lowercased()
        if p.isEmpty { return [] }
        let pool: [String]
        if p.count >= 2 {
            pool = prefixIndex[String(p.prefix(2))] ?? []
        } else {
            pool = ranked.filter { $0.hasPrefix(p) }
        }
        return pool.filter { $0.hasPrefix(p) && $0 != p }
            .sorted { (rank[$0] ?? Int.max) < (rank[$1] ?? Int.max) }
            .prefix(limit)
            .map { $0 }
    }

    /// Best single correction for a finished word, or the word itself if it's already valid.
    func correct(_ word: String) -> String {
        let w = word.lowercased()
        if w.count < 2 || isWord(w) { return word }
        let candidates = edits1(w).filter { rank[$0] != nil }
        guard let best = candidates.min(by: { (rank[$0] ?? Int.max) < (rank[$1] ?? Int.max) }) else {
            return word
        }
        // Only correct to a clearly common word to avoid surprising swaps.
        if (rank[best] ?? Int.max) > 8000 { return word }
        return matchCase(of: word, to: best)
    }

    /// The three-slot suggestion bar for the word currently being typed.
    func suggestions(forTyping typed: String) -> [String] {
        let w = typed.lowercased()
        var out: [String] = []
        let preds = predictions(prefix: w, limit: 3)
        if isWord(w) {
            out.append(typed)
        } else {
            let c = edits1(w).filter { rank[$0] != nil }
                .min(by: { (rank[$0] ?? Int.max) < (rank[$1] ?? Int.max) })
            if let c { out.append(matchCase(of: typed, to: c)) }
        }
        for p in preds where !out.contains(where: { $0.lowercased() == p }) {
            out.append(matchCase(of: typed, to: p))
            if out.count >= 3 { break }
        }
        if !out.contains(where: { $0.lowercased() == w }) && !w.isEmpty {
            out.insert(typed, at: min(1, out.count))
        }
        return Array(out.prefix(3))
    }

    private func matchCase(of source: String, to target: String) -> String {
        guard let first = source.first else { return target }
        if first.isUppercase { return target.prefix(1).uppercased() + target.dropFirst() }
        return target
    }

    /// Best dictionary word for a glide path: the ordered keys the finger crossed, with
    /// consecutive duplicates already removed. Picks the most common word that starts and ends
    /// on the path's endpoints and whose letters appear in order along the path.
    func decodeGlide(_ path: String) -> String? {
        let keys = Array(path.lowercased())
        guard keys.count >= 2, let first = keys.first, let last = keys.last else { return nil }
        let pathStr = String(keys)
        var best: String?
        var bestScore = Int.max
        for word in ranked where word.count >= 2 {
            guard word.first == first, word.last == last else { continue }
            if !Self.isSubsequence(word, of: pathStr) { continue }
            let r = rank[word] ?? Int.max
            let score = r + abs(word.count - keys.count) * 400
            if score < bestScore { bestScore = score; best = word }
        }
        return best
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var iterator = haystack.makeIterator()
        var current = iterator.next()
        for ch in needle {
            while let c = current, c != ch { current = iterator.next() }
            guard current != nil else { return false }
            current = iterator.next()
        }
        return true
    }

    private func edits1(_ word: String) -> Set<String> {
        var result = Set<String>()
        let chars = Array(word)
        let n = chars.count
        // deletions
        for i in 0..<n {
            var c = chars; c.remove(at: i); result.insert(String(c))
        }
        // transpositions
        if n > 1 {
            for i in 0..<(n - 1) {
                var c = chars; c.swapAt(i, i + 1); result.insert(String(c))
            }
        }
        // replacements
        for i in 0..<n {
            for l in letters {
                var c = chars; c[i] = l; result.insert(String(c))
            }
        }
        // insertions
        for i in 0...n {
            for l in letters {
                var c = chars; c.insert(l, at: i); result.insert(String(c))
            }
        }
        return result
    }
}
