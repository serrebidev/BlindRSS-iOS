// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation

/// Podcast-specific services: Podcasting 2.0 chapters documents, Apple
/// Podcasts search (desktop Finding Podcasts), and Wayback archive recovery
/// (desktop Podcast Archive).
enum PodcastService {
    // MARK: Chapters (https://podcastindex.org/namespace/1.0#chapters)

    struct ChaptersDocument: Decodable, Sendable {
        struct Item: Decodable, Sendable {
            let startTime: Double
            let title: String?
            let url: String?
            let img: String?
        }
        let chapters: [Item]
    }

    static func parseChaptersJSON(data: Data) throws -> [ParsedChapter] {
        let doc = try JSONDecoder().decode(ChaptersDocument.self, from: data)
        return doc.chapters
            .map { ParsedChapter(start: $0.startTime, title: $0.title ?? "Chapter", href: $0.url) }
            .sorted(by: { $0.start < $1.start })
    }

    static func fetchChapters(urlString: String) async -> [ParsedChapter] {
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        return (try? parseChaptersJSON(data: data)) ?? []
    }

    // MARK: Apple Podcasts search (iTunes Search API, no key required)

    struct SearchResult: Decodable, Sendable, Identifiable {
        let collectionId: Int
        let collectionName: String?
        let artistName: String?
        let feedUrl: String?
        var id: Int { collectionId }
        var title: String { collectionName ?? "Podcast" }
    }

    private struct SearchResponse: Decodable, Sendable { let results: [SearchResult] }

    static func parseSearchJSON(data: Data) throws -> [SearchResult] {
        try JSONDecoder().decode(SearchResponse.self, from: data).results.filter { $0.feedUrl != nil }
    }

    static func searchPodcasts(term: String) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: "25"),
        ]
        guard let url = components?.url else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try parseSearchJSON(data: data)
    }

    // MARK: Unified discovery (feeds and podcasts in one search)

    struct FeedResult: Decodable, Sendable, Identifiable {
        let title: String
        let url: String
        let website: String?
        /// Directory the result came from ("" for gPodder results, which
        /// predate source labels; DiscoverView groups by this).
        var source: String = ""
        var id: String { url }
        enum CodingKeys: String, CodingKey { case title, url, website }
    }

    static func parseGPodderJSON(data: Data) throws -> [FeedResult] {
        try JSONDecoder().decode([FeedResult].self, from: data)
    }

    /// gPodder search: RSS feeds and podcasts by name, no key required.
    static func searchFeeds(term: String) async -> [FeedResult] {
        var components = URLComponents(string: "https://gpodder.net/search.json")
        components?.queryItems = [URLQueryItem(name: "q", value: term)]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        return (try? parseGPodderJSON(data: data)) ?? []
    }

    private struct FeedsearchResponse: Decodable, Sendable {
        struct Item: Decodable, Sendable { let url: String; let title: String?; let favicon: String? }
        let feeds: [Item]?
    }

    /// feedsearch.dev: finds feeds for a site URL (desktop Feedsearch).
    static func searchFeedsearch(siteURL: String) async -> [FeedResult] {
        var components = URLComponents(string: "https://feedsearch.dev/api/v1/search")
        components?.queryItems = [URLQueryItem(name: "url", value: siteURL)]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(FeedsearchResponse.self, from: data) else { return [] }
        return (decoded.feeds ?? []).map { FeedResult(title: $0.title ?? $0.url, url: $0.url, website: siteURL) }
    }

    /// True when the query looks like a URL rather than a name search.
    static func looksLikeURL(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.contains(".")
            && !trimmed.contains(" ")
    }

    // MARK: Wayback archive recovery

    struct ArchiveAvailability: Decodable, Sendable {
        struct Snapshot: Decodable, Sendable { let url: String?; let timestamp: String? }
        struct Closest: Decodable, Sendable { let closest: Snapshot? }
        let archived_snapshots: Closest?
    }

    /// Oldest usable Wayback snapshot URL for a feed, if one exists.
    static func waybackSnapshotURL(forFeed feedURL: String) async -> URL? {
        var components = URLComponents(string: "https://archive.org/wayback/available")
        components?.queryItems = [URLQueryItem(name: "url", value: feedURL)]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(ArchiveAvailability.self, from: data),
              let snapshot = decoded.archived_snapshots?.closest,
              let raw = snapshot.url else { return nil }
        return URL(string: raw)
    }

    /// Resume rule from desktop config: resume_back_ms 10000,
    /// resume_complete_threshold_ms 60000 (within a minute of the end
    /// counts as finished, so restart from the beginning).
    static func resumePosition(saved: TimeInterval?, duration: TimeInterval?) -> TimeInterval {
        guard let saved, saved > 0 else { return 0 }
        if let duration, duration > 0, duration - saved < 60 { return 0 }
        return max(0, saved - 10)
    }
}

