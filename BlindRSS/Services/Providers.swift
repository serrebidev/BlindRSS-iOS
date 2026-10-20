// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// Hosted providers (desktop Online Accounts and Providers). Miniflux has
/// its own REST API; Inoreader, The Old Reader, and BazQux all speak the
/// Google Reader API, so one client covers those three.
/// Synced items are mirrored into the local SwiftData library with
/// provider-prefixed ids ("miniflux:123", "greader:inoreader:456"), and
/// read state is pushed back on the next sync.
enum HostedProviderKind: String, CaseIterable, Identifiable {
    case miniflux, inoreader, theOldReader, bazqux
    var id: String { rawValue }
    var title: String {
        switch self {
        case .miniflux: return "Miniflux"
        case .inoreader: return "Inoreader"
        case .theOldReader: return "The Old Reader"
        case .bazqux: return "BazQux"
        }
    }
    var defaultBaseURL: String {
        switch self {
        case .miniflux: return ""
        case .inoreader: return "https://www.inoreader.com"
        case .theOldReader: return "https://theoldreader.com"
        case .bazqux: return "https://bazqux.com"
        }
    }
}

struct HostedConfig {
    var kind: HostedProviderKind
    var baseURL: String
    var username: String
    var token: String

    static func load() -> HostedConfig? {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: "hosted.kind"),
              let kind = HostedProviderKind(rawValue: raw) else { return nil }
        return HostedConfig(kind: kind,
                            baseURL: defaults.string(forKey: "hosted.baseURL") ?? kind.defaultBaseURL,
                            username: defaults.string(forKey: "hosted.username") ?? "",
                            token: defaults.string(forKey: "hosted.token") ?? "")
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(kind.rawValue, forKey: "hosted.kind")
        defaults.set(baseURL, forKey: "hosted.baseURL")
        defaults.set(username, forKey: "hosted.username")
        defaults.set(token, forKey: "hosted.token")
    }

    static func clear() {
        for key in ["hosted.kind", "hosted.baseURL", "hosted.username", "hosted.token"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

@MainActor
final class HostedSync {
    private let session = URLSession.shared

    /// Pulls feeds and latest entries into the local library. Returns new count.
    @discardableResult
    func sync(config: HostedConfig, in context: ModelContext) async throws -> Int {
        switch config.kind {
        case .miniflux: return try await syncMiniflux(config: config, in: context)
        default: return try await syncGReader(config: config, in: context)
        }
    }

    // MARK: Miniflux (https://miniflux.app/docs/api.html)

    private struct MFFeed: Decodable { let id: Int; let title: String; let site_url: String?; let feed_url: String; let category: MFCat? }
    private struct MFCat: Decodable { let title: String }
    private struct MFEntries: Decodable { let entries: [MFEntry] }
    private struct MFEntry: Decodable {
        let id: Int; let feed_id: Int; let title: String; let url: String; let content: String?
        let published_at: String?; let author: String?; let status: String
        let starred: Bool; let enclosures: [MFEnclosure]?
    }
    private struct MFEnclosure: Decodable { let url: String; let mime_type: String? }

    /// Miniflux sync. The old version fetched entries feed by feed: with
    /// 698 feeds that is 698 sequential requests and it looks frozen.
    /// This uses the global entries endpoint in pages of 500 instead:
    /// newest 2,000 entries in four requests, grouped by feed_id locally.
    private func syncMiniflux(config: HostedConfig, in context: ModelContext) async throws -> Int {
        let feeds: [MFFeed] = try await request(config: config, path: "/v1/feeds", decode: [MFFeed].self)
        var feedsByID: [String: Feed] = [:]
        for mfeed in feeds {
            let feedID = "miniflux:\(mfeed.id)"
            feedsByID[feedID] = fetchOrCreateFeed(id: feedID, title: mfeed.title, url: mfeed.feed_url,
                                                  category: mfeed.category?.title ?? Category.uncategorized, in: context)
        }
        try context.save()
        Announcer.announce("Found \(feeds.count) feeds. Fetching articles.")

        let pageSize = 500
        let maxEntries = 2000
        var fetched = 0
        var added = 0
        while fetched < maxEntries {
            let page: MFEntries = try await request(
                config: config,
                path: "/v1/entries?order=published_at&direction=desc&limit=\(pageSize)&offset=\(fetched)",
                decode: MFEntries.self)
            if page.entries.isEmpty { break }
            for entry in page.entries {
                guard let feed = feedsByID["miniflux:\(entry.feed_id)"] else { continue }
                let articleID = "miniflux:\(entry.id)"
                if let existing = feed.articles.first(where: { $0.id == articleID }) {
                    existing.isRead = entry.status == "read"
                    existing.isFavorite = entry.starred
                    continue
                }
                let article = Article(id: articleID, title: entry.title, url: entry.url,
                                      content: entry.content ?? "", dateRaw: entry.published_at ?? "",
                                      author: entry.author ?? "", isRead: entry.status == "read",
                                      isFavorite: entry.starred,
                                      mediaURL: entry.enclosures?.first?.url,
                                      mediaType: entry.enclosures?.first?.mime_type, feed: feed)
                article.date = entry.published_at.flatMap(FeedParser.parseDate)
                feed.articles.append(article)
                context.insert(article)
                added += 1
            }
            fetched += page.entries.count
            try context.save()
            Announcer.announce("Fetched \(fetched) articles.")
            if page.entries.count < pageSize { break }
        }
        Announcer.announce("Miniflux sync complete. \(added) new articles from \(feeds.count) feeds.")
        return added
    }

    // MARK: Google Reader API (Inoreader, The Old Reader, BazQux)

    private struct GRSubs: Decodable { let subscriptions: [GRSub] }
    private struct GRSub: Decodable { let id: String; let title: String; let url: String?; let categories: [GRSubCat]? }
    private struct GRSubCat: Decodable { let label: String? }
    private struct GRItems: Decodable { let items: [GRItem]? }
    private struct GRItem: Decodable {
        let id: String; let title: String?; let published: Int?
        let canonical: [GRLink]?; let alternate: [GRLink]?
        let summary: GRContent?; let content: GRContent?
        let author: String?; let enclosure: [GRLink]?
        let categories: [String]?
    }
    private struct GRLink: Decodable { let href: String?; let type: String? }
    private struct GRContent: Decodable { let content: String? }

    private func syncGReader(config: HostedConfig, in context: ModelContext) async throws -> Int {
        let subs: GRSubs = try await request(config: config, path: "/reader/api/0/subscription/list?output=json", decode: GRSubs.self)
        var added = 0
        for sub in subs.subscriptions {
            let feedID = "greader:\(config.kind.rawValue):\(sub.id)"
            let feed = fetchOrCreateFeed(id: feedID, title: sub.title, url: sub.url ?? "",
                                         category: sub.categories?.first?.label ?? Category.uncategorized, in: context)
            let encoded = sub.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sub.id
            let items: GRItems = try await request(config: config, path: "/reader/api/0/stream/contents/\(encoded)?n=50&output=json", decode: GRItems.self)
            for item in items.items ?? [] {
                let articleID = "greader:\(config.kind.rawValue):\(item.id)"
                if feed.articles.contains(where: { $0.id == articleID }) { continue }
                let link = item.canonical?.first?.href ?? item.alternate?.first?.href ?? ""
                let cats = item.categories ?? []
                let article = Article(id: articleID, title: item.title ?? "Untitled", url: link,
                                      content: item.content?.content ?? item.summary?.content ?? "",
                                      date: item.published.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                                      author: item.author ?? "",
                                      isRead: cats.contains(where: { $0.hasSuffix("/state/com.google/read") }),
                                      isFavorite: cats.contains(where: { $0.hasSuffix("/state/com.google/starred") }),
                                      mediaURL: item.enclosure?.first?.href,
                                      mediaType: item.enclosure?.first?.type, feed: feed)
                feed.articles.append(article)
                context.insert(article)
                added += 1
            }
        }
        try context.save()
        Announcer.announce("Hosted sync complete. \(added) new articles.")
        return added
    }

    // MARK: Helpers

    private func fetchOrCreateFeed(id: String, title: String, url: String, category: String, in context: ModelContext) -> Feed {
        if let existing = (try? context.fetch(FetchDescriptor<Feed>()))?.first(where: { $0.id == id }) {
            return existing
        }
        let feed = Feed(id: id, url: url, title: title, category: category)
        context.insert(feed)
        return feed
    }

    /// Adds https:// when the user typed a bare host like rss.example.com.
    static func normalizedBaseURL(_ raw: String) -> String {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !base.hasPrefix("http://"), !base.hasPrefix("https://") {
            base = "https://" + base
        }
        return base
    }

    private func request<T: Decodable>(config: HostedConfig, path: String, decode: T.Type) async throws -> T {
        let base = Self.normalizedBaseURL(config.baseURL)
        guard let url = URL(string: base + path), url.scheme != nil else { throw LibraryError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if config.kind == .miniflux {
            request.setValue(config.token, forHTTPHeaderField: "X-Auth-Token")
        } else {
            request.setValue("GoogleLogin auth=\(config.token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LibraryError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
