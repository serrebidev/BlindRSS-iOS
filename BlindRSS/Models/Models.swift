// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

// SwiftData mirror of the desktop SQLite schema (core/db.py in BlindRSS).
// Desktop table names are kept in comments so a future importer can map a
// desktop rss.db onto these models field for field.

/// Desktop table: feeds (id, url, title, title_is_custom, category, icon_url)
@Model
final class Feed {
    @Attribute(.unique) var id: String
    var url: String
    var title: String
    var titleIsCustom: Bool
    var category: String
    var iconURL: String?
    /// BCP-47 tag the feed declares for its content, if any (desktop Feed.language).
    var language: String?
    var lastError: String?
    var lastErrorAt: Date?
    var lastSuccessAt: Date?
    var consecutiveFailures: Int

    @Relationship(deleteRule: .cascade, inverse: \Article.feed)
    var articles: [Article]

    init(id: String, url: String, title: String, titleIsCustom: Bool = false,
         category: String = Category.uncategorized, iconURL: String? = nil, language: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.titleIsCustom = titleIsCustom
        self.category = category
        self.iconURL = iconURL
        self.language = language
        self.consecutiveFailures = 0
        self.articles = []
    }

    var unreadCount: Int { articles.filter { !$0.isRead }.count }
}

/// Desktop table: articles (id, feed_id, title, url, content, description,
/// date, author, is_read, is_favorite, media_url, media_type, chapter_url, opened_at)
@Model
final class Article {
    @Attribute(.unique) var id: String
    var title: String
    var url: String
    var content: String
    var summary: String?
    var date: Date?
    /// Original date string from the feed, kept for parity with desktop `date TEXT`.
    var dateRaw: String
    var author: String
    var isRead: Bool
    var isFavorite: Bool
    var mediaURL: String?
    var mediaType: String?
    var openedAt: Date?

    var feed: Feed?

    @Relationship(deleteRule: .cascade, inverse: \Chapter.article)
    var chapters: [Chapter]

    init(id: String, title: String, url: String, content: String, summary: String? = nil,
         date: Date? = nil, dateRaw: String = "", author: String = "",
         isRead: Bool = false, isFavorite: Bool = false,
         mediaURL: String? = nil, mediaType: String? = nil, feed: Feed? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.content = content
        self.summary = summary
        self.date = date
        self.dateRaw = dateRaw
        self.author = author
        self.isRead = isRead
        self.isFavorite = isFavorite
        self.mediaURL = mediaURL
        self.mediaType = mediaType
        self.feed = feed
        self.chapters = []
    }

    var hasMedia: Bool { !(mediaURL ?? "").isEmpty }
}

/// Desktop table: categories (id, title). Flat in Phase 1; the desktop local
/// provider nests categories with parent-path strings, which maps to `parent`.
@Model
final class Category {
    static let uncategorized = "Uncategorized"

    @Attribute(.unique) var id: String
    @Attribute(.unique) var title: String
    var parent: String?

    init(title: String, parent: String? = nil) {
        self.id = title
        self.title = title
        self.parent = parent
    }
}

/// Desktop table: chapters (id, article_id, start, title, href)
@Model
final class Chapter {
    @Attribute(.unique) var id: String
    var start: Double
    var title: String
    var href: String?

    var article: Article?

    init(id: String, start: Double, title: String, href: String? = nil, article: Article? = nil) {
        self.id = id
        self.start = start
        self.title = title
        self.href = href
        self.article = article
    }
}

/// Desktop table: playback_state (id, position_ms, duration_ms, updated_at, completed, title)
@Model
final class PlaybackState {
    @Attribute(.unique) var id: String
    var position: TimeInterval
    var duration: TimeInterval?
    var updatedAt: Date
    var completed: Bool
    var title: String?

    init(id: String, position: TimeInterval, duration: TimeInterval? = nil,
         completed: Bool = false, title: String? = nil) {
        self.id = id
        self.position = position
        self.duration = duration
        self.updatedAt = Date()
        self.completed = completed
        self.title = title
    }
}

/// Desktop table: deleted_articles. Snapshot plus tombstone: the row keeps a
/// deleted article restorable and stops refresh from resurrecting it.
@Model
final class DeletedArticle {
    @Attribute(.unique) var id: String
    var feedID: String
    var articleID: String
    var url: String?
    var deletedAt: Date
    var title: String?
    var content: String?
    var summary: String?
    var dateRaw: String?
    var author: String?
    var mediaURL: String?
    var mediaType: String?
    var isRead: Bool?
    var isFavorite: Bool?
    var purged: Bool

    init(feedID: String, article: Article) {
        self.id = "\(feedID):\(article.id)"
        self.feedID = feedID
        self.articleID = article.id
        self.url = article.url
        self.deletedAt = Date()
        self.title = article.title
        self.content = article.content
        self.summary = article.summary
        self.dateRaw = article.dateRaw
        self.author = article.author
        self.mediaURL = article.mediaURL
        self.mediaType = article.mediaType
        self.isRead = article.isRead
        self.isFavorite = article.isFavorite
        self.purged = false
    }
}
