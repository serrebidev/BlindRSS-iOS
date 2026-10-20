# BlindRSS for iOS

Native SwiftUI port of [BlindRSS](../BlindRSS), the screen-reader-first desktop RSS and podcast client. Built for VoiceOver first, following [ios-swiftui-accessibility-techniques](https://github.com/cvs-health/ios-swiftui-accessibility-techniques) by CVS Health.

See [AUDIT.md](AUDIT.md) for the full desktop audit, the feature map, and what is deferred to Phase 2.

## Build (Mac required)

This project was authored on Windows/WSL, which has no Xcode. To build:

1. Open `BlindRSS.xcodeproj` in Xcode 16 or later.
2. Select the BlindRSS target, set your signing team.
3. Run on a device or simulator (iOS 17+).

Run `a11y-check .` from this folder after installing the checker from the techniques repo to lint the SwiftUI sources:

```bash
brew tap cvs-health/ios-swiftui-accessibility-techniques https://github.com/cvs-health/ios-swiftui-accessibility-techniques.git
brew install --HEAD cvs-health/ios-swiftui-accessibility-techniques/a11y-check
a11y-check .
```

## VoiceOver quick reference

- Swipe right/left: move through feeds and articles. Each article speaks title, feed, date, read state, favorite state, and "has audio" once.
- Actions: swipe up or down on a focused article or feed to cycle its actions (Read, Mark Read/Unread, Favorite, Play, Add to Play Queue, Open in Browser, Delete), then double tap. The same actions exist as touch swipe actions on each row.
- Rotor: two-finger rotate to choose Headings, Unread, Favorites, With Audio, or Chapters, then swipe up or down to jump.
- Magic Tap: two-finger double tap toggles play/pause anywhere.
- Player: focus Progress or Playback speed and swipe up or down to adjust by 30 seconds or a quarter speed step.
- Refresh: pull down on the feed list, or focus a feed and use its Refresh action.

## Layout

- `BlindRSS/Models` — SwiftData models mirroring the desktop `rss.db` schema.
- `BlindRSS/Services` — feed parsing (RSS/Atom/JSON Feed), library store, OPML, AVPlayer player, VoiceOver announcer.
- `BlindRSS/Views` — feed list, article list, reader, player, add feed, settings.
- `BlindRSSTests` — parser, HTML text, and OPML unit tests. Run with Command-U on a Mac.

## License

MIT, same as the desktop app.
