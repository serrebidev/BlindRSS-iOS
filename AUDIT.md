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
- Podcast parity (0.1.0): chapters come from Podcasting 2.0 chapters JSON and inline feed chapters; resume uses SwiftData PlaybackState with the desktop rules (save every 15 seconds, rewind 10 on resume, last minute counts as finished); the play queue persists across restarts, auto-advances, and marks finished episodes read; lock-screen/headphone remote commands and background audio are wired; volume, desktop speed preset steps, and a sleep timer are in the player; auto-download after refresh honors the desktop max_downloads limit; one combined Search Feeds and Podcasts searches Apple Podcasts and gPodder by name and detects feeds for pasted URLs (page discovery plus feedsearch.dev); Podcast Archive recovers back catalogues from the Wayback Machine with batch download. Streaming EQ remains download-only, since AVPlayer has no equalizer graph.
- Casting: AirPlay route picker in the equalizer player and system player. Chromecast and DLNA need Google's Cast SDK and a Cast application id; that is the one desktop feature not ported, because it cannot ship without the owner's Cast credentials.
- Notifications for new articles after refresh (Settings toggle), announcements for all major state changes.
- Translations: not ported. The desktop catalogs are gettext files for 15 languages; iOS needs String Catalogs. English ships in 0.1.0.
- CPU: see docs/CPU-AUDIT.md. OPML bulk import still subscribes one feed at a time; a subscribe-first-refresh-once fast path is future work.

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

## 0.1.12 parity pass (2026-10-25, against desktop v2.5.1)

Ported: all keyless podcast/feed directories (fyyd, Podverse, Feedly,
NewsBlur, Reddit, Lemmy, PieFed, Mastodon, Bluesky, Groups.io, Feedspot,
Google News, Bing News) grouped by source in Discover; social URL to
feed resolution (Mastodon, Bluesky, Reddit, Lemmy/Kbin, Groups.io,
GitHub releases, YouTube channel/playlist/page); YouTube Takeout ZIP
import (subscriptions, playlists, owner channel, watch history);
YouTube transcripts in the reader via the keyless Innertube route;
the full Filter Rules action set as an ordered pipeline (mark read,
favorite, delete, skip notification, move, label, stop); Persistent
Searches with sidebar browsing; browsable Categories with rename and
delete; article retention with insert cutoff and favorite exemption;
the three-way delete behaviour setting with optional confirmation;
per-feed notification mute; feed description storage and display with
Reset Title; reader presentation toggles (bullets, quotes, link
targets, alt text) and search scope; last-view/last-feed restoration;
Cmd+1..5 library shortcuts; built-in User Guide; Open Article by URL;
Open Media URL; Site Cookies import (cookies.txt into the shared
cookie storage).

Still not ported, unchanged from the findings above: casting beyond
AirPlay (Cast SDK plus the owner's Cast application id; DLNA/Sonos/
Roku/Kodi belong to the separate Caster engine), yt-dlp resolvers and
everything stream-resolved (including SponsorBlock and download-first
playback), YouTube Account OAuth and Recommendations (the project's
Google OAuth client is not in this repo), article translation (desktop
is bring-your-own AI API key), forum-thread enumeration and the
GitHub/Google Groups synthetic sources (native feeds cover the same
publications), the Awesome RSS catalogue (dozens of bulk OPML fetches
per search; the same publishers answer through NewsBlur/Feedly/
Feedspot), keyed news APIs (NewsAPI/TheNewsAPI return nothing without
a user key), interface translations (String Catalogs conversion), and
desktop-OS surfaces (tray, soundcard selection, built-in updater;
AltStore is the updater here).

Home cleanup (Brandon, 2026-10-26): per-feed Refresh was removed from
Home feed rows as both a VoiceOver custom action and a leading
full-swipe action. It now lives in Feed Properties as Refresh Feed.
The one global Refresh All remains reachable from More on iPhone and
the sidebar toolbar on iPad; pull-to-refresh also remains available.