// MARK: - Directory search (desktop Podcast and Feed Directories)

/// The desktop's keyless search directories beyond Apple Podcasts and
/// gPodder: fyyd, Podverse, Feedly, NewsBlur, Google News, Bing News,
/// Reddit, Lemmy, Mastodon, Bluesky, PieFed, Groups.io, and Feedspot.
/// Extractors are pure Data -> results functions (desktop gui/dialogs.py
/// response shapes), so they are unit-tested; the network calls are thin.
enum DirectorySearch {
    typealias Result = PodcastService.FeedResult

    static func searchAll(term: String) async -> [Result] {
        async let fyyd = searchFyyd(term: term)
        async let podverse = searchPodverse(term: term)
        async let feedly = searchFeedly(term: term)
        async let newsblur = searchNewsBlur(term: term)
        async let reddit = searchReddit(term: term)
        async let lemmy = searchLemmy(term: term)
        async let mastodon = searchMastodon(term: term)
        async let bluesky = searchBluesky(term: term)
        async let piefed = searchPieFed(term: term)
        async let groupsIO = searchGroupsIO(term: term)
        async let feedspot = searchFeedspot(term: term)
        var results = await fyyd + podverse + feedly + newsblur + reddit + lemmy
            + mastodon + bluesky + piefed + groupsIO + feedspot
        results += constructedNewsResults(term: term)
        var seen = Set<String>()
        return results.filter { seen.insert($0.url).inserted }
    }

    /// Google News and Bing News need no lookup: the result is a news
    /// search feed for the term itself (desktop does the same).
    static func constructedNewsResults(term: String) -> [Result] {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let locale = Locale.current
        let language = locale.language.languageCode?.identifier ?? "en"
        let region = locale.region?.identifier ?? "US"
        return [
            Result(title: "Google News: \(trimmed)",
                   url: "https://news.google.com/rss/search?q=\(encoded)&hl=\(language)-\(region)&gl=\(region)&ceid=\(region):\(language)",
                   website: "https://news.google.com", source: "Google News"),
            Result(title: "Bing News: \(trimmed)",
                   url: "https://www.bing.com/news/search?q=\(encoded)&format=rss",
                   website: "https://www.bing.com/news", source: "Bing News"),
        ]
    }

    // MARK: Network plumbing

