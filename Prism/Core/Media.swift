import Foundation

struct MediaImage {
    let url: URL
    let caption: String?
    let width: Int?
    let height: Int?
}

enum PostMedia {
    case images([MediaImage])
    case video(URL, isGif: Bool)
    case link(URL)
    case none

    var isVisual: Bool {
        switch self {
        case .images, .video: return true
        default: return false
        }
    }
}

extension Post {
    var subredditPrefixed: String { subredditNamePrefixed ?? "r/\(subreddit)" }

    var created: Date { Date(timeIntervalSince1970: createdUtc) }

    var permalinkURL: URL {
        URL(string: "https://www.reddit.com\(permalink)") ?? URL(string: "https://www.reddit.com")!
    }

    /// Works out what kind of media a post carries: gallery, Reddit-hosted video, GIF, image, or an outside link.
    var resolvedMedia: PostMedia {
        if isGallery == true, let items = galleryData?.items, let meta = mediaMetadata {
            let images: [MediaImage] = items.compactMap { item in
                guard let s = meta[item.mediaId]?.s,
                      let raw = s.u ?? s.gif,
                      let url = URL(string: raw) else { return nil }
                return MediaImage(url: url, caption: item.caption, width: s.x, height: s.y)
            }
            if !images.isEmpty { return .images(images) }
        }

        if let video = secureMedia?.redditVideo ?? media?.redditVideo,
           let raw = video.hlsUrl ?? video.fallbackUrl,
           let url = URL(string: raw) {
            return .video(url, isGif: video.isGif ?? false)
        }

        if let video = preview?.redditVideoPreview,
           let raw = video.hlsUrl ?? video.fallbackUrl,
           let url = URL(string: raw) {
            return .video(url, isGif: video.isGif ?? true)
        }

        if let raw = url, let link = URL(string: raw) {
            let ext = link.pathExtension.lowercased()
            if ext == "gifv", let mp4 = URL(string: raw.replacingOccurrences(of: ".gifv", with: ".mp4")) {
                return .video(mp4, isGif: true)
            }
            if ext == "gif",
               let mp4Raw = preview?.images?.first?.variants?.mp4?.source?.url,
               let mp4 = URL(string: mp4Raw) {
                return .video(mp4, isGif: true)
            }
            if postHint == "image" || ["jpg", "jpeg", "png", "webp", "gif"].contains(ext) {
                let source = preview?.images?.first?.source
                return .images([MediaImage(url: link, caption: nil, width: source?.width, height: source?.height)])
            }
        }

        if let cross = crosspostParentList?.first {
            let crossMedia = cross.resolvedMedia
            if crossMedia.isVisual { return crossMedia }
        }

        if isSelf != true, let raw = url, let link = URL(string: raw), link.scheme?.hasPrefix("http") == true {
            return .link(link)
        }
        return .none
    }

    /// A feed-sized preview image (around 640px wide when Reddit offers one).
    var previewURL: URL? {
        if let image = preview?.images?.first {
            let pick = image.resolutions?.first(where: { ($0.width ?? 0) >= 640 }) ?? image.source
            if let raw = pick?.url, let url = URL(string: raw) { return url }
        }
        if isGallery == true, let first = galleryData?.items.first, let meta = mediaMetadata?[first.mediaId] {
            let pick = meta.p?.first(where: { ($0.x ?? 0) >= 640 }) ?? meta.s
            if let raw = pick?.u ?? pick?.gif, let url = URL(string: raw) { return url }
        }
        if let cross = crosspostParentList?.first { return cross.previewURL }
        return nil
    }

    var previewAspect: Double {
        if let s = preview?.images?.first?.source, let w = s.width, let h = s.height, h > 0 {
            return Double(w) / Double(h)
        }
        if isGallery == true, let first = galleryData?.items.first,
           let s = mediaMetadata?[first.mediaId]?.s, let w = s.x, let h = s.y, h > 0 {
            return Double(w) / Double(h)
        }
        if let v = secureMedia?.redditVideo ?? media?.redditVideo, let w = v.width, let h = v.height, h > 0 {
            return Double(w) / Double(h)
        }
        if let cross = crosspostParentList?.first { return cross.previewAspect }
        return 16.0 / 9.0
    }

    var thumbnailURL: URL? {
        if let t = thumbnail, t.hasPrefix("http"), let url = URL(string: t) { return url }
        return previewURL
    }
}
