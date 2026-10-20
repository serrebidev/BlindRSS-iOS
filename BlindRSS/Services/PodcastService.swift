// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation

/// Podcast-specific services: Podcasting 2.0 chapters documents, Apple
/// Podcasts search (desktop Finding Podcasts), and Wayback archive recovery
/// (desktop Podcast Archive).
enum PodcastService {
    // MARK: Chapters (https://podcastindex.org/namespace/1.0#chapters)

    struct ChaptersDocument: Decodable {
        struct Item: Decodable {
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

    struct SearchResult: Decodable, Identifiable {
        let collectionId: Int
        let collectionName: String?
        let artistName: String?
        let feedUrl: String?
        var id: Int { collectionId }
        var title: String { collectionName ?? "Podcast" }
    }

    private struct SearchResponse: Decodable { let results: [SearchResult] }

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

    struct FeedResult: Decodable, Identifiable {
        let title: String
        let url: String
        let website: String?
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

    private struct FeedsearchResponse: Decodable {
        struct Item: Decodable { let url: String; let title: String?; let favicon: String? }
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

    struct ArchiveAvailability: Decodable {
        struct Snapshot: Decodable { let url: String?; let timestamp: String? }
        struct Closest: Decodable { let closest: Snapshot? }
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
