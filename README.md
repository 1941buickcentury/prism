# Prism

A Reddit client for iOS 27.1 in the spirit of Boost and Apollo, built in SwiftUI with Liquid Glass throughout and native iPhone Duo support. It uses your own approved Reddit API client ID.

> Reddit plans to close public API access for third-party apps in March 2027. Prism stops working when that happens.

## What's in it

- **Feeds:** Home, Popular, All and any subreddit, with Best/Hot/New/Top/Rising/Controversial sorting and time ranges. Floating glass chips switch between Home, Popular and All.
- **Posts:** glass cards with images, galleries, videos and link previews. Swipe right to upvote or downvote, left to save. NSFW and spoilers blur until tapped.
- **Comments:** threaded with Apollo-style colored depth bars. Tap to collapse, swipe to vote or reply, long-press for more. Hidden replies and long threads load in place. The post's vote, reply, save and share buttons float in a Liquid Glass bar at the bottom.
- **Media viewer:** full screen, pinch and double-tap zoom, swipe between gallery images, swipe down to close, save to Photos, share. Reddit videos play with sound; GIFs loop.
- **Login:** OAuth with your client ID. Browsing works logged out too.
- **Inbox:** inbox, unread and sent, with unread count on the tab, mark read and reply.
- **Profile:** your posts, comments, saved and upvoted items; other users' profiles too.
- **Search:** posts and communities, plus quick "Go to r/…" jumps.
- **Settings:** API keys, accent color, compact layout, glass cards on/off, NSFW blur, default comment sort, open links in app.

### iPhone Duo

- **Inner display:** the Home feed becomes a two-pane browser — the feed on the left, the selected post and its comments on the right — so picking a post opens it beside the list instead of covering it. The tab bar can become a sidebar.
- **Posts:** on the inner display the post and its comments sit side by side, using iOS 27.1's `ArrangementView` split so each pane gets its own side of the fold.
- **Tabletop pose:** half-fold the Duo while viewing an image or video and the media moves above the fold, with the controls and caption below it.
- **Outer display:** the normal iPhone layout.
- **Split View and multiple windows:** Prism resizes to any width and can open two windows side by side.

## 1. Check your Reddit app

At [reddit.com/prefs/apps](https://www.reddit.com/prefs/apps), open your approved app (it should be an **installed app**, which has no secret). Note:

- the **client ID**: the string under the app name
- the **redirect URI**

Prism handles either kind of redirect URI:

- A custom scheme like `prism://auth` logs in through the iOS system sheet, which can reuse your Safari login.
- An `http(s)://` URI logs in through an in-app web page that catches the redirect. Use this if the same app is still set up in Boost and you don't want to change its redirect.

## 2. Build it in the cloud

1. Create a GitHub repository and push this folder to it. A public repo gets free macOS build minutes; a private one uses your monthly allowance quickly, since macOS minutes count 10×. There are no secrets in the code; your client ID is typed into the app, not stored in the repo.
2. Each push to `main` runs **Build Prism** under the repo's **Actions** tab, on GitHub's Xcode 27 runner. It checks for the iOS 27.1 SDK first and stops with a clear message if the runner doesn't have it. You can also start it by hand with **Run workflow**.
3. When it finishes, download the **Prism-ipa** artifact and unzip it to get `Prism.ipa`.

If the build fails, download the **build-log** artifact. The errors are near the end.

### Screenshots

To get real screenshots from each build, add your client ID as a repository secret: **Settings › Secrets and variables › Actions › New repository secret**, named `REDDIT_CLIENT_ID`. A second job then runs Prism in the iPhone and iPhone Duo simulators, logged out, and saves the feed, a post, the media viewer and a subreddit in light and dark mode as the **Prism-screenshots** artifact. Without the secret, that job is skipped.

## 3. Install on your iPhone from Windows

1. Install [Sideloadly](https://sideloadly.io). It needs the iTunes and iCloud apps from Apple's website, not the Microsoft Store versions.
2. Plug in the iPhone, drag `Prism.ipa` into Sideloadly, enter your Apple ID and start.
3. On the iPhone, turn on **Settings › Privacy & Security › Developer Mode** (it restarts), then trust your Apple ID under **Settings › General › VPN & Device Management**.

With a free Apple ID, sideloaded apps expire after 7 days. Re-sideload to refresh; your login and settings carry over. A paid developer account extends that to a year.

Prism requires iOS 27.1 or later on the phone.

## 4. First launch

Enter your client ID and redirect URI, tap **Continue**, then log in from the **Profile** tab.

## Project layout

```
project.yml                   XcodeGen spec (the .xcodeproj is generated in CI)
.github/workflows/build.yml   Cloud build that produces the unsigned .ipa
Prism/App                     App entry, tabs, per-tab navigation
Prism/Core                    Models, Reddit API client, OAuth, votes/saves, routing
Prism/UI                      Background, glass cards, markdown, shared bits
Prism/Features                Feed, Post + comments, Media, Subreddits, Inbox, Profile, Search, Settings
```

To build on a Mac instead: `brew install xcodegen && xcodegen generate`, then open `Prism.xcodeproj` in Xcode 27.1 or later.
