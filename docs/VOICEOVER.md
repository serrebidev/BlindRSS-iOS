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

Double tapping an article that has audio plays it and opens its notes in the reader.

The player is the mini player bar at the bottom of the screen. It has every control of the desktop player, in this order:

- Progress: the episode title. Swipe up or down to move by the seek interval from Settings (30 seconds by default). The value is the position and the current chapter, for example "3:05 of 42:10, chapter Intro". Touch users can drag the slider.
- Back and Forward by the seek interval, Play or Pause, and Stop.
- Playback speed: swipe up or down to change speed by a tenth, from half speed to four times speed. Double tap for Faster, Slower, Normal Speed, and presets.
- Chapters: swipe up or down for the next or previous chapter. Double tap for Previous Chapter, Next Chapter, Open Chapter Link, and the chapter list.
- AirPlay and output devices.
- More player controls: Equalizer, Skip Silence, Volume Up and Volume Down in 5 percent steps, Play Next in Queue, Play Previous in Queue, Open Play Queue, and Sleep Timer.
- Equalizer: the desktop's ten bands from 31.25 Hz to 16 kHz plus a preamp, each a slider from -20 to +20 decibels (swipe up or down). Preset applies one of the desktop's built-in presets or one you saved. Type a Preset name, then Save as Preset saves the current levels. Delete Preset removes a saved one. Moving a slider turns the equalizer on. It works on streamed and downloaded episodes.
- Skip Silence, on by default as on the desktop, plays quickly through quiet parts of 0.7 seconds or more, on streamed and downloaded episodes.
- Play Queue: remove an item, play it now, or move it up or down from its actions. Clear Queue is in the toolbar.

State changes are announced: refresh results with new article counts, marked as read, added to favorites, deleted, added to the play queue, playing, paused, and playback failures. You do not need to hunt for a status bar.

## Adding and organizing

Add Feed is in the feed list toolbar. It asks for a feed URL and a category. Errors are announced, not only shown in red text. Subscribe confirms with the feed name and article count.

Settings has OPML import and export, refresh on startup, resume playback, default playback speed, and the seek interval. Import announces how many feeds were found and when the import finishes.

## Hardware keyboards

On iPad or Mac with a physical keyboard: Command-N adds a feed, Command-R refreshes, Command-Shift-R marks all read, matching the desktop command layout in core/shortcuts.py.

## More actions in 0.1.0

Article actions also include Copy Link and Download Media. Downloaded episodes play offline. In Settings, Downloads lists them; double tap one to play it in the mini player.

Settings also contains: Online Account (Miniflux, Inoreader, The Old Reader, BazQux sync), Smart Folders, Filter Rules, and Deleted Articles, where Restore and Delete Permanently are row actions. Feed rows include Edit Feed for renaming and recategorizing.

In the reader, Fetch Full Text recovers complete articles, and YouTube articles show an embedded player with chapter listings from the description.

## Podcast playback

Episodes resume where you stopped, rewound ten seconds. Finished episodes are marked read, and the next queued episode starts on its own. The play queue survives restarting the app; Move Up, Move Down, Remove, Play Now, and Clear Queue are queue actions.

Lock-screen and headphone controls play, pause, skip, and seek without opening the app. Sleep Timer, under More player controls, stops playback after 15, 30, or 60 minutes or at the end of the episode.

Search Feeds and Podcasts in Add Feed is one combined search: type a name to search Apple Podcasts and gPodder together, or paste a site URL to detect its feeds. Subscribing is one tap on a result. A feed's Podcast Archive action recovers older episodes from the Wayback Machine and downloads them in batches. Auto-download in Settings fetches new episodes after refresh, up to the limit you set.
