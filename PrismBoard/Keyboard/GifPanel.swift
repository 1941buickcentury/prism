import SwiftUI
import UIKit

/// GIF browsing via Tenor. Needs Full Access (for network) and a Tenor API key, which the user
/// adds in the Prism app. A text field can't be focused inside a keyboard, so this uses tappable
/// category chips instead of search. Tapping a GIF copies it to paste into the conversation.
struct GifPanel: View {
    @ObservedObject var model: KeyboardModel
    let theme: KBTheme

    @State private var results: [TenorGif] = []
    @State private var loading = false
    @State private var toast: String?
    @State private var category = "trending"
    @State private var loadTask: Task<Void, Never>?

    private let categories = ["trending", "lol", "love", "yes", "no", "wow", "sad", "ok"]
    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
    private var apiKey: String { SharedStore.shared.tenorKey }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat.capitalized)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(category == cat ? .white : theme.text)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(category == cat ? theme.accent : theme.keyFillSpecial))
                                .onTapGesture { category = cat; search(cat) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                Image(systemName: "keyboard").foregroundStyle(theme.accent)
                    .frame(width: 42, height: 34)
                    .tapKey { model.panel = .none }
                    .padding(.trailing, 6)
            }

            if !model.hasFullAccess {
                notice("Turn on Full Access for Prism Keyboard in Settings to use GIFs.")
            } else if apiKey.isEmpty {
                notice("Add a Tenor API key in the Prism app to enable GIFs.")
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(results) { gif in
                            AsyncImage(url: URL(string: gif.preview)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8).fill(theme.keyFillSpecial)
                            }
                            .frame(height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { copy(gif) }
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
        .onAppear { if results.isEmpty { search(category) } }
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
        let isTrending = term == "trending"
        var comps = URLComponents(string: "https://tenor.googleapis.com/v2/\(isTrending ? "featured" : "search")")!
        comps.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: isTrending ? "trending" : term),
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