    private static func fetch(_ urlString: String, acceptHTML: Bool = false) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("BlindRSS-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if acceptHTML { request.setValue("text/html", forHTTPHeaderField: "Accept") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private static func jsonData(_ urlString: String) async -> Data? { await fetch(urlString) }

    private static func object(_ data: Data?) -> Any? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    private static func dict(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
    private static func dicts(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }
    private static func string(_ dict: [String: Any], _ key: String) -> String {
        (dict[key] as? String) ?? ""
    }

    private static func query(_ term: String) -> String {
        term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
    }

    // MARK: fyyd

    static func searchFyyd(term: String) async -> [Result] {
        parseFyyd(await jsonData("https://api.fyyd.de/0.2/search/podcast?term=\(query(term))&count=20"))
    }

    static func parseFyyd(_ data: Data?) -> [Result] {
        dicts(dict(object(data))["data"]).compactMap { item in
            let url = string(item, "xmlURL")
            guard !url.isEmpty else { return nil }
            let author = string(item, "author")
            return Result(title: string(item, "title").isEmpty ? url : string(item, "title"),
                          url: url, website: author.isEmpty ? nil : author, source: "fyyd")
        }
    }

    // MARK: Podverse

    static func searchPodverse(term: String) async -> [Result] {
        parsePodverse(await jsonData("https://api.podverse.fm/api/v1/podcast?searchTitle=\(query(term))"))
    }

    static func parsePodverse(_ data: Data?) -> [Result] {
        // Response shape: [ [items...], total_count ]
        guard let array = object(data) as? [Any], let first = array.first else { return [] }
        return dicts(first).compactMap { item in
            let feedURL = dicts(item["feedUrls"]).first?["url"] as? String ?? ""
            guard !feedURL.isEmpty else { return nil }
            return Result(title: string(item, "title").isEmpty ? feedURL : string(item, "title"),
                          url: feedURL, website: nil, source: "Podverse")
        }
    }

    // MARK: Feedly

    static func searchFeedly(term: String) async -> [Result] {
        parseFeedly(await jsonData("https://cloud.feedly.com/v3/search/feeds?q=\(query(term))"))
    }

    static func parseFeedly(_ data: Data?) -> [Result] {
        dicts(dict(object(data))["results"]).compactMap { item in
            let feedID = string(item, "feedId")
            guard feedID.hasPrefix("feed/") else { return nil }
            let url = String(feedID.dropFirst("feed/".count))
            return Result(title: string(item, "title").isEmpty ? url : string(item, "title"),
                          url: url, website: nil, source: "Feedly")
        }
    }

    // MARK: NewsBlur

    static func searchNewsBlur(term: String) async -> [Result] {
        parseNewsBlur(await jsonData("https://www.newsblur.com/discover/autocomplete?term=\(query(term))&v=2"))
    }

    static func parseNewsBlur(_ data: Data?) -> [Result] {
        let root = object(data)
        let feeds = dicts(dict(root)["feeds"]).isEmpty ? dicts(root) : dicts(dict(root)["feeds"])
        var seen = Set<String>()
        return feeds.compactMap { item in
            let url = string(item, "value").isEmpty ? string(item, "address") : string(item, "value")
            guard url.contains("://"), !url.allSatisfy(\.isNumber), seen.insert(url).inserted else { return nil }
            return Result(title: string(item, "label").isEmpty ? url : string(item, "label"),
                          url: url, website: nil, source: "NewsBlur")
        }
    }

    // MARK: Reddit

    static func searchReddit(term: String) async -> [Result] {
        parseReddit(await jsonData("https://www.reddit.com/subreddits/search.json?q=\(query(term))&limit=10"))
    }

    static func parseReddit(_ data: Data?) -> [Result] {
        dicts(dict(dict(object(data))["data"])["children"]).compactMap { child in
            let sub = dict(child["data"])
            let name = string(sub, "display_name")
            guard !name.isEmpty else { return nil }
            return Result(title: "r/\(name)", url: "https://www.reddit.com/r/\(name)/.rss",
                          website: "https://www.reddit.com/r/\(name)", source: "Reddit")
        }
    }

    // MARK: Lemmy and PieFed (Lemmy-shaped community search)

    static func searchLemmy(term: String) async -> [Result] {
        parseCommunities(await jsonData("https://lemmy.world/api/v3/search?q=\(query(term))&type_=Communities&sort=TopAll&limit=15"),
                         source: "Lemmy")
    }

    static func searchPieFed(term: String) async -> [Result] {
        parseCommunities(await jsonData("https://piefed.social/api/alpha/search?q=\(query(term))&type_=Communities&limit=10"),
                         source: "PieFed")
    }

    /// Converts community actor URLs the way the desktop does:
    /// .../c/name becomes <instance>/feeds/c/name.xml, /m/name gains /rss.
    static func communityFeedURL(actorID: String) -> String? {
        if let range = actorID.range(of: "/c/") {
            let base = String(actorID[..<range.lowerBound])
            let name = String(actorID[range.upperBound...]).split(separator: "/").first.map(String.init) ?? ""
            guard !name.isEmpty else { return nil }
            return "\(base)/feeds/c/\(name).xml"
        }
        if actorID.contains("/m/") { return actorID + "/rss" }
        return nil
    }

    static func parseCommunities(_ data: Data?, source: String) -> [Result] {
        dicts(dict(object(data))["communities"]).compactMap { item in
            let community = dict(item["community"])
            let actor = string(community, "actor_id")
            guard let url = communityFeedURL(actorID: actor) else { return nil }
            let title = string(community, "title").isEmpty ? string(community, "name") : string(community, "title")
            return Result(title: title, url: url, website: actor, source: source)
        }
    }

    // MARK: Mastodon

    static func searchMastodon(term: String) async -> [Result] {
        var url = "https://mastodon.social/api/v2/search?q=\(query(term))&limit=12"
        if term.contains("@"), term.contains(".") { url += "&resolve=true" }
        return parseMastodon(await jsonData(url), instance: "https://mastodon.social")
    }

    static func parseMastodon(_ data: Data?, instance: String) -> [Result] {
        let root = dict(object(data))
        var results = dicts(root["accounts"]).compactMap { account -> Result? in
            let profile = string(account, "url")
            guard !profile.isEmpty else { return nil }
            let name = string(account, "display_name").isEmpty ? string(account, "username") : string(account, "display_name")
            return Result(title: name, url: profile.hasSuffix("/") ? profile + "rss" : profile + ".rss",
                          website: profile, source: "Mastodon")
        }
        results += dicts(root["hashtags"]).compactMap { tag -> Result? in
            let name = string(tag, "name")
            guard !name.isEmpty else { return nil }
            return Result(title: "#\(name)", url: "\(instance)/tags/\(name).rss",
                          website: "\(instance)/tags/\(name)", source: "Mastodon")
        }
        return results
    }

    // MARK: Bluesky

    static func searchBluesky(term: String) async -> [Result] {
        parseBluesky(await jsonData("https://public.api.bsky.app/xrpc/app.bsky.actor.searchActors?q=\(query(term))&limit=12"))
    }

    static func parseBluesky(_ data: Data?) -> [Result] {
        dicts(dict(object(data))["actors"]).compactMap { actor in
            let handle = string(actor, "handle")
            guard !handle.isEmpty else { return nil }
            let name = string(actor, "displayName").isEmpty ? handle : string(actor, "displayName")
            return Result(title: name, url: "https://bsky.app/profile/\(handle)/rss",
                          website: "https://bsky.app/profile/\(handle)", source: "Bluesky")
        }
    }

    // MARK: Groups.io (public directory pages are HTML)

    static func searchGroupsIO(term: String) async -> [Result] {
        guard let data = await fetch("https://groups.io/search?q=\(query(term))", acceptHTML: true),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else { return [] }
        return parseGroupsIO(html)
    }

    /// Group links look like href="/g/<name>" or the full URL; each becomes
    /// the group's native https://groups.io/g/<name>/rss feed.
    static func parseGroupsIO(_ html: String) -> [Result] {
        var results: [Result] = []
        var seen = Set<String>()
        for anchor in anchors(in: html) {
            guard let range = anchor.href.range(of: "/g/") else { continue }
            let name = anchor.href[range.upperBound...].split(separator: "/").first.map(String.init) ?? ""
            guard !name.isEmpty, name != "search", seen.insert(name).inserted else { continue }
            results.append(Result(title: anchor.text.isEmpty ? name : anchor.text,
                                  url: "https://groups.io/g/\(name)/rss",
                                  website: "https://groups.io/g/\(name)", source: "Groups.io"))
            if results.count >= 20 { break }
        }
        return results
    }

    // MARK: Feedspot (curated topic pages are HTML)

    static func searchFeedspot(term: String) async -> [Result] {
        let slug = term.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
            .reduce(into: "") { if $1 != "_" || !$0.hasSuffix("_") { $0.append($1) } }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard !slug.isEmpty,
              let data = await fetch("https://rss.feedspot.com/\(slug)_rss_feeds/", acceptHTML: true),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else { return [] }
        return parseFeedspot(html)
    }

    /// Each entry is a title anchor inside a feed_heading element followed
    /// by the feed-URL anchor (class "ext" without "extdomain").
    static func parseFeedspot(_ html: String) -> [Result] {
        var results: [Result] = []
        var seen = Set<String>()
        var pendingTitle = ""
        for anchor in anchors(in: html) {
            if anchor.insideFeedHeading { pendingTitle = anchor.text; continue }
            guard anchor.classes.contains("ext"), !anchor.classes.contains("extdomain") else { continue }
            let href = anchor.href
            guard let host = URL(string: href)?.host, !host.hasSuffix("feedspot.com"),
                  seen.insert(href).inserted else { continue }
            results.append(Result(title: pendingTitle.isEmpty ? host : pendingTitle,
                                  url: href, website: nil, source: "Feedspot"))
            pendingTitle = ""
            if results.count >= 50 { break }
        }
        return results
    }

    // MARK: Minimal anchor scanning for the two HTML directories

    struct Anchor {
        var href: String
        var classes: Set<String>
        var text: String
        var insideFeedHeading: Bool
    }

    /// Scans <a ...>text</a> tags in document order. Feedspot headings are
    /// approximated: an anchor counts as a heading when its parent tag
    /// (the nearest preceding tag) carries the feed_heading class.
    static func anchors(in html: String) -> [Anchor] {
        var anchors: [Anchor] = []
        let lower = html.lowercased()
        var position = lower.startIndex
        var lastTagClass = ""
        while let open = lower.range(of: "<", range: position..<lower.endIndex) {
            guard let close = lower.range(of: ">", range: open.upperBound..<lower.endIndex) else { break }
            let tag = String(html[open.lowerBound..<close.upperBound])
            let tagLower = String(lower[open.lowerBound..<close.upperBound])
            position = close.upperBound
            if tagLower.hasPrefix("<a ") || tagLower.hasPrefix("<a>") || tagLower.hasPrefix("<a\n") {
                let href = attribute("href", in: tag) ?? ""
                let classes = Set((attribute("class", in: tag) ?? "").split(separator: " ").map(String.init))
                var text = ""
                if let end = lower.range(of: "</a>", range: position..<lower.endIndex) {
                    text = HTMLText.plainText(from: String(html[position..<end.lowerBound]))
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                }
                anchors.append(Anchor(href: href, classes: classes, text: text,
                                      insideFeedHeading: lastTagClass.contains("feed_heading")))
                // A parent class applies to the one anchor it wraps.
                lastTagClass = ""
            } else if !tagLower.hasPrefix("</") {
                if let cls = attribute("class", in: tag) { lastTagClass = cls }
            }
        }
        return anchors
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let range = tag.range(of: "\(name)=", options: .caseInsensitive) else { return nil }
        let rest = tag[range.upperBound...]
        if let first = rest.first, first == "\"" || first == "'" {
            let afterQuote = rest.dropFirst()
            return afterQuote.split(separator: first).first.map(String.init)
        }
        return rest.split(separator: " ").first.map(String.init)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ">")) }
    }
}

