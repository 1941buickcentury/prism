import SwiftUI
import Observation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark, black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .black: return "Pure Black"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .black: return .dark
        }
    }
}

enum AppAccent: String, CaseIterable, Identifiable {
    case redline, sunflower, emerald, azure, violet, magenta, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .redline: return "Redline"
        case .sunflower: return "Sunflower"
        case .emerald: return "Emerald"
        case .azure: return "Azure"
        case .violet: return "Violet"
        case .magenta: return "Magenta"
        case .graphite: return "Graphite"
        }
    }

    var color: Color {
        switch self {
        case .redline: return Color(red: 1.00, green: 0.34, blue: 0.18)
        case .sunflower: return Color(red: 1.00, green: 0.72, blue: 0.00)
        case .emerald: return Color(red: 0.00, green: 0.78, blue: 0.47)
        case .azure: return Color(red: 0.00, green: 0.52, blue: 1.00)
        case .violet: return Color(red: 0.58, green: 0.35, blue: 1.00)
        case .magenta: return Color(red: 1.00, green: 0.25, blue: 0.55)
        case .graphite: return Color(red: 0.44, green: 0.47, blue: 0.53)
        }
    }
}

/// Holds the user's chosen accent color and makes it available app-wide. Changing it
/// updates every view that reads `theme.accent` and the root `.tint`.
@Observable
@MainActor
final class ThemeManager {
    var accentID: String {
        didSet { UserDefaults.standard.set(accentID, forKey: "accentID") }
    }

    var appearanceID: String {
        didSet { UserDefaults.standard.set(appearanceID, forKey: "appearanceID") }
    }

    init() {
        accentID = UserDefaults.standard.string(forKey: "accentID") ?? AppAccent.redline.id
        appearanceID = UserDefaults.standard.string(forKey: "appearanceID") ?? AppAppearance.system.id
    }

    var selected: AppAccent {
        AppAccent(rawValue: accentID) ?? .redline
    }

    var accent: Color { selected.color }

    var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceID) ?? .system
    }

    var colorScheme: ColorScheme? { appearance.colorScheme }

    var pureBlack: Bool { appearance == .black }
}
