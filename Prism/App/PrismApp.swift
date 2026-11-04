import SwiftUI

@main
struct PrismApp: App {
    @State private var auth: AuthManager
    @State private var client: RedditClient
    @State private var actions: ActionStore

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
        let auth = AuthManager()
        let client = RedditClient(auth: auth)
        _auth = State(initialValue: auth)
        _client = State(initialValue: client)
        _actions = State(initialValue: ActionStore(client: client))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(client)
                .environment(actions)
        }
    }
}

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(RedditClient.self) private var client
    @Environment(ActionStore.self) private var actions
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = actions
        Group {
            if auth.isConfigured {
                MainTabView()
            } else {
                SetupView()
            }
        }
        .task(id: auth.isLoggedIn) {
            await client.refreshAccount()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await client.refreshAccount() }
            }
        }
        .alert("Log in to do that", isPresented: $store.needsLogin) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Voting, saving and replying need your Reddit account. Log in from the Profile tab.")
        }
    }
}

struct MainTabView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeRoot()
            }
            Tab("Subreddits", systemImage: "square.stack.3d.up.fill") {
                TabRoot { SubredditsView() }
            }
            Tab("Inbox", systemImage: "tray.fill") {
                TabRoot { InboxView() }
            }
            .badge(auth.account?.inboxCount ?? 0)
            Tab("Profile", systemImage: "person.crop.circle.fill") {
                TabRoot { ProfileView() }
            }
            Tab(role: .search) {
                TabRoot { SearchView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// Each tab gets its own navigation stack, link handling, in-app browser and media viewer.
struct TabRoot<Content: View>: View {
    @State private var router = Router()
    @AppStorage("openLinksInApp") private var openLinksInApp = true
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            content
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
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

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .feed(let source):
            if case .subreddit(let name) = source {
                SubredditView(name: name)
            } else {
                FeedView(source: source)
            }
        case .post(let post):
            PostDetailView(post: post)
        case .postID(let id, let focus):
            PostDetailView(id: id, focus: focus)
        case .user(let name):
            UserView(name: name, isSelf: false)
        case .message(let message):
            MessageDetailView(message: message)
        case .settings:
            SettingsView()
        }
    }
}