## 0.1.13 research round (2026-10-26): the "not ported" list, re-examined

Brandon's methodology, applied per problem area: web search with the
results opened and read, plus GitHub, Codeberg, and GitLab searches,
each sorted by most recent (10 results) and by most stars (10 results).
Findings are recorded per area below with repo names, stars, last-push
dates, and a one-line verdict each. "Ported" means a maintained-enough
library or a documented public API/endpoint integrated in the app's
existing patterns, with unit tests in the repo style. Anything still
blocked cites the evidence here, not an assertion.

### A. yt-dlp-equivalent extraction (YouTube, Rumble, Odysee, SponsorBlock, SoundCloud, Mixcloud)

Web, read: SwiftyYTDL (a SwiftUI wrapper that embeds yt-dlp through
PythonKit and the Python Apple Support prebuilt libraries; a stub
project, no maintenance signal); tfourj/palladium (an iOS media
downloader app based on yt-dlp, app not library); yt-dlp-apple-webkit-
jsi (a Python yt-dlp plugin that solves YouTube challenges through
Apple WebKit — still requires an embedded Python runtime); a-Shell and
iSH (terminal apps that run yt-dlp on iOS — not embeddable in another
app); 0xced/XCDYouTubeKit (Objective-C extractor, JavaScriptCore
signature unscrambling, unmaintained era); the Innertube explainer
(the keyless /youtubei/v1 player, search, next, and browse endpoints —
the app already uses the player endpoint for transcripts); DeepWiki
architecture pages for alexeichhorn/YouTubeKit (local extraction:
watch page fetch, player JS download, concurrent Innertube clients,
local cipher decryption, Stream objects; optional remote youtube-dl
WebSocket fallback).

GitHub, "youtube extractor swift", recent: alexeichhorn/YouTubeKit
(420 stars, pushed 2026-10-25 — the extractor, actively maintained);
nssevy/YTTranscript (0, 2026-10-09, transcript tool, not extraction);
teenagelove/swift-yt-downloader (0, 2026-07-10, Telegram bot);
dcas796/YouTubeKit (5, 2024-03-31, stale namesake);
AlwardL24/SwiftYoutubeExtractor (2, 2023-12-11, tiny subset);
yassram/YoutubeVideoExtractor (10, 2018-12-02, dead).
GitHub, same query, stars: YouTubeKit 420 first; everything else is
10 stars or fewer and 2018–2024 vintage.
GitHub, "innertube swift youtube", recent and stars: b5i/YouTubeKit
(134 stars, pushed 2026-08-18 — a different library: internal-API
data access, no stream extraction); arraypress/swift-youtube-metadata
(3, 2026-10-25, metadata via Innertube); atpugvaraa/YouTubeSDK (2,
2026-10-14, Innertube SDK); gek0z/YouMenuTube (0, 2026-10-04, uses
YouTubeKit for playback).
GitHub, "ytdlp ios python": no results in either sort. Codeberg and
GitLab: no results for any A query, either sort.

Verdict, YouTube: PORTED. alexeichhorn/YouTubeKit (MIT, 420 stars, 34
releases, latest 0.4.10, pushed the day before this round) does
yt-dlp's local extraction in pure Swift. Integrated as an SPM
dependency; YouTube articles gain Play Stream (AVPlayer, with resume,
speed, and SponsorBlock skipping) and Download Stream, and Discover's
Video Search runs on the keyless Innertube search endpoint the app
already used for transcripts. The embedded web player stays as the
visual option. Rumble and Odysee: still blocked — no Swift extractor
exists on any host, and the only iOS yt-dlp route is embedding a
Python runtime behind a stub wrapper (SwiftyYTDL) or a terminal app;
that evidence stands until a maintained library appears.

