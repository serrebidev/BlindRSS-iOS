# BlindRSS for iOS

Native SwiftUI port of [BlindRSS](https://github.com/serrebidev/BlindRSS), the screen-reader-first desktop RSS and podcast client. Built for VoiceOver first, following [ios-swiftui-accessibility-techniques](https://github.com/cvs-health/ios-swiftui-accessibility-techniques) by CVS Health.

Current release: 0.1.0. This is the first public iOS build. Expect rough edges; the desktop app remains the full-featured one.

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

Also included: hosted providers (Miniflux, plus Inoreader, The Old Reader, and BazQux over the Google Reader API) in Settings, Online Account; Smart Folders; Filter Rules that mark read, favorite, or delete as articles arrive; a Deleted Articles view with restore; feed properties editing; full-text recovery; feed discovery from web page URLs; media downloads with an equalizer player (five-band EQ and silence skipping); YouTube articles with an embedded player and description chapters; AirPlay; and notifications for new articles.

Not ported: Chromecast and DLNA casting (needs Google's Cast SDK and a Cast application id), direct YouTube stream extraction (no yt-dlp on iOS; videos play in the embedded player), and translations (desktop gettext catalogs need converting to String Catalogs). See [AUDIT.md](AUDIT.md).

## VoiceOver

Every touch swipe action is duplicated as a VoiceOver action on the same row. Articles offer Read, Mark Read or Unread, Favorite, Play, Add to Play Queue, Open in Browser, and Delete. Feeds offer Open, Refresh, Mark All Read, and Delete.

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
