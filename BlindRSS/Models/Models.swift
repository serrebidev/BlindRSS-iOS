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
    /// The description the feed itself publishes (desktop View Feed Description).
    var feedDescription: String?
    /// Whether new articles from this feed count toward the new-article
    /// notification (desktop Feed Properties: notifications for this feed).
    var notificationsEnabled: Bool = true
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

    /// Mirrored from a hosted account (Providers.swift id prefixes). These
    /// refresh through the account, never by fetching their feed URL.
    var isHosted: Bool { id.hasPrefix("miniflux:") || id.hasPrefix("greader:") }
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
    /// Podcasting 2.0 chapters document URL from the feed, if any.
    var chapterURL: String?
    /// Extra categories a Filter Rule labeled this article with (desktop
    /// article_labels). The article also shows under these categories.
    var labels: [String] = []
    /// Category a Filter Rule moved this article to (desktop rule "move").
    /// Shown there instead of only under its feed's category.
    var movedCategory: String?
    /// Moved out of its feed's list by the delete behaviour "move to
    /// category": visible only under `movedCategory`.
    var hiddenFromFeed: Bool = false
    /// Local filename in Documents/Downloads once the media is downloaded.
    var localFileName: String?
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

/// Desktop table: smart_folders (id, name, rule_json, position).
/// Rule fields are the iOS form of the desktop rule tree leaves.
@Model
final class SmartFolder {
    @Attribute(.unique) var id: String
    var name: String
    /// all, unread, or favorites
    var readState: String
    var titleContains: String
    var feedTitleContains: String
    var hasMediaOnly: Bool
    var position: Int

    init(name: String, readState: String = "all", titleContains: String = "",
         feedTitleContains: String = "", hasMediaOnly: Bool = false, position: Int = 0) {
        self.id = UUID().uuidString
        self.name = name
        self.readState = readState
        self.titleContains = titleContains
        self.feedTitleContains = feedTitleContains
        self.hasMediaOnly = hasMediaOnly
        self.position = position
    }

    func matches(_ article: Article) -> Bool {
        switch readState {
        case "unread": if article.isRead { return false }
        case "favorites": if !article.isFavorite { return false }
        default: break
        }
        if !titleContains.isEmpty,
           !article.title.localizedCaseInsensitiveContains(titleContains) { return false }
        if !feedTitleContains.isEmpty,
           !(article.feed?.title.localizedCaseInsensitiveContains(feedTitleContains) ?? false) { return false }
        if hasMediaOnly, !article.hasMedia { return false }
        return true
    }
}

/// The combined effect of every Filter Rule that matched one article
/// (desktop core/filters.py evaluate_pipeline). Boolean actions OR
/// together, the last move wins, labels union in first-seen order.
struct FilterEffects: Equatable {
    var markRead = false
    var favorite = false
    var delete = false
    var skipNotification = false
    var moveCategory: String?
    var labels: [String] = []
}

/// Desktop table: filter_rules (id, name, rule_json, actions_json, enabled, stop, position).
/// Applied to articles as they arrive during refresh. The action set is the
/// desktop one: mark read, favorite, delete, skip notification, move to a
/// category, and label with a category; a rule flagged stop ends the
/// pipeline for that article once it has matched.
@Model
final class FilterRule {
    @Attribute(.unique) var id: String
    var name: String
    /// title, content, feed, or author
    var field: String
    var contains: String
    /// Legacy single action (markRead, favorite, or delete) kept for rules
    /// saved before the full action set; used when no do* flag is set.
    var action: String
    var doMarkRead: Bool = false
    var doFavorite: Bool = false
    var doDelete: Bool = false
    var skipNotification: Bool = false
    /// Category to move matching articles to ("" = no move).
    var moveCategory: String = ""
    /// Category to also label matching articles with ("" = no label).
    var labelCategory: String = ""
    /// Stop processing later rules for an article this rule matched.
    var stop: Bool = false
    var enabled: Bool
    var position: Int

    init(name: String, field: String = "title", contains: String = "",
         action: String = "markRead", enabled: Bool = true, position: Int = 0) {
        self.id = UUID().uuidString
        self.name = name
        self.field = field
        self.contains = contains
        self.action = action
        self.enabled = enabled
        self.position = position
    }

    func matches(_ article: Article) -> Bool {
        guard enabled, !contains.isEmpty else { return false }
        let haystack: String
        switch field {
        case "content": haystack = HTMLText.plainText(from: article.content)
        case "feed": haystack = article.feed?.title ?? ""
        case "author": haystack = article.author
        default: haystack = article.title
        }
        return haystack.localizedCaseInsensitiveContains(contains)
    }

    /// This rule's boolean actions: the do* flags, falling back to the
    /// legacy single action for rules saved before they existed.
    var effectiveActions: (markRead: Bool, favorite: Bool, delete: Bool) {
        // The legacy fallback applies only when the rule carries no
        // new-style action at all; a rule whose only actions are
        // skip/move/label must not resurrect its legacy single action.
        if doMarkRead || doFavorite || doDelete || skipNotification
            || !moveCategory.isEmpty || !labelCategory.isEmpty {
            return (doMarkRead, doFavorite, doDelete)
        }
        return (action == "markRead", action == "favorite", action == "delete")
    }

    /// True when the rule would do nothing (desktop rejects such rules).
    var hasNoActions: Bool {
        let actions = effectiveActions
        return !actions.markRead && !actions.favorite && !actions.delete
            && !skipNotification && moveCategory.isEmpty && labelCategory.isEmpty
    }

    /// Runs the ordered pipeline over one article (desktop evaluate_pipeline).
    static func pipeline(rules: [FilterRule], article: Article) -> FilterEffects {
        var effects = FilterEffects()
        for rule in rules where rule.matches(article) {
            let actions = rule.effectiveActions
            effects.markRead = effects.markRead || actions.markRead
            effects.favorite = effects.favorite || actions.favorite
            effects.delete = effects.delete || actions.delete
            effects.skipNotification = effects.skipNotification || rule.skipNotification
            if !rule.moveCategory.isEmpty { effects.moveCategory = rule.moveCategory }
            if !rule.labelCategory.isEmpty, !effects.labels.contains(rule.labelCategory) {
                effects.labels.append(rule.labelCategory)
            }
            if rule.stop { break }
        }
        return effects
    }
}

/// Desktop persistent searches: a saved search term kept as its own item,
/// re-evaluated against the current articles whenever it is opened.
@Model
final class SavedSearch {
    @Attribute(.unique) var id: String
    var name: String
    var term: String
    var position: Int

    init(name: String, term: String, position: Int = 0) {
        self.id = UUID().uuidString
        self.name = name
        self.term = term
        self.position = position
    }

    /// Same fields the article list search matches.
    func matches(_ article: Article, titlesOnly: Bool = false) -> Bool {
        if article.title.localizedCaseInsensitiveContains(term) { return true }
        if titlesOnly { return false }
        return article.content.localizedCaseInsensitiveContains(term)
            || article.author.localizedCaseInsensitiveContains(term)
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
