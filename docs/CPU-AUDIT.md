# CPU Audit: Miniflux Sync, Refresh, Adding Feeds

Audit of the 0.1.0 code, with the fixes applied in 0.1.1. Reference account: Miniflux at rss.serrebiradio.com with 698 feeds and 28,785 total entries (measured directly against the API: /v1/feeds answers in about 0.6 seconds; one global /v1/entries page of 500 is about 4 MB in about 1 second). No on-device profiler is available in this environment, so costs are counted from the code: requests, fetches, comparisons, and main-actor work per operation.

## Miniflux sync (Services/Providers.swift)

Before 0.1.1, sync fetched entries per feed: 698 sequential requests, each waiting on the network, all inserts on the main actor, and no save until the end. It looked frozen and was the reported "never completes" bug. The 0.1.1 rewrite uses the global entries endpoint (pages of 500, newest 2,000), four requests total.

CPU problems found in the 0.1.1 rewrite and fixed in the same pass:

- fetchOrCreateFeed ran a full Feed table fetch for every feed: 698 full fetches per sync, each faulting relationships. Now one fetch builds an id dictionary.
- Every entry did a linear scan of its feed's article array to test existence. With thousands of stored articles this is the classic accidental quadratic. Now each feed's articles become a dictionary once, and lookups are constant time.
- Each 4 MB JSON page decoded on the main actor, stalling the UI four times per sync. Decoding now runs in a detached task; only the SwiftData inserts stay on the main actor, which they must.
- Progress saves happen per page (four saves), so a killed sync keeps what it fetched.

Remaining cost, accepted: inserting 2,000 articles with full HTML content into SwiftData is main-actor work and will take seconds on a first sync. It is now bounded, announced per page ("Fetched 500 articles"), and later syncs mostly update read and favorite flags on existing rows.

## Local refresh (Services/LibraryStore.swift)

- Refresh All was strictly sequential: one feed at a time. For a large local library that keeps the radio awake for the sum of every feed's latency. It now fetches and parses 8 feeds concurrently (desktop allows 16; 8 is the phone-friendly value) and merges serially, because ModelContext is not thread-safe.
- Feed XML parsed on the main actor. A large feed blocked the UI for the whole parse. Fetch and parse now run off the main actor (FeedParser types are Sendable, parsing runs detached).
- Merge did a linear article scan per entry and fetched the FilterRule table once per new article. A 100-entry refresh against a 2,000-article feed was about 200,000 comparisons plus 100 table fetches. Merge now builds one article dictionary and fetches filter rules once per feed.
- Each new article with a chapters URL still spawns its own chapters fetch. These are small JSON documents and they suspend on the network rather than burning CPU, so this was left as is.

## Adding feeds

- Add Feed shared the old merge costs and parsed on the main actor. Both are fixed by the shared fetch and merge changes above; a single add is one request, one detached parse, one save.
- OPML import adds feeds one at a time, saving each. For a 698-feed OPML that is 698 sequential subscribes. Each subscribe also downloads that feed's articles immediately, which is the real cost. This is correctness-friendly but slow; a bulk-import fast path that subscribes first and refreshes once is future work, noted in AUDIT.md.
- Discover subscribe has the same single-add path and is fine.

## Lists and player (per-render costs)

- Article search stripped HTML from every article's full content on every render while searching. That was the list's largest CPU cost. Search now matches raw content text without HTML stripping.
- Feed rows filtered their feed's entire article list to count unread, once per row per render: 698 feeds meant 698 full scans per frame. Unread counts are now built in one pass over all articles and read from a dictionary.
- The play queue restore used a linear scan per queued id; now a dictionary.
- Playback state was fetched in full on every play and again on every 15-second progress save. It is now fetched once when the player wiring is set up and kept in a dictionary.

## Battery note

The concurrent refresh window (8) and the Miniflux page cap (2,000 newest) are the two settings that most affect radio time. Both favor finishing quickly and letting the radio sleep over trickling requests indefinitely, which is the right trade on cellular.

## Second pass (0.1.2)

0.1.1 still ran hot on the reference account. The first pass counted network and merge costs but missed per-render SwiftUI costs, which repeat on every model change. During a refresh that is every merged feed.

- Feed list unread counts (Views/FeedListView.swift). The 0.1.1 "single pass" was a computed property, and each feed row read it three times (badge check, badge text, VoiceOver value). Every read walked every feed's articles, so 698 feeds meant about 2,100 full-library passes per render. The Library badges added two more flatMaps of every article. Now one pass per render produces per-feed unread, total unread, favorites, and error counts, passed into the rows. Categories group once with Dictionary(grouping:) instead of filtering all feeds per category.
- Refresh All with a hosted account (Services/LibraryStore.swift). Miniflux and Google Reader feeds were refreshed by fetching their feed URLs directly: 698 requests and parses, merged under local ids ("miniflux:12:guid") that differ from the sync ids ("miniflux:4567"), so every refresh duplicated the account's articles and grew the library that every list scans. Hosted feeds (Feed.isHosted) now refresh through HostedSync; only local feeds are fetched by URL. Single-feed refresh of a hosted feed also syncs the account.
- Save frequency. Refresh saved after every feed. Each save re-runs every open @Query and re-renders the lists. Refresh now saves every 25 feeds and once at the end.
- Unchanged writes. Merge rewrote eight fields on every existing article, and Miniflux sync rewrote read and favorite flags on every entry. Writes now happen only when a value differs, so unchanged articles are not dirtied, saved, or re-rendered.
- Root view query (Views/ContentView.swift). ContentView held an @Query of every article only to restore the play queue at launch, so any article change re-rendered the whole window. It now fetches just the queued ids once.
- Article list (Views/ArticleListView.swift). The filtered list was a computed property read five times per render (empty check, list, three rotors), each a full filter and sort. It is now computed once per render, and the redundant sort is gone (the query already sorts by date).
- Date parsing (Services/FeedParser.swift). parseDate built a new ISO formatter and a new RFC formatter on every call and reconfigured them for each pattern. Formatters are now built once.
- Chapter loading and restore. loadChapters fetched the entire Article table once per new episode with a chapters URL; restore fetched every feed. Both fetch by id with a predicate.
- Smaller: reader strips HTML once per render instead of three times; Downloads queries only rows with a downloaded file; the downloads directory is resolved once; refresh child tasks no longer read SwiftData models off the main actor.