SponsorBlock: web reading — the official API documentation
(wiki.sponsor.ajay.app): GET /api/skipSegments returns segment times
as JSON, no key; ajayyy/iSponsorBlock (an iOS jailbreak tweak — proof
the API is used from iOS, not a reusable library). GitHub,
"sponsorblock swift", recent and stars: 0xCUB3/wBlock (3,132 stars,
2026-10-25, Safari content blocker, not a segment client);
milika/SmartTubeIOS (432, 2026-10-12, a full Swift YouTube client
with SponsorBlock — precedent, not a library); shirkeharsh/mooziac
(106, 2026-10-24, macOS player). No Swift client library on Codeberg
or GitLab either. Verdict: PORTED without a library — the documented
public API is one GET; SponsorBlockService parses it (unit-tested)
and AudioPlayer skips segments during stream playback, announced.

SoundCloud: web reading — SoundCloud closed new API registrations in
2017; the internal api-v2 needs a client_id harvested from the web
player's JS bundles, which rotates every few weeks (multiple 2026
guides confirm); the official route is OAuth with a registered app.
But SoundCloud also serves a native per-user RSS feed at
feeds.soundcloud.com/users/soundcloud:users:<id>/sounds.rss (verified
live, HTTP 200), needing nothing. GitHub, "soundcloud api swift":
delannoyk/SoundcloudSDK (89 stars, 2021-11-14, stale); lerboe/
SoundCloud (41, 2026-10-23, private api-v2 client — depends on the
rotating client_id); superturboryan/SoundCloud-Swift (11, 2026-05-31,
public API client — still needs a registered client_id). Codeberg and
GitLab: nothing. Verdict: PORTED via the RSS route — a profile URL
resolves by scraping the user id from the profile page (the app's
existing YouTube-channel pattern) to the native RSS feed. Playback of
SoundCloud tracks themselves still needs api-v2 with a harvested
client_id; subscriptions (new-upload tracking) are the ported part.

