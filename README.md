# BlindRSS for iOS

Native SwiftUI port of [BlindRSS](https://github.com/serrebidev/BlindRSS), the screen-reader-first desktop RSS and podcast client. Built for VoiceOver first, following [ios-swiftui-accessibility-techniques](https://github.com/cvs-health/ios-swiftui-accessibility-techniques) by CVS Health.

Current release: 0.1.12. The 0.1.12 release closes the feature gap with the desktop app (v2.5.x): everything portable to iOS is now here.

## Install with AltStore

BlindRSS is in the serrebiALT source.

1. In AltStore, open Sources, tap Add, and paste:

   https://raw.githubusercontent.com/serrebidev/serrebiALT/main/apps.json

2. Find BlindRSS in the source and install it. AltStore re-signs the app with your account, so no developer certificate is needed.

You can also download the `.ipa` directly from [Releases](https://github.com/serrebidev/BlindRSS-iOS/releases) and install it with AltStore, SideStore, or another sideloader.

## What works

- RSS, Atom, and JSON Feed subscriptions, grouped by category, stored on device with SwiftData.
- All, Unread, Read, and Favorites views. Mark read and unread, mark all read, favorites, search, and delete with restore snapshots.
- Per-feed error tracking with a Feeds with Errors view.
- OPML import and export.
- Podcasting fully supported, matching the desktop player: enclosure streaming and downloads, Podcasting 2.0 chapters from feeds, resume playback, persistent auto-advancing play queue, lock-screen controls, background audio, volume, speed presets, sleep timer, auto-download, one combined Search Feeds and Podcasts (Apple Podcasts and gPodder by name, feed detection for pasted URLs), and Wayback archive recovery with batch download.
- Feed refresh with VoiceOver announcements of new article counts.

Also included: hosted providers (Miniflux, plus Inoreader, The Old Reader, and BazQux over the Google Reader API) in Settings, Online Account; Smart Folders; Filter Rules with the desktop's full action set (mark read, favorite, delete, do not notify, move to a category, label, stop) applied as a pipeline as articles arrive; a Deleted Articles view with restore; feed properties editing with per-feed notification mute, the feed's published description, and Reset Title; full-text recovery; feed discovery from web page URLs; media downloads; a ten-band equalizer with the desktop presets and silence skipping for streamed and downloaded episodes; YouTube articles with an embedded player, description chapters, and a readable transcript; AirPlay; and notifications for new articles.

New in 0.1.12 (desktop parity): discovery across every keyless desktop directory (fyyd, Podverse, Feedly, NewsBlur, Reddit, Lemmy, Mastodon, Bluesky, PieFed, Groups.io, Feedspot, Google News, Bing News) grouped by source; social page URLs resolve to feeds when subscribing (Mastodon, Bluesky, Reddit, Lemmy, Groups.io, GitHub, YouTube channels and playlists); YouTube Takeout ZIP import; Persistent Searches in the feed list; browsable Categories with rename and delete; article retention; delete behaviour (Deleted Articles, permanent, or move to a category) with an optional confirmation; reader presentation options (bullets, quote markers, link targets, image alt text) and a search-scope setting; last-view restoration at launch; a built-in User Guide; Open Article by URL and Open Media URL; and Site Cookies import.

New in 0.1.17 (Apple Intelligence, iOS 26 on a supported device; private, on device, no account): Summarize, Key Points, and Ask about this article in the reader; Brief Me on the newest unread articles in any list; a Summarize action on every article row; Siri and Shortcuts ("Brief me with BlindRSS", "Summarize an article in BlindRSS", "Ask BlindRSS about an article", "How many unread articles in BlindRSS", "Refresh BlindRSS", "Add a feed to BlindRSS"); Siri onscreen awareness of the open article; recent articles in Spotlight; visual intelligence search of article titles; Writing Tools on article text; and Apple's on-device translation tried before the public translation services. On older systems the app works as before and Settings says why the features are missing.

Not ported: Chromecast and DLNA casting (needs Google's Cast SDK and a Cast application id), direct YouTube stream extraction and stream-resolved features (no yt-dlp on iOS; videos play in the embedded player), and translations (desktop gettext catalogs need converting to String Catalogs). See [AUDIT.md](AUDIT.md).

## VoiceOver

Every touch swipe action is duplicated as a VoiceOver action on the same row. Articles offer Open in Browser, Download Media, Copy Link, Read, Mark Read or Unread, Favorite, Play, Add to Play Queue, Share, and Delete, in an order you can change in Settings, Article Actions. Feeds offer Open, Refresh, Mark All Read, and Delete.

The full gesture guide is in [docs/VOICEOVER.md](docs/VOICEOVER.md). The short version:

- Swipe right and left to move. Each article speaks title, feed, date, read state, favorite state, and "has audio" once.
- Swipe up or down on an article or feed to cycle its actions, then double tap.
- Two-finger rotate for the rotor: Headings, Unread, Favorites, With Audio, and Chapters.
- Magic Tap, a two-finger double tap, plays or pauses anywhere.
- In the player, focus Progress or Playback speed and swipe up or down to adjust.

## Documentation

- [AUDIT.md](AUDIT.md) — desktop audit, data model map, feature inventory, port plan, VoiceOver design rules, and open decisions.
- [docs/VOICEOVER.md](docs/VOICEOVER.md) — complete VoiceOver gesture guide.
- [CHANGELOG.md](CHANGELOG.md) — release notes by version.
- [docs/CPU-AUDIT.md](docs/CPU-AUDIT.md) — CPU audit of Miniflux sync, refresh, and adding feeds, with the 0.1.1 fixes.

## Build (Mac required)

CI builds and releases the app. To build locally:

1. Open `BlindRSS.xcodeproj` in Xcode 16 or later.
2. Run on a device or simulator (iOS 17 or later). Unsigned CI builds are produced with `CODE_SIGNING_ALLOWED=NO`; AltStore re-signs on install.

Run the accessibility checker from the techniques repo against the sources:

```bash
brew tap cvs-health/ios-swiftui-accessibility-techniques https://github.com/cvs-health/ios-swiftui-accessibility-techniques.git
brew install --HEAD cvs-health/ios-swiftui-accessibility-techniques/a11y-check
a11y-check BlindRSS
```

CI runs the same check on every push and attaches the report to the build artifacts. Unit tests cover the feed parsers, HTML text, and OPML. Run them with Command-U on a Mac, or in CI.

## Layout

- `BlindRSS/Models` — SwiftData models mirroring the desktop `rss.db` schema.
- `BlindRSS/Services` — feed parsing (RSS, Atom, JSON Feed), library store, OPML, AVPlayer playback, VoiceOver announcements.
- `BlindRSS/Views` — feed list, article list, reader, player, add feed, settings.
- `BlindRSSTests` — parser, HTML text, and OPML unit tests.
- `.github/workflows/build.yml` — tests, accessibility check, unsigned IPA, and tag releases.

## License

MIT, same as the desktop app. See [LICENSE](LICENSE).
