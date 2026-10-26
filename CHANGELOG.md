# Changelog

## 0.1.12

Desktop parity release: BlindRSS for iOS now matches the desktop app (v2.5.x) on everything portable to iOS.

- Discovery searches every keyless desktop directory at once: Apple Podcasts and gPodder, plus fyyd, Podverse, Feedly, NewsBlur, Reddit, Lemmy, Mastodon, Bluesky, PieFed, Groups.io, Feedspot, and Google News and Bing News search feeds, grouped by directory.
- Pasting a profile or community page into Add Feed subscribes to its feed: Mastodon and Bluesky profiles, subreddits and Reddit users, Lemmy and Kbin communities, Groups.io groups, GitHub repositories, and YouTube channels, playlists, and channel pages.
- YouTube Takeout import in Settings, Subscriptions: subscriptions, playlists, and watched channels from a Google Takeout ZIP become subscriptions, like the desktop importer.
- YouTube videos gain a Transcript section in the reader: captions as readable paragraphs, no account needed.
- Filter Rules grew the desktop's full action set: mark read, favorite, delete, do not notify, move to a category, label, and stop processing further rules, combined per rule in order.
- Persistent Searches: named searches saved in Settings appear in the feed list's new Searches section, and the app restores your last feed or view at launch like the desktop. Categories are browsable from the feed list and can be renamed or deleted in Settings.
- Article retention: optionally remove articles older than 7, 30, 90, 180, or 365 days (favorites are never removed), and refreshes no longer bring back articles past the cutoff.
- Delete behaviour is now a setting: move to Deleted Articles (as before), delete permanently, or move to a category; deleting asks first unless you turn the confirmation off.
- Per-feed notifications: each feed's properties can mute its new-article notifications, and feeds show their published description there; Reset Title restores the feed's own title.
- Home is cleaner: feed rows no longer expose a per-feed Refresh action or an accidental full-swipe Refresh. Refresh one feed deliberately from its Feed Properties; the global Refresh All remains in the More menu on iPhone and the toolbar on iPad.
- Reader presentation options (desktop Reading settings): bullet markers on lists, Quote markers on quotations, link targets read after link text, and image alt text, all off by default as on the desktop. Search can be limited to titles.
- New Settings tools: a built-in User Guide, Open Article by URL, Open Media URL, and Site Cookies (import a browser's cookies.txt for sites that need a sign-in). Cmd+1 to Cmd+5 switch library views on a keyboard, and every feed now keeps its published description.

## 0.1.11

- On iPhone, Add Feed and More now sit right at the top of the feed list, under the status bar. 0.1.10 left a blank band above them.

## 0.1.10

- On iPhone, Add Feed and More are now large buttons at the top of the feed list, before the Feeds heading, so VoiceOver reaches them first and they are easier to tap. More holds Refresh All and Settings. iPad keeps them in the sidebar toolbar.

## 0.1.9

- The mini player now starts compact, one row high: the episode title and time, Back, Play or Pause, and Forward. Before, it took about a fifth of an iPhone screen on every view, and more while typing a search. All player controls, at the end of the row, shows every control as before: Stop, speed, chapters, AirPlay, and More player controls. Fewer player controls shrinks it again, and the app remembers the choice. Swiping up or down on the title still seeks, and the two-finger double tap still plays and pauses.
- On iPad and in landscape, articles and the player now stay at a readable width, centered, instead of stretching lines and buttons across the whole screen.
- YouTube videos in the reader now fill the width at 16:9, instead of a fixed short strip.

## 0.1.8

- Fix article actions not following the chosen order. iOS also lists a row's touch swipe actions in the VoiceOver Actions rotor, ahead of the row's own actions. So Delete, Favorite, Mark Read, Play, and Share came first, and most actions were offered twice. While VoiceOver is on, rows now offer only their own actions, in the order from Settings, Article Actions: Open in Browser, Download Media, and Copy Link first by default. Touch swipes are unchanged when VoiceOver is off.
- The same duplicate actions are gone from feeds, the play queue, deleted articles, smart folders, and filter rules.

## 0.1.7

- Feeds now refresh automatically. Settings, Refresh automatically offers Never, every 5, 10, or 30 minutes, every hour, every 2 hours, or every day. The default is every 5 minutes, as on the desktop.
- Automatic refreshes are quiet. They speak only when there are new articles, for example "12 new articles.", instead of announcing every feed.
- When the app is closed, iOS Background App Refresh refreshes on the same schedule. iOS picks the exact time: never sooner than the interval, often later, and not at all if Background App Refresh is off for BlindRSS. New articles raise a notification when Notifications for new articles is on.
- Fix podcasts stopping when the screen locks or you leave the app. No earlier build declared background audio: the setting meant to do it was one Xcode ignores. Background audio and background refresh are now declared in the app's Info.plist.
- Fix Refresh on startup. The setting was saved but never used, so the app did not refresh when it opened.
- Only one Refresh All runs at a time. Pulling to refresh during an automatic refresh says "Refresh already in progress." instead of fetching every feed twice.
- Article actions now start with Open in Browser, then Download Media, then Copy Link. The order can be changed in Settings, Article Actions, with Move Up, Move Down, and Move to Top on each action, dragging in Edit mode, and Reset to Default Order.
- Share is now a VoiceOver action too, matching the touch swipe. Play, Add to Play Queue, and Download Media only appear on articles with audio.

## 0.1.6

- Fix updating and installing from AltStore. AltStore said "The data couldn't be read because it isn't in the correct format", because every BlindRSS build so far was unsigned. Builds are now signed with the owner's certificate, as Accessible IPTV builds are, and a release build fails instead of publishing an unsigned app.
- The equalizer now works on streamed episodes, not only downloads. It matches the desktop: ten bands from 31.25 Hz to 16 kHz, a preamp, gains from -20 to +20 dB, the desktop's built-in presets, and presets you save and delete. Open it from More player controls, Equalizer.
- Skip Silence now works on streamed episodes too, and is on by default as on the desktop. Quiet parts of 0.7 seconds or more play quickly until sound returns. Turn it off under More player controls or in the Equalizer.
- Downloads now play in the mini player with every player control, instead of a separate download player.

## 0.1.5

- The podcast player is now the mini player at the bottom of the screen, with every control of the desktop player. It no longer opens over the app. Controls: a position slider, back and forward by the seek interval, Play or Pause, Stop, speed, chapters, AirPlay, and More player controls.
- Speed goes from 0.5x to 4x like the desktop. Swipe up or down on Playback speed to change it by a tenth. The menu has Faster, Slower, Normal Speed, and presets.
- Chapters: swipe up or down on Chapters to move to the next or previous chapter. The menu adds Open Chapter Link and the chapter list, with the current chapter checked. The progress value names the current chapter.
- More player controls: Volume Up and Volume Down in 5 percent steps, Play Next in Queue, the new Play Previous in Queue, Open Play Queue, and Sleep Timer.
- Double tapping an article with audio now plays it, as activating it does on the desktop. The reader still opens with its notes.
- Stop now saves your position.

## 0.1.4

- Fix Fetch Full Text. It used to strip the tags from the whole web page, so it read menus, footers, cookie notices, and related links. It never picked out the article. It now finds the article the way BlindRSS for Android does, and keeps only its headings and paragraphs.
- Miniflux articles get their full text from your Miniflux server first. The server's extractor also works on sites that block apps.
- Pages are now requested the way Safari requests them. The old app name was blocked by many news sites, and the error page text was shown as the article. When a site refuses, the app now says so, with the HTTP code.
- Pages that are not in UTF-8 now load. Before, they failed with a message saying the feed text was already complete.
- The reader now shows each paragraph and heading as its own VoiceOver item. Swipe moves by paragraph, and the Headings rotor works in articles. Before, the whole article was one item.
- Web punctuation like &#8217; and &rsquo; is now shown as the real character, not read out as code.
- On iPad, choosing another article no longer keeps the previous article's full text.

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