Mixcloud: the documented public API (mixcloud.com/developers) serves
a user's cloudcasts at api.mixcloud.com/<user>/cloudcasts/ with no
key (verified live). Verdict: PORTED — profile URLs convert to the
API list URL and FeedParser reads it as a feed. The API exposes no
direct stream URLs (playback stays in Mixcloud's own player), so
entries link to the cloudcast pages; that is an API limit, stated.

### B. Casting beyond AirPlay

Web, read: Google's official iOS sender integration guide — its own
sample initializes GCKCastContext with
kGCKDefaultMediaReceiverApplicationID, Google's Default Media
Receiver (CC1AD845), and its media-load walkthrough runs on it; no
developer registration is involved. Bitmovin's Cast documentation
confirms the iOS SDK falls back to the default receiver when no app
id is configured. The 0.1.12 claim "cannot ship without the owner's
Cast credentials" is therefore REFUTED for media casting; a custom
receiver (branding, custom namespaces) would still need an owner-
registered application id, and nothing in the desktop's Caster media
flow needs one.

GitHub, "google cast ios sdk swift", recent: SRGSSR/castor (16
stars, pushed 2026-10-26 — a high-level Cast SDK from the Swiss
broadcaster's engineering org; its 3.x line needs swift-tools 6.4);
CreatureSurvive/SwiftCast (0, 2026-09-27, pure-Swift sender,
brand new); tobiaseisenschenk/swift-package-google-cast-sdk (1,
2024-12-20, thin SPM wrapper). Stars sort: the same three. Google
itself distributes the iOS SDK only via CocoaPods and manual
download; SRGSSR/google-cast-sdk is a maintained SPM packaging of
Google's official xcframework (tools 5.7, current release 4.8.6).
Codeberg and GitLab: no Cast SDKs, either sort.
GitHub, "dlna upnp swift ios", recent and stars: yuri-rod/
smart-tv-remote-swift (2, 2026-10-04, TV remote with some DLNA);
CreatureSurvive/UPnPCast (0, 2026-09-27, new, unproven). Nothing
maintained; the desktop's DLNA/Sonos/Roku/Kodi support lives in its
separate Caster engine, not in a reusable Swift library.

Verdict: Google Cast PORTED — GoogleCast 4.8.6 via the SRGSSR SPM
packaging, Cast context on the default receiver, a labeled Cast
button beside AirPlay in the player, and session-start media
handoff with local pause. DLNA/UPnP and the rest of the Caster
engine: still blocked on library evidence above; they stay a
separate-engine feature.

### C. Article translation without a user API key

Web, read: Lingva Translate (open-source Google Translate frontend)
documents GET /api/v1/<source>/<target>/<text> -> {"translation"};
its instance list names lingva.ml (official), translate.igna.wtf,
lingva.lunar.icu, translate.plausibility.cloud,
translate.projectsegfau.lt, lingva.garudalinux.org and more
(verified live from this workspace). LibreTranslate's flagship
instance now requires a key, but its README's mirror table lists
keyless public mirrors (translate.argosopentech.com,
translate.terraprint.co, trans.zillyhuhn.com,
libretranslate.eownerdead.dedyn.io, lt.vern.cc); the endpoint is
POST /translate -> {"translatedText"}. LiTranslate (an iOS app on
LibreTranslate) is App Store precedent for shipping this way.

GitHub, "libretranslate client swift", recent and stars:
wacumov/libretranslate (17 stars, 2025-01-27 — a real Swift client;
not needed, the endpoint is one POST). GitHub, "lingva translate
api": no Swift client of note (artdima/LingvanexAPI is a different,
keyed service); clients are C++/Ruby/Python (aqbifzl/lingva-api,
cheeaun/lingva-api). GitLab: nesstero/pylingva (1 star, 2024-08-12)
and mirrors. Codeberg: nothing.

Verdict: PORTED — TranslateService tries six Lingva instances, then
four LibreTranslate mirrors, per chunk; the reader gains a Translate
button (target: the device language). No key, no account.

### D. YouTube account features (OAuth, Recommendations)

Web, read: Yattee, the largest open-source iOS YouTube client,
deliberately ships no Google account login (it uses Invidious/Piped
backends and their accounts instead) and offers no recommendation
feed. Google's own iOS OAuth documentation requires an OAuth client
ID created in the app owner's Google Cloud project, bound to the
app's bundle ID, with a consent screen; there is no shared or
third-party client an unrelated app may ship. Code hosts: the query
"youtube api oauth ios client swift" returned ZERO results on
GitHub, Codeberg, and GitLab in both sorts — no library ships this.

Verdict: still blocked, on one exact missing credential that only
Brandon can supply: a Google Cloud project for BlindRSS with an
iOS OAuth client ID bound to bundle id org.serrebidev.BlindRSS
(plus its consent screen). With that client id, sign-in and the
subscriptions/recommendations feeds are a standard integration;
without it, no code can ship account features. (Invidious/Piped
public instances would give a non-Google account system, but they
are third-party proxies with their own reliability and terms; not
treated as an unlock.)

### E. Forum-thread reading (Reddit, Lemmy, Groups)

Web, read: Lemmy's API documentation (join-lemmy.org) — public
/api/v3 REST, and multiple client guides confirm read access to
public communities needs "no login, no API key, and no OAuth";
GetPost and GetComments are documented endpoints (verified live
from this workspace). Reddit: Reddit's own deprecation notice for
unauthenticated JSON access, plus several 2026 reports that .json
answers 403 since May 2026 across hosts; the supported paths are
the OAuth Data API (free non-commercial tier, registered and
approved app, Responsible Builder Policy since November 2025) or
Devvit. One article claimed .json still works; the weight of
evidence, including Reddit's own statement, says it is shut.

GitHub, "lemmy api client swift", recent and stars:
CreatureSurvive/Swimmy (0 stars, 2025-02-04) — the only Swift
client; unnecessary, the REST endpoints are two GETs. GitHub,
"reddit api client swift ios": cranci1/Osmium (28, 2025-05-08, a
cobalt-API client, unrelated); direx99/reddit-bionic-client (0,
2023-09-02, goes through a custom Node proxy — an admission the
direct route is closed); dyountmusic/realtimereddit-iOSClient (5,
2019-04-18, pre-shutdown). Codeberg and GitLab: nothing usable.

Verdict: Lemmy PORTED — post articles from any Lemmy instance gain
a Load Thread section (post body plus comments, depth-indented).
Reddit threads: still blocked — the unauthenticated route is shut
down by Reddit (evidence above); unblocking needs a Reddit API app
registered and approved under Brandon's own Reddit account, which
only he can create. Groups.io threads ride the group's native RSS
(already subscribed); Google Groups has no public API or RSS
(Google retired both), so its threads stay web-only.

### F. Interface translations (gettext -> String Catalogs)

Web, read: the .xcstrings format is JSON; Xcode resolves SwiftUI
literal Text/Button titles through Localizable.xcstrings by the
English source string — the same key gettext uses as msgid.
Localazy (commercial SaaS) advertises PO -> String Catalog
conversion; no open-source PO converter appeared in web results.
The code-host sweep confirms it: GitHub, "xcstrings gettext po
converter" — ZERO results in both sorts on GitHub, Codeberg, and
GitLab. GitHub, "string catalog localization tool", recent:
corrupt952/xckit (5 stars, 2026-10-26, catalog management CLI);
TheEnd14147/xcode-xcstrings-csv-tool (4, 2026-10-12, CSV-driven);
jaalbin24/xcstrings-tool (4, 2026-01-16, completeness audits);
stars sort adds KookyBread/AutoStringsCatalogsTranslator (5,
2025-09-06) and zhang-hongshen/strings2xcstrings (1, 2024-01-13,
.strings files, not .po). Every tool is CSV- or strings-based;
none reads gettext.

Verdict: PORTED with an in-repo tool — tools/po2xcstrings.py
converts the desktop's 15 catalogs into Localizable.xcstrings:
1,881 keys, roughly 1,600 translated strings per language, plural
entries take their first form, and gettext placeholders (%s, %d,
%(name)s) become catalog specifiers (%@, %lld). SwiftUI literals
that match desktop strings (Settings, Play, Pause, Add Feed,
Downloads, and hundreds more) now localize with the device
language. Honest limits: strings built in code — accessibilityLabel
values and announcements — are plain Swift Strings that do not pass
through the catalog and stay English, and iOS-only literals with no
desktop counterpart stay English until the desktop catalogs gain
them.

### G. Keyless news search and the Awesome RSS catalogue

Web, read: the Awesome RSS repository (plenaryapp/awesome-rss-
feeds, 2,853 stars, pushed 2026-10-05) is organized as one OPML
file per country (25, in with_category and without_category forms)
and per topic; the Plenary app's own design fetches a single file
when a country is opened. The 0.1.12 objection ("dozens of bulk
OPML fetches per search") misread the structure: search never
fetches anything; browsing fetches one file. NewsAPI and
TheNewsAPI remain key-only (their Swift clients, e.g.
lucaslimapoa/NewsAPISwift, 25 stars, 2018-06-28, still require a
developer key); the keyless headline-search function is already
covered by the Google News and Bing News RSS directories ported in
0.1.12. GitHub, "awesome rss feeds", stars: plenaryapp/
awesome-rss-feeds first (2,853); GitLab carries only a
deletion-scheduled mirror (0 stars, 2026-10-02); Codeberg nothing.

Verdict: catalogue PORTED — Discover gains a Browse Awesome RSS
Catalogue section (25 countries, 41 topics); opening an entry
downloads exactly one OPML file and lists its feeds for one-tap
subscribe, grouped by the OPML's own categories. Keyed news APIs
stay keyed, with the keyless RSS directories as the shipped
equivalent.
