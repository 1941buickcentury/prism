import SwiftUI
import UIKit

/// GIF search via Tenor. Needs Full Access (for network) and a Tenor API key, which the user
/// adds in the Prism app. Tapping a GIF copies it so it can be pasted into the conversation —
/// keyboard extensions can't insert images directly into arbitrary apps.
struct GifPanel: View {
    @ObservedObject var model: KeyboardModel
    let theme: KBTheme

    @State private var query = ""
    @State private var results: [TenorGif] = []
    @State private var loading = false
    @State private var toast: String?
    @State private var loadTask: Task<Void, Never>?

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
    private var apiKey: String { SharedStore.shared.tenorKey }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.subtext)
                    TextField("Search GIFs", text: $query)
                        .foregroundStyle(theme.text)
                        .submitLabel(.search)
                        .onSubmit { search(query) }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.keyFillSpecial))
                Button { model.panel = .none } label: {
                    Image(systemName: "keyboard").foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 8)

            if !model.hasFullAccess {
                notice("Turn on Full Access for Prism Keyboard in Settings to use GIFs.")
            } else if apiKey.isEmpty {
                notice("Add a Tenor API key in the Prism app to enable GIF search.")
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(results) { gif in
                            Button { copy(gif) } label: {
                                AsyncImage(url: URL(string: gif.preview)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8).fill(theme.keyFillSpecial)
                                }
                                .frame(height: 92)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(theme.accent))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)
            }
        }
        .onAppear { if results.isEmpty { search("trending") } }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(theme.subtext)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func search(_ term: String) {
        guard model.hasFullAccess, !apiKey.isEmpty else { return }
        loadTask?.cancel()
        loading = true
        let q = term.trimmingCharacters(in: .whitespaces)
        let path = q.isEmpty || q == "trending" ? "featured" : "search"
        var comps = URLComponents(string: "https://tenor.googleapis.com/v2/\(path)")!
        comps.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: q.isEmpty ? "trending" : q),
            URLQueryItem(name: "limit", value: "24"),
            URLQueryItem(name: "media_filter", value: "tinygif,gif"),
            URLQueryItem(name: "client_key", value: "prismboard")
        ]
        guard let url = comps.url else { loading = false; return }
        loadTask = Task {
            defer { loading = false }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(TenorResponse.self, from: data)
                if Task.isCancelled { return }
                results = decoded.results.compactMap { $0.gif }
            } catch {
                if !Task.isCancelled { results = [] }
            }
        }
    }

    private func copy(_ gif: TenorGif) {
        model.haptics.wide()
        Task {
            guard let url = URL(string: gif.full),
                  let (data, _) = try? await URLSession.shared.data(from: url) else {
                await MainActor.run { showToast("Couldn't load that GIF") }
                return
            }
            await MainActor.run {
                UIPasteboard.general.setData(data, forPasteboardType: "com.compuserve.gif")
                showToast("Copied — paste it in")
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { toast = nil }
        }
    }
}

// MARK: - Tenor models

struct TenorResponse: Decodable { let results: [TenorResult] }

struct TenorResult: Decodable {
    let id: String
    let mediaFormats: [String: TenorMedia]

    enum CodingKeys: String, CodingKey { case id; case mediaFormats = "media_formats" }

    var gif: TenorGif? {
        let preview = mediaFormats["tinygif"]?.url ?? mediaFormats["gif"]?.url
        let full = mediaFormats["gif"]?.url ?? mediaFormats["tinygif"]?.url
        guard let preview, let full else { return nil }
        return TenorGif(id: id, preview: preview, full: full)
    }
}

struct TenorMedia: Decodable { let url: String }

struct TenorGif: Identifiable {
    let id: String
    let preview: String
    let full: String
}
