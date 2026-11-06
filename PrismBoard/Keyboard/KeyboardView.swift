import SwiftUI

// MARK: - Theme

struct KBTheme {
    let accent: Color
    let dark: Bool
    let glass: Bool

    var keyFill: Color { dark ? Color.white.opacity(0.18) : Color.white.opacity(0.92) }
    var keyFillSpecial: Color { dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07) }
    var keyStroke: Color { dark ? Color.white.opacity(0.14) : Color.black.opacity(0.05) }
    var text: Color { dark ? .white : .black }
    var subtext: Color { dark ? Color.white.opacity(0.55) : Color.black.opacity(0.5) }
    var keyShadow: Color { dark ? .black.opacity(0.35) : .black.opacity(0.18) }
}

// MARK: - Key sizing

private func keyWeight(_ cap: KeyCap) -> CGFloat {
    switch cap {
    case .char: return 1.0
    case .shift, .backspace, .plane: return 1.5
    case .globe, .gif: return 1.2
    case .space: return 4.4
    case .ret: return 2.0
    }
}

// MARK: - Reliable tap for keyboard extensions

/// SwiftUI `Button` and `.onTapGesture` are unreliable inside a keyboard extension's hosting
/// view; a zero-distance drag is not, so all taps go through this.
extension View {
    func tapKey(_ action: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { _ in action() })
    }
}

// MARK: - A single key

struct KeyView: View {
    let cap: KeyCap
    let theme: KBTheme
    @ObservedObject var model: KeyboardModel
    @GestureState private var pressed = false

    private var isChar: Bool { if case .char = cap { return true }; return false }

    private var label: String {
        if case .char(let s) = cap { return model.shift != .off ? s.uppercased() : s }
        return cap.display
    }

    private var shiftActive: Bool { if case .shift = cap { return model.shift != .off }; return false }
    private var isGifActive: Bool { if case .gif = cap, model.panel == .gif { return true }; return false }

    private var fill: Color {
        if shiftActive || isGifActive { return theme.accent }
        return isChar ? theme.keyFill : theme.keyFillSpecial
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(theme.keyStroke, lineWidth: 0.5)
                )
                .shadow(color: theme.keyShadow, radius: 0, x: 0, y: 1)
            labelContent
                .foregroundStyle(shiftActive || isGifActive ? .white : theme.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .brightness(pressed ? (theme.dark ? 0.12 : -0.06) : 0)
        .scaleEffect(pressed ? 0.93 : 1)
        .animation(.easeOut(duration: 0.06), value: pressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($pressed) { _, state, _ in state = true }
                .onEnded { _ in model.tap(cap) }
        )
    }

    @ViewBuilder
    private var labelContent: some View {
        switch cap {
        case .char: Text(label).font(.system(size: 23))
        case .space: Text("space").font(.system(size: 15, weight: .medium))
        case .ret: Text("return").font(.system(size: 15, weight: .medium))
        case .shift: Image(systemName: model.shift == .locked ? "capslock.fill" : (model.shift == .on ? "shift.fill" : "shift"))
        case .backspace: Image(systemName: "delete.left")
        case .globe: Image(systemName: "globe")
        case .gif: Text("GIF").font(.system(size: 14, weight: .heavy))
        case .plane(let p): Text(KeyCap.plane(p).display).font(.system(size: 15, weight: .medium))
        }
    }
}

// MARK: - A row

struct KeyRowView: View {
    let row: [KeyCap]
    let theme: KBTheme
    @ObservedObject var model: KeyboardModel

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            if model.layout == .split && row.count > 3 {
                let mid = (row.count + 1) / 2
                let half = geo.size.width / 2 - 16
                HStack(spacing: spacing) {
                    rowStack(Array(row[0..<mid]), width: half, spacing: spacing)
                    Spacer(minLength: 20)
                    rowStack(Array(row[mid...]), width: half, spacing: spacing)
                }
            } else {
                rowStack(row, width: geo.size.width, spacing: spacing)
            }
        }
        .frame(height: model.layout == .floating ? 44 : 52)
    }

    private func rowStack(_ keys: [KeyCap], width: CGFloat, spacing: CGFloat) -> some View {
        let weights = keys.map(keyWeight)
        let total = max(weights.reduce(0, +), 0.01)
        let avail = width - spacing * CGFloat(max(keys.count - 1, 0))
        return HStack(spacing: spacing) {
            ForEach(keys.indices, id: \.self) { i in
                KeyView(cap: keys[i], theme: theme, model: model)
                    .frame(width: max(avail * weights[i] / total, 8))
            }
        }
    }
}

// MARK: - The keys area

struct KeysView: View {
    @ObservedObject var model: KeyboardModel
    let theme: KBTheme

    var body: some View {
        VStack(spacing: model.layout == .floating ? 9 : 11) {
            ForEach(model.rows.indices, id: \.self) { r in
                KeyRowView(row: model.rows[r], theme: theme, model: model)
            }
        }
    }
}

// MARK: - Suggestion bar

struct SuggestionBar: View {
    @ObservedObject var model: KeyboardModel
    let theme: KBTheme

    var body: some View {
        HStack(spacing: 0) {
            if model.suggestions.isEmpty {
                Text("Prism").font(.footnote.weight(.semibold)).foregroundStyle(theme.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
            } else {
                ForEach(Array(model.suggestions.enumerated()), id: \.offset) { index, s in
                    Text(s)
                        .font(.system(size: 17, weight: index == 0 ? .semibold : .regular))
                        .foregroundStyle(index == 0 ? theme.accent : theme.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .tapKey { model.applySuggestion(s) }
                    if index < model.suggestions.count - 1 {
                        Rectangle().fill(theme.subtext.opacity(0.3)).frame(width: 1, height: 22)
                    }
                }
            }
            Image(systemName: "face.smiling")
                .foregroundStyle(model.panel == .kaomoji ? theme.accent : theme.subtext)
                .frame(width: 42, height: 40)
                .tapKey { model.panel = model.panel == .kaomoji ? .none : .kaomoji }
            Image(systemName: layoutIcon)
                .foregroundStyle(model.layout == .normal ? theme.subtext : theme.accent)
                .frame(width: 42, height: 40)
                .tapKey { model.cycleLayout() }
        }
        .frame(height: 44)
        .padding(.horizontal, 4)
    }

    private var layoutIcon: String {
        switch model.layout {
        case .normal: return "rectangle.split.2x1"
        case .split: return "rectangle.split.2x1.fill"
        case .floating: return "macwindow"
        }
    }
}

// MARK: - Kaomoji panel

struct KaomojiPanel: View {
    @ObservedObject var model: KeyboardModel
    let theme: KBTheme

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Faces").font(.subheadline.weight(.semibold)).foregroundStyle(theme.subtext)
                Spacer()
                Image(systemName: "keyboard").foregroundStyle(theme.accent)
                    .frame(width: 40, height: 32)
                    .tapKey { model.panel = .none }
            }
            .padding(.horizontal, 10)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Kaomoji.all, id: \.self) { face in
                        Text(face)
                            .font(.system(size: 15))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(theme.keyFillSpecial))
                            .onTapGesture { model.insertSnippet(face) }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }
}
