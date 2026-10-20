# Changelog

## 1.0.0

First iOS release. Native SwiftUI port of BlindRSS for desktop.

- RSS, Atom, and JSON Feed subscriptions with categories, stored locally with SwiftData.
- All, Unread, Read, and Favorites views. Mark read and unread, mark all read, favorites, delete with restore snapshots, and per-feed error tracking.
- OPML import and export.
- Podcast and video playback with AVPlayer: resume, chapters, playback speed, play queue, and AirPlay.
- VoiceOver first: every touch swipe action is duplicated as a VoiceOver action on the same row. Articles offer Read, Mark Read or Unread, Favorite, Play, Add to Play Queue, Open in Browser, and Delete. Feeds offer Open, Refresh, Mark All Read, and Delete.
- Rotors for Headings, Unread, Favorites, With Audio, and Chapters. Magic Tap toggles playback anywhere. Player progress and speed are adjustable by VoiceOver swipe.
- Refresh, deletion, and playback changes are announced to VoiceOver.
