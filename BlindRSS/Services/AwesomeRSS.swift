// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation

/// The Awesome RSS catalogue (research round 0.1.13): the curated OPML
/// collection at github.com/plenaryapp/awesome-rss-feeds — one OPML
/// file per country (25) and per topic. The 0.1.12 audit rejected it
/// for "dozens of bulk OPML fetches per search"; the research found
/// the catalogue is lazy by design (the Plenary app fetches one file
/// when a country or topic is opened), so this port does the same:
/// opening an entry downloads exactly one OPML file and lists its
/// feeds, parsed by the app's existing OPML parser.
enum AwesomeRSSService {
    struct Entry: Identifiable, Equatable, Sendable {
        var name: String
        /// Path inside the repository, e.g. "countries/with_category/Canada.opml".
        var path: String
        var group: String
        var id: String { path }
    }

    static let rawBase = "https://raw.githubusercontent.com/plenaryapp/awesome-rss-feeds/master/"

    /// Countries, from the repository tree (countries/with_category).
    static let countries = [
        "Australia", "Bangladesh", "Brazil", "Canada", "France", "Germany",
        "Hong Kong SAR China", "India", "Indonesia", "Iran", "Ireland", "Italy",
        "Japan", "Mexico", "Myanmar (Burma)", "Nigeria", "Pakistan", "Philippines",
        "Poland", "Russia", "South Africa", "Spain", "Ukraine",
        "United Kingdom", "United States",
    ]

    /// Topics, from the repository tree (recommended/with_category).
    static let topics = [
        "Android", "Android Development", "Animal & Wildlife", "Apple",
        "Architecture", "Beauty", "Books", "Business & Economy", "Cars",
        "Chess", "Cricket", "Cryptocurrency", "Cyber security", "DIY",
        "Environment", "Fashion", "Food", "Football", "Funny", "Gaming",
        "History", "Interior design", "Memes", "Movies", "Music", "Nature",
        "News", "Personal finance", "Photography", "Programming", "Science",
        "Space", "Sports", "Startups", "Tech", "Television", "Tennis",
        "Travel", "UI - UX", "Web Development", "iOS Development",
    ]

    static var catalogue: [Entry] {
        countries.map { Entry(name: $0, path: "countries/with_category/\($0).opml", group: "Countries") }
            + topics.map { Entry(name: $0, path: "recommended/with_category/\($0).opml", group: "Topics") }
    }

    static func fileURL(for entry: Entry) -> URL? {
        guard let encoded = entry.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: rawBase + encoded)
    }

    /// Maps one parsed OPML file to Discover-style results; the OPML
    /// outline folders become the result's category detail.
    static func results(fromOPML data: Data, entry: Entry) -> [PodcastService.FeedResult] {
        OPMLService.parse(data: data).map { feed in
            PodcastService.FeedResult(title: feed.title.isEmpty ? feed.xmlURL : feed.title,
                                      url: feed.xmlURL,
                                      website: feed.category == Category.uncategorized ? nil : feed.category,
                                      source: "Awesome RSS: \(entry.name)")
        }
    }

    static func feeds(for entry: Entry) async -> [PodcastService.FeedResult] {
        guard let url = fileURL(for: entry),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return results(fromOPML: data, entry: entry)
    }
}
