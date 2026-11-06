import SwiftUI
import Combine

protocol KeyboardProxy: AnyObject {
    var contextBefore: String { get }
    func insert(_ text: String)
    func deleteBackward()
}

enum ShiftState { case off, on, locked }
enum LayoutMode: String, CaseIterable { case normal, split, floating }
enum Panel { case none, kaomoji, gif }

@MainActor
final class KeyboardModel: ObservableObject {
    @Published var plane: KeyPlane = .letters
    @Published var shift: ShiftState = .on
    @Published var layout: LayoutMode = .normal
    @Published var panel: Panel = .none
    @Published var suggestions: [String] = []
    @Published var floatingOffset: CGSize = .zero
    @Published var pressedKey: String?

    let engine: WordEngine
    weak var proxy: KeyboardProxy?
    var onGlobe: () -> Void = {}
    var onHeightChange: () -> Void = {}
    let hasFullAccess: Bool
    let haptics: Haptics

    // Settings snapshot (read once when the keyboard loads).
    let accent: KBAccent
    let dark: Bool
    let glass: Bool
    let autocorrectOn: Bool
    let glideOn: Bool
    let numberRow: Bool

    init(engine: WordEngine, proxy: KeyboardProxy, hasFullAccess: Bool, systemDark: Bool) {
        self.engine = engine
        self.proxy = proxy
        self.hasFullAccess = hasFullAccess
        let s = SharedStore.shared
        self.accent = s.accent
        switch s.appearance {
        case .dark, .black: self.dark = true
        case .light: self.dark = false
        case .system: self.dark = systemDark
        }
        self.glass = s.glass
        self.autocorrectOn = s.autocorrect
        self.glideOn = s.glide
        self.numberRow = s.numberRow
        self.haptics = Haptics(enabled: s.haptics && hasFullAccess)
        refreshSuggestions()
    }

    var rows: [[KeyCap]] { Layout.rows(for: plane, showNumberRow: numberRow && plane == .letters) }

    var currentWord: String {
        let before = proxy?.contextBefore ?? ""
        let tail = before.reversed().prefix { $0.isLetter || $0 == "'" }
        return String(tail.reversed())
    }

    func syncContext() {
        refreshSuggestions()
        updateAutoShift()
    }

    func refreshSuggestions() {
        let w = currentWord
        suggestions = w.isEmpty ? [] : engine.suggestions(forTyping: w)
    }

    private func updateAutoShift() {
        guard shift != .locked else { return }
        let before = proxy?.contextBefore ?? ""
        if before.isEmpty || before.hasSuffix(". ") || before.hasSuffix("? ")
            || before.hasSuffix("! ") || before.hasSuffix("\n") {
            shift = .on
        }
    }

    // MARK: Key handling

    func tap(_ cap: KeyCap) {
        switch cap {
        case .char(let s): insertChar(s)
        case .shift: haptics.control(); cycleShift()
        case .backspace: haptics.control(); proxy?.deleteBackward(); refreshSuggestions()
        case .plane(let p): haptics.key(); plane = p
        case .globe: onGlobe()
        case .space: handleSpace()
        case .ret: haptics.wide(); proxy?.insert("\n"); updateAutoShift(); refreshSuggestions()
        case .gif: haptics.key(); panel = panel == .gif ? .none : .gif
        }
    }

    private func insertChar(_ s: String) {
        haptics.key()
        let out = shift != .off ? s.uppercased() : s
        proxy?.insert(out)
        if shift == .on { shift = .off }
        refreshSuggestions()
    }

    private func cycleShift() {
        switch shift {
        case .off: shift = .on
        case .on: shift = .locked
        case .locked: shift = .off
        }
    }

    private func handleSpace() {
        haptics.wide()
        let w = currentWord
        if autocorrectOn, !w.isEmpty {
            let fixed = engine.correct(w)
            if fixed != w {
                for _ in 0..<w.count { proxy?.deleteBackward() }
                proxy?.insert(fixed)
            }
        }
        proxy?.insert(" ")
        updateAutoShift()
        refreshSuggestions()
    }

    func applySuggestion(_ s: String) {
        haptics.key()
        let w = currentWord
        for _ in 0..<w.count { proxy?.deleteBackward() }
        proxy?.insert(s + " ")
        if shift == .on { shift = .off }
        updateAutoShift()
        refreshSuggestions()
    }

    func insertSnippet(_ text: String) {
        haptics.key()
        proxy?.insert(text)
        refreshSuggestions()
    }

    func commitGlide(_ keys: [Character]) {
        var deduped: [Character] = []
        for k in keys where deduped.last != k { deduped.append(k) }
        guard deduped.count >= 2, let word = engine.decodeGlide(String(deduped)) else { return }
        let cased = shift != .off ? word.prefix(1).uppercased() + word.dropFirst() : word
        proxy?.insert(cased + " ")
        if shift == .on { shift = .off }
        updateAutoShift()
        refreshSuggestions()
        haptics.glideCommit()
    }

    // MARK: Layout

    func cycleLayout() {
        haptics.control()
        switch layout {
        case .normal: layout = .split
        case .split: layout = .floating
        case .floating: layout = .normal
        }
        floatingOffset = .zero
        onHeightChange()
    }

    var keyboardHeight: CGFloat {
        let rowCount = CGFloat(rows.count)
        let rowH: CGFloat = layout == .floating ? 44 : 52
        let rowSpacing: CGFloat = layout == .floating ? 9 : 11
        // suggestion bar (44) + top gap, rows + inter-row spacing, bottom padding
        return 50 + rowCount * rowH + max(rowCount - 1, 0) * rowSpacing + 16
    }
}
