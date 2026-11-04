import SwiftUI

/// Root of the Home tab. On a wide screen (iPhone Duo inner display) it's a two-pane
/// browser: feed on the left, the selected post and its comments on the right. On a
/// normal iPhone it falls back to a single navigation stack.
struct HomeRoot: View {
    @State private var router = Router()
    @AppStorage("openLinksInApp") private var openLinksInApp = true
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        Group {
            if hSize == .regular {
                SplitBrowser()
            } else {
                NavigationStack(path: $router.path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { route in
                            RouteView(route: route)
                        }
                }
            }
        }
        .environment(router)
        .environment(\.openURL, OpenURLAction { url in
            router.open(url, inApp: openLinksInApp)
        })
        .sheet(item: $router.safari) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
        .fullScreenCover(item: $router.media) { presentation in
            MediaViewer(presentation: presentation)
        }
    }
}

struct SplitBrowser: View {
    @Environment(Router.self) private var router
    @Environment(AuthManager.self) private var auth

    @State private var source: FeedSource = .home
    @State private var selected: Post?
    @Namespace private var chips

    private let sources: [FeedSource] = [.home, .popular, .all]

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            FeedView(
                source: source,
                initialSort: source == .home && auth.isLoggedIn ? .best : .hot,
                onSelect: { post in
                    router.path = NavigationPath()
                    selected = post
                },
                selectedName: selected?.name
            )
            .id([source.key, String(auth.isLoggedIn)])
            .safeAreaInset(edge: .top) { chipRow }
            .navigationSplitViewColumnWidth(min: 360, ideal: 430, max: 540)
        } detail: {
            NavigationStack(path: $router.path) {
                detailRoot
                    .navigationDestination(for: Route.self) { route in
                        RouteView(route: route)
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detailRoot: some View {
        if let selected {
            PostDetailView(post: selected, preferStacked: true)
                .id(selected.name)
        } else {
            ZStack {
                AmbientBackground()
                ContentUnavailableView("Pick a post",
                                       systemImage: "sidebar.right",
                                       description: Text("Choose a post on the left to read it and its comments here."))
            }
        }
    }

    private var chipRow: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(sources, id: \.self) { option in
                    Button {
                        withAnimation(.bouncy) { source = option }
                    } label: {
                        Label(option.title, systemImage: option.icon)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        source == option
                            ? .regular.tint(Color.accentColor.opacity(0.55)).interactive()
                            : .regular.interactive(),
                        in: .capsule
                    )
                    .glassEffectID(option.key, in: chips)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}