// MARK: - Social URL resolution (desktop get_social_feed_url)

/// Converts profile and community page URLs into their native feed URLs
/// when a user pastes one into Add Feed. Only pattern conversions that
/// need no account and no page fetch live here; YouTube channel pages
/// (/@handle, /c/name) are resolved by scraping the channel id below.
enum SocialResolver {
    static func feedURL(forPageURL raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased(),
              url.scheme == "http" || url.scheme == "https" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let base = "\(url.scheme ?? "https")://\(url.host ?? host)"

        // YouTube playlist and channel-id URLs convert directly.
        if host.contains("youtube.com") {
            if url.path == "/playlist",
               let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "list" })?.value, !id.isEmpty {
                return "https://www.youtube.com/feeds/videos.xml?playlist_id=\(id)"
            }
            if parts.count == 2, parts[0] == "channel" {
                return "https://www.youtube.com/feeds/videos.xml?channel_id=\(parts[1])"
            }
            return nil
        }
        // Reddit subreddit and user pages.
        if host.contains("reddit.com"), parts.count >= 2 {
            if parts[0] == "r" { return "https://www.reddit.com/r/\(parts[1])/.rss" }
            if parts[0] == "user" || parts[0] == "u" { return "https://www.reddit.com/user/\(parts[1])/.rss" }
            return nil
        }
        // Bluesky profiles.
        if host.contains("bsky.app"), parts.count >= 2, parts[0] == "profile" {
            return "https://bsky.app/profile/\(parts[1])/rss"
        }
        // Groups.io group pages.
        if host == "groups.io" || host.hasSuffix(".groups.io"), parts.count >= 2, parts[0] == "g" {
            return "https://\(host)/g/\(parts[1])/rss"
        }
        // Lemmy communities (/c/name) and Kbin magazines (/m/name).
        if parts.count >= 2, parts[0] == "c" {
            return "\(base)/feeds/c/\(parts[1]).xml"
        }
        if parts.count >= 2, parts[0] == "m" {
            return "\(base)/m/\(parts[1])/rss"
        }
        // Mixcloud user pages: the documented public API's cloudcast
        // list, which FeedParser reads as a feed (research 0.1.13).
        if host == "www.mixcloud.com" || host == "mixcloud.com", parts.count == 1 {
            return "https://api.mixcloud.com/\(parts[0])/cloudcasts/?limit=100"
        }
        // GitHub repository pages: the repo's release feed.
        if host == "github.com", parts.count == 2,
           !["search", "explore", "topics", "settings", "login", "signup", "features", "about"].contains(parts[0]) {
            return "https://github.com/\(parts[0])/\(parts[1])/releases.atom"
        }
        // Mastodon-style profile and tag pages (/@user, /tags/name) on any
        // host: the profile itself gains .rss.
        if parts.count == 1, parts[0].hasPrefix("@") {
            return "\(base)/\(parts[0]).rss"
        }
        if parts.count == 2, parts[0] == "tags" {
            return "\(base)/tags/\(parts[1]).rss"
        }
        return nil
    }

    static func isSoundCloudProfile(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(), host == "soundcloud.com" || host == "www.soundcloud.com"
        else { return false }
        // Profile pages are a single path segment ("/<artist>"); track
        // and playlist pages are two or more and are not subscriptions.
        return url.path.split(separator: "/").count == 1
    }

    /// A SoundCloud profile page carries the user's numeric id in its
    /// HTML ("soundcloud:users:<id>"); the native per-user RSS feed
    /// (feeds.soundcloud.com) hangs off that id — the same scrape
    /// pattern as YouTube channel pages (research 0.1.13). SoundCloud's
    /// API itself needs a client_id from a registration programme that
    /// has been closed since 2017; the RSS feed needs nothing.
    static func soundCloudFeedURL(pageURL raw: String) async -> String? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { return nil }
        return Self.soundCloudFeedURL(fromProfileHTML: html)
    }

    static func soundCloudFeedURL(fromProfileHTML html: String) -> String? {
        guard let start = html.range(of: "soundcloud:users:") else { return nil }
        let id = html[start.upperBound...].prefix(while: \.isNumber)
        guard id.count >= 4 else { return nil }
        return "https://feeds.soundcloud.com/users/soundcloud:users:\(id)/sounds.rss"
    }

    static func isYouTubeChannelPage(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(), host.contains("youtube.com") else { return false }
        let parts = url.path.split(separator: "/").map(String.init)
        return parts.count == 1 && parts[0].hasPrefix("@")
            || parts.count == 2 && (parts[0] == "c" || parts[0] == "user")
    }

    /// A YouTube channel page carries its channel id in the HTML
    /// ("channelId":"UC..."); the RSS feed hangs off that id.
    static func youTubeChannelFeedURL(pageURL raw: String) async -> String? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { return nil }
        return Self.channelFeedURL(fromChannelPageHTML: html)
    }

    static func channelFeedURL(fromChannelPageHTML html: String) -> String? {
        for marker in ["\"channelId\":\"", "\"externalId\":\"", "channel_id=", "/channel/"] {
            guard let start = html.range(of: marker) else { continue }
            let rest = html[start.upperBound...]
            let id = rest.prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
            if id.hasPrefix("UC"), id.count > 10 {
                return "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)"
            }
        }
        return nil
    }
}
