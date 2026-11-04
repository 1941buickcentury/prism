import SwiftUI
import SafariServices

// MARK: - Background

/// A soft mesh gradient behind every screen, so the Liquid Glass surfaces have color to bend.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        if theme.pureBlack {
            Color.black.ignoresSafeArea()
        } else {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.55, 0.45], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: scheme == .dark ? Self.dark : Self.light
            )
            .ignoresSafeArea()
        }
    }

    private static let dark: [Color] = [
        Color(red: 0.05, green: 0.05, blue: 0.10), Color(red: 0.11, green: 0.06, blue: 0.17), Color(red: 0.04, green: 0.07, blue: 0.15),
        Color(red: 0.16, green: 0.06, blue: 0.10), Color(red: 0.09, green: 0.07, blue: 0.15), Color(red: 0.03, green: 0.10, blue: 0.15),
        Color(red: 0.22, green: 0.09, blue: 0.05), Color(red: 0.06, green: 0.05, blue: 0.12), Color(red: 0.05, green: 0.09, blue: 0.17)
    ]

    private static let light: [Color] = [
        Color(red: 0.99, green: 0.95, blue: 0.93), Color(red: 0.95, green: 0.93, blue: 0.99), Color(red: 0.92, green: 0.96, blue: 1.00),
        Color(red: 1.00, green: 0.89, blue: 0.85), Color(red: 0.97, green: 0.95, blue: 0.99), Color(red: 0.87, green: 0.95, blue: 0.99),
        Color(red: 1.00, green: 0.92, blue: 0.86), Color(red: 0.94, green: 0.91, blue: 1.00), Color(red: 0.89, green: 0.96, blue: 0.98)
    ]
}

// MARK: - Glass card

struct GlassCardModifier: ViewModifier {
    @AppStorage("glassCards") private var glassCards = true
    let radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if glassCards {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: .rect(cornerRadius: radius))
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCardModifier(radius: cornerRadius))
    }

    /// A list row with no background or separator, so cards float over the ambient background.
    func plainRow(vertical: CGFloat = 6, horizontal: CGFloat = 12) -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal))
    }

    func errorAlert(_ error: Binding<String?>, title: String = "Something went wrong") -> some View {
        alert(title, isPresented: Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error.wrappedValue ?? "")
        }
    }
}

// MARK: - Small pieces

struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct Avatar: View {
    let url: URL?
    var size: CGFloat = 36
    var fallback: String = "person.fill"
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.15)
                }
            } else {
                Image(systemName: fallback)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.accent.gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct LoadingRow: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
    }
}

struct LoginPromptView: View {
    let title: String
    let message: String

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 54))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.title2.bold())
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                LoginButton()
                    .padding(.top, 6)
            }
            .padding(28)
            .glassEffect(.regular, in: .rect(cornerRadius: 32))
            .padding(20)
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

// MARK: - Formatting

extension Date {
    var shortAgo: String {
        let seconds = max(0, Date().timeIntervalSince(self))
        switch seconds {
        case ..<60: return "now"
        case ..<3_600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3_600))h"
        case ..<2_592_000: return "\(Int(seconds / 86_400))d"
        case ..<31_536_000: return "\(Int(seconds / 2_592_000))mo"
        default: return "\(Int(seconds / 31_536_000))y"
        }
    }
}

extension Int {
    var compact: String {
        let value = Double(self)
        switch abs(value) {
        case 1_000_000...: return String(format: "%.1fM", value / 1_000_000)
        case 10_000...: return String(format: "%.0fk", value / 1_000)
        case 1_000...: return String(format: "%.1fk", value / 1_000)
        default: return "\(self)"
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
