# Changelog

## 0.1.0

First iOS release. Native SwiftUI port of BlindRSS for desktop.

- RSS, Atom, and JSON Feed subscriptions with categories, stored locally with SwiftData.
- All, Unread, Read, and Favorites views. Mark read and unread, mark all read, favorites, delete with restore snapshots, and per-feed error tracking.
- OPML import and export.
- Podcasting fully supported: enclosures stream or download, Podcasting 2.0 chapters (JSON documents and inline feed chapters), resume playback with the desktop 10-second rewind and last-minute completion rule, a persistent play queue that auto-advances and survives restarts, lock-screen and headphone remote controls, background audio, volume, speed presets (0.5x to 3x), a sleep timer, auto-download with a configurable limit, Apple Podcasts search, and Wayback Podcast Archive recovery with batch download.
- Hosted providers: Miniflux, Inoreader, The Old Reader, and BazQux sync in Settings, Online Account.
- Smart Folders, Filter Rules, Deleted Articles with restore, feed properties, article media filter and sorting, copy link.
- Downloads with offline playback, a five-band equalizer player, and silence skipping. Full-text recovery and feed discovery from web page URLs.
- YouTube articles with embedded playback and chapters from description timestamps. AirPlay output picker. Notifications for new articles.
- VoiceOver first: every touch swipe action is duplicated as a VoiceOver action on the same row. Articles offer Read, Mark Read or Unread, Favorite, Play, Add to Play Queue, Open in Browser, and Delete. Feeds offer Open, Refresh, Mark All Read, and Delete.
- Rotors for Headings, Unread, Favorites, With Audio, and Chapters. Magic Tap toggles playback anywhere. Player progress and speed are adjustable by VoiceOver swipe.
- Refresh, deletion, and playback changes are announced to VoiceOver.
