// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData
import UserNotifications

/// Feed fetching and library mutations. The iOS counterpart of the desktop
/// Local provider (providers/local.py): add/remove feeds, refresh with
/// per-feed error tracking, mark read state, OPML, and deleted-article restore.
/// Hosted providers (Miniflux, Inoreader, The Old Reader, BazQux) are Phase 2.
@MainActor
final class LibraryStore {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    // MARK: Feeds

    func addFeed(urlString: String, category: String = Category.uncategorized,
                 in context: ModelContext) async throws -> Feed {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http" || url.scheme == "https" else {
            throw LibraryError.invalidURL
        }
        let parsed = try await fetchFeed(at: url)
        let feed = Feed(id: url.absoluteString, url: url.absoluteString,
                        title: parsed.title, category: category, language: parsed.language)
        context.insert(feed)
        merge(entries: parsed.entries, into: feed, in: context)
        try context.save()
        Announcer.announce("Subscribed to \(feed.title). \(parsed.entries.count) articles.")
        return feed
    }

    func removeFeed(_ feed: Feed, in context: ModelContext) {
        let title = feed.title
        context.delete(feed)
        try? context.save()
        Announcer.announce("Removed feed \(title).")
    }

    func refresh(feed: Feed, in context: ModelContext) async {
        guard let url = URL(string: feed.url) else { return }
        do {
            let parsed = try await fetchFeed(at: url)
            if !feed.titleIsCustom { feed.title = parsed.title }
            feed.lastError = nil
            feed.lastSuccessAt = Date()
            feed.consecutiveFailures = 0
            let added = merge(entries: parsed.entries, into: feed, in: context)
            try context.save()
            if added > 0 { Announcer.announce("\(feed.title): \(added) new articles.") }
        } catch {
            feed.lastError = error.localizedDescription
            feed.lastErrorAt = Date()
            feed.consecutiveFailures += 1
            try? context.save()
        }
    }

    func refreshAll(feeds: [Feed], in context: ModelContext) async {
        var newTotal = 0
        for feed in feeds {
            let before = feed.articles.count
            await refresh(feed: feed, in: context)
            newTotal += max(0, feed.articles.count - before)
        }
        Announcer.announce("Refresh complete. \(newTotal) new articles.")
        if newTotal > 0, UserDefaults.standard.bool(forKey: "notificationsEnabled") {
            let content = UNMutableNotificationContent()
            content.title = "BlindRSS"
            content.body = "\(newTotal) new articles."
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    // MARK: Articles

    func setRead(_ article: Article, read: Bool, in context: ModelContext) {
        article.isRead = read
        if read { article.openedAt = Date() }
        try? context.save()
        Announcer.announce(read ? "Marked as read." : "Marked as unread.")
    }

    func toggleFavorite(_ article: Article, in context: ModelContext) {
        article.isFavorite.toggle()
        try? context.save()
        Announcer.announce(article.isFavorite ? "Added to favorites." : "Removed from favorites.")
    }

    func markAllRead(in articles: [Article], context: ModelContext) {
        for article in articles where !article.isRead { article.isRead = true }
        try? context.save()
        Announcer.announce("Marked \(articles.count) articles as read.")
    }

    /// Restores a deleted article from its snapshot and clears the tombstone.
    func restoreDeleted(_ deleted: DeletedArticle, in context: ModelContext) {
        guard let feed = (try? context.fetch(FetchDescriptor<Feed>()))?.first(where: { $0.id == deleted.feedID }) else { return }
        let article = Article(id: deleted.articleID, title: deleted.title ?? "Untitled",
                              url: deleted.url ?? "", content: deleted.content ?? "",
                              summary: deleted.summary, dateRaw: deleted.dateRaw ?? "",
                              author: deleted.author ?? "", isRead: deleted.isRead ?? false,
                              isFavorite: deleted.isFavorite ?? false,
                              mediaURL: deleted.mediaURL, mediaType: deleted.mediaType, feed: feed)
        feed.articles.append(article)
        context.insert(article)
        context.delete(deleted)
        try? context.save()
        Announcer.announce("Restored \(article.title).")
    }

    func purgeDeleted(_ deleted: DeletedArticle, in context: ModelContext) {
        deleted.purged = true
        context.delete(deleted)
        try? context.save()
        Announcer.announce("Permanently deleted.")
    }

    /// Snapshots the article into DeletedArticle (tombstone), then removes it,
    /// matching desktop delete/restore in core/db.py.
    func deleteArticle(_ article: Article, in context: ModelContext) {
        guard let feed = article.feed else { return }
        context.insert(DeletedArticle(feedID: feed.id, article: article))
        context.delete(article)
        try? context.save()
        Announcer.announce("Deleted \(article.title).")
    }

    // MARK: Fetching

    private func fetchFeed(at url: URL) async throws -> ParsedFeed {
        var request = URLRequest(url: url)
        request.setValue("BlindRSS-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LibraryError.httpStatus(http.statusCode)
        }
        return try FeedParser.parse(data: data, sourceURL: url)
    }

    /// Inserts new entries, updates changed ones, respects delete tombstones.
    /// Returns the number of newly added articles.
    @discardableResult
    private func merge(entries: [ParsedEntry], into feed: Feed, in context: ModelContext) -> Int {
        let feedID = feed.id
        let tombstones = (try? context.fetch(FetchDescriptor<DeletedArticle>(
            predicate: #Predicate { $0.feedID == feedID }))) ?? []
        let tombstonedIDs = Set(tombstones.map(\.articleID))
        var added = 0
        for entry in entries {
            let articleID = "\(feed.id):\(entry.guid)"
            if tombstonedIDs.contains(articleID) || tombstonedIDs.contains(entry.guid) { continue }
            if let existing = feed.articles.first(where: { $0.id == articleID }) {
                existing.title = entry.title
                existing.content = entry.contentHTML.isEmpty ? (entry.summaryHTML ?? "") : entry.contentHTML
                existing.summary = entry.summaryHTML
                existing.date = entry.date
                existing.dateRaw = entry.dateRaw
                existing.author = entry.author
                existing.mediaURL = entry.mediaURL
                existing.mediaType = entry.mediaType
            } else {
                let article = Article(
                    id: articleID, title: entry.title, url: entry.link,
                    content: entry.contentHTML.isEmpty ? (entry.summaryHTML ?? "") : entry.contentHTML,
                    summary: entry.summaryHTML, date: entry.date, dateRaw: entry.dateRaw,
                    author: entry.author, mediaURL: entry.mediaURL,
                    mediaType: entry.mediaType, feed: feed)
                feed.articles.append(article)
                context.insert(article)
                added += 1
                applyFilterRules(to: article, in: context)
            }
        }
        return added
    }

    /// Desktop Filter Rules: mark read, favorite, or delete on arrival.
    private func applyFilterRules(to article: Article, in context: ModelContext) {
        let rules = (try? context.fetch(FetchDescriptor<FilterRule>(sortBy: [SortDescriptor(\.position)]))) ?? []
        for rule in rules where rule.matches(article) {
            switch rule.action {
            case "favorite": article.isFavorite = true
            case "delete": deleteArticle(article, in: context); return
            default: article.isRead = true
            }
        }
    }
}

enum LibraryError: LocalizedError {
    case invalidURL
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "That is not a valid feed URL."
        case .httpStatus(let code): return "The feed server returned HTTP \(code)."
        }
    }
}
