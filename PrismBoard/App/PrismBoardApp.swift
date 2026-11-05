import SwiftUI

@main
struct PrismBoardApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

private let groupStore = UserDefaults(suiteName: SharedStore.groupID)

struct AppRootView: View {
    @AppStorage("kb_appearance", store: groupStore) private var appearance = KBAppearance.system.rawValue
    @AppStorage("kb_accent", store: groupStore) private var accent = KBAccent.redline.rawValue
    @AppStorage("kb_glass", store: groupStore) private var glass = true
    @AppStorage("kb_haptics", store: groupStore) private var haptics = true
    @AppStorage("kb_autocorrect", store: groupStore) private var autocorrect = true
    @AppStorage("kb_glide", store: groupStore) private var glide = true
    @AppStorage("kb_numberrow", store: groupStore) private var numberRow = true
    @AppStorage("kb_tenor", store: groupStore) private var tenorKey = ""

    @State private var preview = ""

    private var accentColor: Color { (KBAccent(rawValue: accent) ?? .redline).color }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Try it here").font(.subheadline.weight(.semibold))
                        TextField("Tap here, then switch to Prism Keyboard with 🌐", text: $preview, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...5)
                    }
                }

                Section("Enable the keyboard") {
                    Label("Settings › General › Keyboard › Keyboards › Add New Keyboard › Prism", systemImage: "1.circle")
                    Label("Tap Prism in the list, then turn on Allow Full Access (needed for haptics and GIFs)", systemImage: "2.circle")
                    Label("In any app, long-press 🌐 and pick Prism", systemImage: "3.circle")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(KBAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Accent")
                        HStack(spacing: 14) {
                            ForEach(KBAccent.allCases) { option in
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if accent == option.rawValue {
                                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                        }
                                    }
                                    .onTapGesture { accent = option.rawValue }
                            }
                        }
                    }
                    Toggle("Glass look", isOn: $glass)
                }

                Section("Typing") {
                    Toggle("Haptics", isOn: $haptics)
                    Toggle("Autocorrect", isOn: $autocorrect)
                    Toggle("Glide typing (swipe)", isOn: $glide)
                    Toggle("Number row", isOn: $numberRow)
                }

                Section {
                    SecureField("Tenor API key", text: $tenorKey)
                } header: {
                    Text("GIFs")
                } footer: {
                    Text("Get a free key from Tenor (Google) to enable GIF search. Leave blank to skip GIFs.")
                }
            }
            .navigationTitle("Prism Keyboard")
            .tint(accentColor)
        }
    }
}
