import SwiftUI

// MARK: - Theme

struct KBTheme {
    let accent: Color
    let dark: Bool
    let glass: Bool

    var keyFill: Color { dark ? Color.white.opacity(0.16) : Color.white }
    var keyFillSpecial: Color { dark ? Color.white.opacity(0.07) : Color.black.opacity(0.09) }
    var text: Color { dark ? .white : .black }
    var subtext: Color { dark ? Color.white.opacity(0.55) : Color.black.opacity(0.5) }
    var keyShadow: Color { dark ? .black.opacity(0.5) : .black.opacity(0.22) }
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

// MARK: - A single key

struct KeyButtonStyle: ButtonStyle {
    let theme: KBTheme
    let fill: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fill)
                    .shadow(color: theme.keyShadow, radius: 0, x: 0, y: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .brightness(configuration.isPressed ? (theme.dark ? 0.10 : -0.05) : 0)
            .animation(.easeOut(duration: 0.07), value: configuration.isPressed)
    }
}

struct KeyView: View {
    let cap: KeyCap
    let theme: KBTheme
    @ObservedObject var model: KeyboardModel

    private var isChar: Bool { if case .char = cap { return true }; return false }

    private var label: String {
        if case .char(let s) = cap { return model.shift != .off ? s.uppercased() : s }
        return cap.display
    }

    private var shiftActive: Bool {
        if case .shift = cap { return model.shift != .off }
        return false
    }

    private var fill: Color {
        if shiftActive { return theme.accent }
        if case .gif = cap, model.panel == .gif { return theme.accent }
        return isChar ? theme.keyFill : theme.keyFillSpecial
    }

    var body: some View {
        Button { model.tap(cap) } label: {
            Group {
                switch cap {
                case .char: Text(label).font(.system(size: 22))
                case .space: Text("space").font(.system(size: 15, weight: .medium))
                case .ret: Text("return").font(.system(size: 15, weight: .medium))
                case .shift: Image(systemName: model.shift == .locked ? "capslock.fill" : (model.shift == .on ? "shift.fill" : "shift"))
                case .backspace: Image(systemName: "delete.left")
                case .globe: Image(systemName: "globe")
                case .gif: Text("GIF").font(.system(size: 14, weight: .heavy))
                case .plane(let p): Text(KeyCap.plane(p).display).font(.system(size: 15, weight: .medium))
                }
            }
            .foregroundStyle(shiftActive || (isGifActive) ? .white : theme.text)
        }
        .buttonStyle(KeyButtonStyle(theme: theme, fill: fill))
    }

    private var isGifActive: Bool { if case .gif = cap, model.panel == .gif { return true }; return false }
}

// MARK: - A row

struct KeyRowView: View {
    let row: [KeyCap]
    let theme: KBTheme
    @ObservedObject var model: KeyboardModel

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 5
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
        .frame(height: model.layout == .floating ? 38 : 44)
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
        VStack(spacing: 8) {
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
                    Button { model.applySuggestion(s) } label: {
                        Text(s)
                            .font(.system(size: 17, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(index == 0 ? theme.accent : theme.text)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    if index < model.suggestions.count - 1 {
                        Rectangle().fill(theme.subtext.opacity(0.3)).frame(width: 1, height: 22)
                    }
                }
            }
            Button { model.panel = model.panel == .kaomoji ? .none : .kaomoji } label: {
                Image(systemName: "face.smiling")
                    .foregroundStyle(model.panel == .kaomoji ? theme.accent : theme.subtext)
                    .frame(width: 40, height: 40)
            }
            Button { model.cycleLayout() } label: {
                Image(systemName: layoutIcon)
                    .foregroundStyle(model.layout == .normal ? theme.subtext : theme.accent)
                    .frame(width: 40, height: 40)
            }
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
                Button { model.panel = .none } label: {
                    Image(systemName: "keyboard").foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 10)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Kaomoji.all, id: \.self) { face in
                        Button { model.insertSnippet(face) } label: {
                            Text(face)
                                .font(.system(size: 15))
                                .foregroundStyle(theme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 10).fill(theme.keyFillSpecial))
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }
}
