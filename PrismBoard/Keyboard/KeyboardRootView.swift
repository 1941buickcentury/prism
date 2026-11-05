import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel
    @State private var floatBase: CGSize = .zero

    private var theme: KBTheme { KBTheme(accent: model.accent.color, dark: model.dark, glass: model.glass) }

    var body: some View {
        ZStack {
            background
            if model.layout == .floating {
                floatingLayer
            } else {
                VStack(spacing: 6) {
                    SuggestionBar(model: model, theme: theme)
                    panelOrKeys
                }
                .padding(.horizontal, 3)
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(model.dark ? .dark : .light)
    }

    private var background: some View {
        ZStack {
            (model.dark ? Color(red: 0.06, green: 0.06, blue: 0.08) : Color(red: 0.82, green: 0.83, blue: 0.86))
            if model.dark {
                RadialGradient(
                    colors: [model.accent.color.opacity(0.20), .clear],
                    center: .top, startRadius: 0, endRadius: 360
                )
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var panelOrKeys: some View {
        switch model.panel {
        case .none: KeysView(model: model, theme: theme)
        case .kaomoji: KaomojiPanel(model: model, theme: theme)
        case .gif: GifPanel(model: model, theme: theme)
        }
    }

    private var floatingLayer: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                floatingCard
            }
        }
    }

    private var floatingCard: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(theme.subtext.opacity(0.6))
                .frame(width: 42, height: 5)
                .padding(.top, 7)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { model.floatingOffset = CGSize(width: floatBase.width + $0.translation.width,
                                                                   height: floatBase.height + $0.translation.height) }
                        .onEnded { _ in floatBase = model.floatingOffset }
                )
            SuggestionBar(model: model, theme: theme)
            panelOrKeys
                .padding(.bottom, 8)
        }
        .frame(width: 344)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(model.dark ? Color(red: 0.11, green: 0.11, blue: 0.13) : Color(white: 0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        .offset(model.floatingOffset)
        .padding(10)
    }
}
