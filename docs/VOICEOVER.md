# VoiceOver Guide

BlindRSS for iOS is built VoiceOver first. This guide covers every gesture. It mirrors the desktop keyboard commands where an equivalent exists.

## Moving around

Swipe right to move forward, swipe left to move back. The app has three areas, like the desktop main window: the feed list, the article list, and the reader.

Every article is one stop. It speaks the title first, then the feed, the date, whether it is read or unread, whether it is a favorite, and whether it has audio. You hear the same order on every article, so scanning a list is predictable.

Section headings are headings. Flick up or down with the Headings rotor setting to jump between them.

## Article actions

On any article, swipe up or down to cycle its actions, then double tap to run one.

- Read: opens the article and marks it read.
- Mark Read or Mark Unread: toggles the read state without opening it.
- Favorite or Remove Favorite: adds or removes the star.
- Play: starts the attached audio or video. Only present on articles with audio.
- Add to Play Queue: queues the episode after the current one.
- Open in Browser: opens the original article in Safari.
- Delete: deletes the article. Deleted articles are kept as snapshots in the database, matching the desktop Deleted Articles behavior, and refresh will not bring them back.

The same actions exist as touch swipe actions on each row for sighted and low-vision users. Neither group gets an action the other cannot reach.

## Feed actions

On any feed, swipe up or down for its actions.

- Open: shows the feed articles.
- Refresh: fetches new articles from that feed only.
- Mark All Read: marks every article in the feed read.
- Delete: removes the feed and its articles.

To refresh everything, pull down on the feed list, or use Refresh All in the toolbar.

## Rotors

Turn the two-finger rotate gesture to pick a rotor, then swipe up or down to jump.

- Headings: jumps between section headings.
- Unread: jumps between unread articles only.
- Favorites: jumps between favorite articles only.
- With Audio: jumps between articles with audio or video only.
- Chapters: inside an article or the player, jumps between chapters.

## Playback

Magic Tap, a two-finger double tap anywhere, plays or pauses. This is the VoiceOver equivalent of the desktop Ctrl+P command.

Open the player from the mini player bar at the bottom of the screen.

- Progress: focus it and swipe up or down to move 30 seconds at a time. It speaks position as "12 minutes of 43" style values, for example "3:05 of 42:10".
- Playback speed: focus it and swipe up or down to change speed in quarter steps, from half speed to three times speed.
- Chapters: buttons seek playback to the chapter start.
- Play Queue: remove an item or play it now from its actions. Play Next in Queue starts the next item.

State changes are announced: refresh results with new article counts, marked as read, added to favorites, deleted, added to the play queue, playing, paused, and playback failures. You do not need to hunt for a status bar.

## Adding and organizing

Add Feed is in the feed list toolbar. It asks for a feed URL and a category. Errors are announced, not only shown in red text. Subscribe confirms with the feed name and article count.

Settings has OPML import and export, refresh on startup, resume playback, default playback speed, and the seek interval. Import announces how many feeds were found and when the import finishes.

## Hardware keyboards

On iPad or Mac with a physical keyboard: Command-N adds a feed, Command-R refreshes, Command-Shift-R marks all read, matching the desktop command layout in core/shortcuts.py.

## More actions in 0.1.0

Article actions also include Copy Link and Download Media. Downloaded episodes play offline. In Settings, Downloads opens the equalizer player: five EQ bands are sliders (focus one and swipe up or down), Skip silence is a toggle, and the AirPlay picker chooses output devices.

Settings also contains: Online Account (Miniflux, Inoreader, The Old Reader, BazQux sync), Smart Folders, Filter Rules, and Deleted Articles, where Restore and Delete Permanently are row actions. Feed rows include Edit Feed for renaming and recategorizing.

In the reader, Fetch Full Text recovers complete articles, and YouTube articles show an embedded player with chapter listings from the description.

## Podcast playback

Episodes resume where you stopped, rewound ten seconds. Finished episodes are marked read, and the next queued episode starts on its own. The play queue survives restarting the app; Move Up, Move Down, Remove, Play Now, and Clear Queue are queue actions.

Lock-screen and headphone controls play, pause, skip, and seek without opening the app. In the player: Volume is a slider, Speed Presets sets speed directly, Sleep Timer stops playback after 15, 30, or 60 minutes or at the end of the episode, and chapters seek when focused.

Find a Podcast in Add Feed searches Apple Podcasts; subscribing is one tap on a result. A feed's Podcast Archive action recovers older episodes from the Wayback Machine and downloads them in batches. Auto-download in Settings fetches new episodes after refresh, up to the limit you set.
