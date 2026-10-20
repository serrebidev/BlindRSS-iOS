# Changelog

## 0.1.3

- Fix feeds, Unread, All Articles, and the other library views not opening on iPhone. The sidebar rows were buttons that changed state, but on iPhone the split view only moves to the next screen when its list selection changes, so nothing opened. All Articles was already the default, so tapping it changed nothing at all. Rows now use list selection.
- Fix articles not opening in the reader, for the same reason. Opening an article still marks it read, now without a spoken "Marked as read" each time.
- Choosing a different feed or view now starts with no article open, instead of jumping back to the previous article.

## 0.1.2

- Fix high CPU use that 0.1.1 did not solve. The feed list rebuilt unread counts for the whole library about three times per feed on every update, so a 698-feed account did thousands of full-library passes each time anything changed. Counts are now built once per update.
- Refresh All no longer fetches every Miniflux or Google Reader feed URL directly. Hosted feeds refresh through the account, so a large account is a few requests instead of hundreds, and articles are no longer duplicated by refresh.
- Refresh saves every 25 feeds instead of after each one, and only writes article fields that actually changed, so unchanged articles stop re-rendering the lists.
- The main window no longer loads the whole library just to restore the play queue. The article list filters once per update instead of five times. Feed dates parse with shared formatters, and chapter loading fetches one article instead of the whole table.

## 0.1.1

- Fix Miniflux sync never finishing with large accounts. Sync used to fetch entries feed by feed (698 sequential requests on the reference account). It now uses the global entries endpoint, newest 2,000 entries in pages of 500, with progress announcements.
- Bare server addresses like rss.example.com now get https:// automatically.
- Sync failures are shown and announced instead of failing silently.
- Lower CPU use in Miniflux sync, refresh, and adding feeds: constant-time article lookups instead of linear scans, JSON decoding and feed parsing off the main thread, 8 feeds refreshed at once, and single-pass unread counts in lists. Details in docs/CPU-AUDIT.md.

## 0.1.0

First iOS release. Native SwiftUI port of BlindRSS for desktop.

- RSS, Atom, and JSON Feed subscriptions with categories, stored locally with SwiftData.
- All, Unread, Read, and Favorites views. Mark read and unread, mark all read, favorites, delete with restore snapshots, and per-feed error tracking.
- OPML import and export.
- Podcasting fully supported: enclosures stream or download, Podcasting 2.0 chapters (JSON documents and inline feed chapters), resume playback with the desktop 10-second rewind and last-minute completion rule, a persistent play queue that auto-advances and survives restarts, lock-screen and headphone remote controls, background audio, volume, speed presets (0.5x to 3x), a sleep timer, auto-download with a configurable limit, one combined Search Feeds and Podcasts (Apple Podcasts plus gPodder by name, feed detection and feedsearch for pasted URLs), and Wayback Podcast Archive recovery with batch download.
- Hosted providers: Miniflux, Inoreader, The Old Reader, and BazQux sync in Settings, Online Account.
- Smart Folders, Filter Rules, Deleted Articles with restore, feed properties, article media filter and sorting, copy link.
- Downloads with offline playback, a five-band equalizer player, and silence skipping. Full-text recovery and feed discovery from web page URLs.
- YouTube articles with embedded playback and chapters from description timestamps. AirPlay output picker. Notifications for new articles.
- VoiceOver first: every touch swipe action is duplicated as a VoiceOver action on the same row. Articles offer Read, Mark Read or Unread, Favorite, Play, Add to Play Queue, Open in Browser, and Delete. Feeds offer Open, Refresh, Mark All Read, and Delete.
- Rotors for Headings, Unread, Favorites, With Audio, and Chapters. Magic Tap toggles playback anywhere. Player progress and speed are adjustable by VoiceOver swipe.
- Refresh, deletion, and playback changes are announced to VoiceOver.
