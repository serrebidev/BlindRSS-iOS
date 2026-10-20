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

### Phase 2 (documented, not in this delivery)

Hosted providers (Miniflux first — it matches the desktop default provider in config.json — then Inoreader, The Old Reader, BazQux), full-text extraction parity, YouTube/Rumble/Odysee resolution (yt-dlp has no iOS equivalent; needs a server or a different resolver), filter rules engine, Smart Folder rule editor, casting beyond AirPlay (AVFoundation gives AirPlay natively; Chromecast/DLNA need third-party SDKs), silence skipping and equalizer (need an AVAudioEngine pipeline), feed discovery directories, and translations.

Nothing in Phase 2 is silently dropped: each item needs a decision, listed at the end of this file.

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

## Decisions needed before Phase 2

1. Hosted providers: ship Miniflux only, or all four hosted providers? Desktop defaults to Miniflux.
2. Media resolution: YouTube/Rumble/Odysee need a resolver story on iOS (no yt-dlp). Options: skip, server-side resolver, or audio-only via public instances.
3. Casting: AirPlay only, or add Google Cast SDK (third-party dependency, privacy review)?
4. Distribution: App Store, TestFlight only, or sideload? Affects background refresh and file access entitlements.

## Verification limits

This workspace is WSL2 on Windows: no Xcode, no swift toolchain, no simulator. The project is delivered as a complete Xcode project plus a SwiftData/SwiftUI source tree that must be opened on a Mac to build. Structural checks (project file balance, file inventory, cross-references) were run here; a Mac build and a VoiceOver pass on device are still required. See README.md in this repo for the Mac steps.
