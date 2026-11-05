import SwiftUI

/// Settings shared between the container app and the keyboard extension via an App Group.
/// Falls back to standard defaults if the group isn't available (e.g. entitlement stripped).
enum KBAppearance: String, CaseIterable, Identifiable {
    case system, light, dark, black
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"; case .light: return "Light"
        case .dark: return "Dark"; case .black: return "Pure Black"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil; case .light: return .light
        case .dark, .black: return .dark
        }
    }
}

enum KBAccent: String, CaseIterable, Identifiable {
    case redline, sunflower, emerald, azure, violet, magenta, graphite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .redline: return "Redline"; case .sunflower: return "Sunflower"
        case .emerald: return "Emerald"; case .azure: return "Azure"
        case .violet: return "Violet"; case .magenta: return "Magenta"
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

final class SharedStore {
    static let shared = SharedStore()
    static let groupID = "group.com.shotatredline.prismboard"

    private let defaults: UserDefaults
    private init() {
        defaults = UserDefaults(suiteName: SharedStore.groupID) ?? .standard
    }

    private func str(_ k: String, _ d: String) -> String { defaults.string(forKey: k) ?? d }
    private func bool(_ k: String, _ d: Bool) -> Bool { defaults.object(forKey: k) == nil ? d : defaults.bool(forKey: k) }

    var accent: KBAccent {
        get { KBAccent(rawValue: str("kb_accent", "redline")) ?? .redline }
        set { defaults.set(newValue.rawValue, forKey: "kb_accent") }
    }
    var appearance: KBAppearance {
        get { KBAppearance(rawValue: str("kb_appearance", "system")) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "kb_appearance") }
    }
    var glass: Bool {
        get { bool("kb_glass", true) }; set { defaults.set(newValue, forKey: "kb_glass") }
    }
    var haptics: Bool {
        get { bool("kb_haptics", true) }; set { defaults.set(newValue, forKey: "kb_haptics") }
    }
    var autocorrect: Bool {
        get { bool("kb_autocorrect", true) }; set { defaults.set(newValue, forKey: "kb_autocorrect") }
    }
    var glide: Bool {
        get { bool("kb_glide", true) }; set { defaults.set(newValue, forKey: "kb_glide") }
    }
    var numberRow: Bool {
        get { bool("kb_numberrow", true) }; set { defaults.set(newValue, forKey: "kb_numberrow") }
    }
    var tenorKey: String {
        get { str("kb_tenor", "") }; set { defaults.set(newValue, forKey: "kb_tenor") }
    }
}
