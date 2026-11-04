import SwiftUI
import AVKit
import AVFoundation
import Combine
import UIKit

/// Full-screen viewer for images, galleries, videos and GIFs, with floating Liquid Glass controls.
struct MediaViewer: View {
    let presentation: MediaPresentation

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var showChrome = true
    @State private var dragY: CGFloat = 0
    @State private var zoomed = false
    @State private var saveStatus: SaveStatus = .idle

    enum SaveStatus { case idle, saving, saved, failed }

    private var images: [MediaImage] {
        if case .images(let images) = presentation.media { return images }
        return []
    }

    private var currentURL: URL? {
        switch presentation.media {
        case .images(let images): return images.indices.contains(index) ? images[index].url : nil
        case .video(let url, _): return url
        default: return nil
        }
    }

    private var caption: String {
        if images.indices.contains(index), let caption = images[index].caption, !caption.isEmpty {
            return "\(presentation.title)\n\(caption)"
        }
        return presentation.title
    }

    var body: some View {
        GeometryReader { proxy in
            let fold = proxy.reservedRegions(kind: .division).first(where: { $0.isActive })?.frame
            if let fold, fold.width > fold.height {
                tabletopLayout(fold: fold, size: proxy.size)
            } else {
                standardLayout
            }
        }
        .statusBarHidden(!showChrome)
        .preferredColorScheme(.dark)
    }

    /// Normal full-screen viewer with floating glass controls.
    private var standardLayout: some View {
        ZStack {
            Color.black
                .opacity(1 - min(abs(dragY) / 500, 0.7))
                .ignoresSafeArea()
            content
                .offset(y: dragY)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
        }
        .simultaneousGesture(dismissDrag, including: zoomed ? .subviews : .all)
        .overlay(alignment: .top) {
            if showChrome {
                topBar
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if showChrome {
                captionView
                    .transition(.opacity)
            }
        }
    }

    /// iPhone Duo half-folded like a laptop: media above the fold, controls and caption below it.
    private func tabletopLayout(fold: CGRect, size: CGSize) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                content
            }
            .frame(height: max(fold.minY, 0))
            .clipped()

            Color.black
                .frame(height: fold.height)

            VStack(spacing: 14) {
                topBar
                captionView
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity)
            .frame(height: max(size.height - fold.maxY, 0))
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var captionView: some View {
        Text(caption)
            .font(.subheadline)
            .foregroundStyle(.white)
            .lineLimit(4)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch presentation.media {
        case .images(let images):
            if images.count == 1 {
                ZoomableImage(url: images[0].url, zoomed: $zoomed)
            } else {
                TabView(selection: $index) {
                    ForEach(Array(images.enumerated()), id: \.offset) { pair in
                        ZoomableImage(url: pair.element.url, zoomed: $zoomed)
                            .tag(pair.offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: index) { saveStatus = .idle }
            }
        case .video(let url, let isGif):
            LoopingPlayer(url: url, loop: isGif)
        case .link, .none:
            EmptyView()
        }
    }

    private var topBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)

                Spacer(minLength: 0)

                if images.count > 1 {
                    Text("\(index + 1) / \(images.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .capsule)
                }

                Spacer(minLength: 0)

                if let url = currentURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.headline)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                }

                if !images.isEmpty {
                    Button {
                        save()
                    } label: {
                        Image(systemName: saveIcon)
                            .font(.headline)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .disabled(saveStatus == .saving)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var saveIcon: String {
        switch saveStatus {
        case .idle: return "arrow.down.to.line"
        case .saving: return "ellipsis"
        case .saved: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if abs(value.translation.height) > abs(value.translation.width) {
                    dragY = value.translation.height
                }
            }
            .onEnded { _ in
                if abs(dragY) > 140 {
                    dismiss()
                } else {
                    withAnimation(.spring) { dragY = 0 }
                }
            }
    }

    private func save() {
        guard let url = currentURL else { return }
        saveStatus = .saving
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else {
                    saveStatus = .failed
                    return
                }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                saveStatus = .saved
            } catch {
                saveStatus = .failed
            }
        }
    }
}

struct ZoomableImage: View {
    let url: URL
    @Binding var zoomed: Bool

    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else if phase.error != nil {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(scale * pinch)
        .offset(offset)
        .gesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in
                    state = value.magnification
                }
                .onEnded { value in
                    let next = min(max(scale * value.magnification, 1), 5)
                    withAnimation(.spring) {
                        scale = next
                        if next == 1 {
                            offset = .zero
                            baseOffset = .zero
                        }
                    }
                    zoomed = next > 1
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    offset = CGSize(width: baseOffset.width + value.translation.width,
                                    height: baseOffset.height + value.translation.height)
                }
                .onEnded { _ in
                    baseOffset = offset
                },
            including: scale > 1 ? .all : .subviews
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring) {
                if scale > 1 {
                    scale = 1
                    offset = .zero
                    baseOffset = .zero
                } else {
                    scale = 2.5
                }
            }
            zoomed = scale > 1
        }
    }
}

struct LoopingPlayer: View {
    let url: URL
    let loop: Bool
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                try? AVAudioSession.sharedInstance().setCategory(.playback)
                let player = AVPlayer(url: url)
                player.isMuted = loop
                player.play()
                self.player = player
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
                guard loop, let item = note.object as? AVPlayerItem, item == player?.currentItem else { return }
                player?.seek(to: .zero)
                player?.play()
            }
    }
}
