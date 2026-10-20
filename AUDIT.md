# BlindRSS to iOS — Audit

Source: `/mnt/c/Users/admin/git/BlindRSS` (Python 3.14, wxPython desktop app, MIT).
Target: this repo, `blindRSS-iOS` (was empty at audit time).
Accessibility reference: [ios-swiftui-accessibility-techniques](https://github.com/cvs-health/ios-swiftui-accessibility-techniques) by CVS Health (SKILL.md, 45 a11y-check rules, 24 WCAG 2.2 criteria; Rotor, Accessibility Actions, Adjustable Action, Magic Tap, Lists docs).

## What the desktop app is

A screen-reader-first RSS and podcast client for Windows, macOS, and Linux. It is not a small RSS reader. The audit found roughly 60 core modules, 16 GUI modules, and 8 provider modules.

### Data model (from core/models.py and core/db.py)

Desktop SQLite file `rss.db`. The iOS port mirrors these tables as SwiftData models.

- `feeds`: id, url, title, title_is_custom, category, icon_url. In code, `Feed` also carries `language` (BCP-47) and a transient `unread_count`.
- `articles`: id, feed_id, title, url, content, description, date, author, is_read, is_favorite, media_url, media_type, chapter_url, opened_at.
- `categories`: id, title (unique). Categories can nest (parent path strings) in the local provider.
- `chapters`: id, article_id, start, title, href.
- `deleted_articles`: tombstone plus full snapshot, so deletes can be restored and refresh never resurrects a deleted item.
- `playback_state`: id (media/article id), position_ms, duration_ms, updated_at, completed, title. Resume playback depends on this.
- `smart_folders`: id, name, rule_json, position. Rule-based virtual folders.
- `filter_rules`: id, name, rule_json, actions_json, enabled, stop, position.
- `article_labels`, `article_versions`, `podcast_archive_state`, `youtube_history_state`, hosted archive sidecars, feed error tracking (last_error, consecutive_failures), and per-feed settings.

### Providers (from providers/base.py)

Abstract `RSSProvider` contract: refresh, refresh_feed, get_feeds, get_articles (plus paged variant), mark_read, mark_unread, mark_all_read, add_feed, remove_feed, get/add/rename/delete categories, import/export OPML, favorites, feed errors, full-content fetch, chapters, article delete/restore, smart folders.

Implementations: Local (full RSS/Atom/JSON Feed parsing, conditional GET, per-feed intervals), Miniflux, Inoreader, The Old Reader, BazQux, hosted podcast archive, YouTube account.

### Feature inventory (from README.md and docs/help/en.md)

- Local feeds plus hosted providers listed above.
- All / Unread / Read / Favorites views, mark read/unread, mark all read, search, sorting, article list columns.
- Smart Folders, saved searches, Feeds with Errors view, filter rules, Deleted Articles view with restore.
- Full-text recovery when a feed ships only summaries; rich full-text view; accessible browser.
- YouTube videos as articles with description, transcript, chapters; Reddit, Lemmy, Groups.io, Google Groups threads.
- Feed discovery: Apple Podcasts, gPodder, Feedly, NewsBlur, Feedspot, Reddit, Fediverse, Feedsearch, local discovery. Subscribes to YouTube, Mastodon, Bluesky, PieFed, SoundCloud, Mixcloud.
- OPML import/export, YouTube Takeout import.
- Media: podcast and video enclosures via VLC, local range-cache proxy, playback speed, equalizer, silence skipping, chapters, soundcard selection, downloads.
- Casting via Caster: Chromecast, AirPlay, DLNA/UPnP, Sonos, Roku, Kodi.
- 67 remappable keyboard commands (core/shortcuts.py), grouped Feeds, Articles, View, Player, Play Queue, Playback Speed, Tools, Help. Context-sensitive F1 help with an offline user guide.
- Tray controls, media keys, startup restore of last feed and folder, notifications, 15 translations, signed auto-updater.

## Port plan

### Phase 1 (this delivery): local-first iOS app

Native SwiftUI app, iOS 17+, SwiftData persistence mirroring the desktop schema above, URLSession fetching, XMLParser-based RSS/Atom parsing plus JSON Feed, OPML import/export, AVPlayer playback with resume, chapters, speed control, and a play queue. Views mirror the desktop layout: feed and folder list, article list, reading pane, article window, search, status announcements.

Desktop keyboard commands map to iOS as follows: menus and buttons for sighted use, VoiceOver custom actions and swipe actions for blind use (next section), Magic Tap for play/pause, and hardware-keyboard shortcuts (Command-N, Command-R, Command-1 to 6 filters, and so on) for iPad and Mac Catalyst keyboards, reusing the desktop command ids from core/shortcuts.py.

### Phase 2 (implemented in 0.1.0)

- Hosted providers: Miniflux REST client plus one Google Reader API client covering Inoreader, The Old Reader, and BazQux (Services/Providers.swift). Accounts live in Settings, Online Account. Items mirror into the local library with provider-prefixed ids.
- Full-text recovery: Fetch Full Text in the reader keeps the longer of feed text and recovered page text (Services/Downloads.swift, FullTextService).
- Feed discovery: subscribing to a web page URL finds its advertised feed (FullTextService.discoverFeeds).
- Smart Folders and Filter Rules: models in Models/Models.swift, editors in Views/ManageViews.swift. Filter rules (mark read, favorite, delete) apply as articles arrive.
- Deleted Articles view with restore and permanent delete; feed properties editing; article media filter and sort; copy link; downloads.
- YouTube: channel feeds parse as RSS; video articles play in the embedded player and chapters are parsed from description timestamps (Services/YouTube.swift). Direct stream resolution (desktop yt-dlp) has no iOS equivalent; the embed player is the iOS answer.
- Downloads play offline through AVPlayer, or through the equalizer engine (five-band EQ plus silence skipping, Services/EnginePlayer.swift) from the Downloads view.
- Podcast parity (0.1.0): chapters come from Podcasting 2.0 chapters JSON and inline feed chapters; resume uses SwiftData PlaybackState with the desktop rules (save every 15 seconds, rewind 10 on resume, last minute counts as finished); the play queue persists across restarts, auto-advances, and marks finished episodes read; lock-screen/headphone remote commands and background audio are wired; volume, desktop speed preset steps, and a sleep timer are in the player; auto-download after refresh honors the desktop max_downloads limit; Find a Podcast searches Apple Podcasts; Podcast Archive recovers back catalogues from the Wayback Machine with batch download. Streaming EQ remains download-only, since AVPlayer has no equalizer graph.
- Casting: AirPlay route picker in the equalizer player and system player. Chromecast and DLNA need Google's Cast SDK and a Cast application id; that is the one desktop feature not ported, because it cannot ship without the owner's Cast credentials.
- Notifications for new articles after refresh (Settings toggle), announcements for all major state changes.
- Translations: not ported. The desktop catalogs are gettext files for 15 languages; iOS needs String Catalogs. English ships in 0.1.0.

## VoiceOver design (from the CVS Health techniques repo)

Rules applied from SKILL.md and the technique docs:

- Every interactive element has a meaningful label, 1 to 3 words, starting with visible text, never containing the control type ("button", "link"). Icon-only buttons always get `.accessibilityLabel`.
- `.accessibilityHint` is required wherever swipe actions, long press, or context menus exist, because VoiceOver users cannot discover them otherwise. Hints are third-person, describe the result, end with a period, and never name the gesture.
- Article rows combine icon and text with `.accessibilityElement(children: .combine)` into one VoiceOver element: title, feed, date, read state, favorite state, and "has audio" are spoken once, in that order.
- Section headings carry `.accessibilityAddTraits(.isHeader)` so the Rotor can jump by heading. Custom Rotors ("Unread", "Favorites", "With Audio") use `.accessibilityRotor` so a two-finger rotate plus swipe moves between matching articles without swiping past everything.
- Swipe parity: every List `.swipeActions` action is duplicated as a VoiceOver `.accessibilityAction(named:)` on the same row. A blind user who cannot perform the touch swipe gets the identical action set. Article actions: Mark Read/Unread, Favorite, Play, Share, Open in Browser, Delete. Feed actions: Refresh, Mark All Read, Edit, Delete.
- Player progress and playback speed use `.accessibilityAdjustableAction` (swipe up/down with VoiceOver to change value) with `.accessibilityValue` spoken as "12 minutes of 43" and "1.25 times".
- Magic Tap (two-finger double tap) toggles play/pause anywhere via `.accessibilityAction(.magicTap)`.
- State changes announce with `UIAccessibility.post(notification: .announcement, ...)`: refresh completion counts, mark-all-read, deletions, and playback errors. Screen changes use `.screenChanged`, partial changes `.layoutChanged`.
- Sheets and modals return VoiceOver focus to their trigger with `@AccessibilityFocusState` on dismiss.
- Dynamic Type: text styles only, no fixed point sizes, no `.lineLimit(1)`, scrollable reader. Semantic colors only (`.primary`, `.secondary`), 44pt minimum touch targets, `.navigationTitle` on every pushed view, Reduce Motion respected, no orientation lock.

## Distribution decision

Distribution is GitHub Releases plus the serrebiALT AltStore source (https://github.com/serrebidev/serrebiALT). Builds are unsigned; AltStore re-signs on install. No App Store or TestFlight in 0.1.0.

## Verification

Built and tested by GitHub Actions on macos-15 (unit tests on a simulator, a11y-check report attached to build artifacts, unsigned IPA). This workspace is WSL2 with no Xcode, so local verification is structural only. A VoiceOver pass on a real device is still recommended before announcing.
