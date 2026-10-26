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
    private static var isRefreshingAll = false
    /// When the last Refresh All started, manual or automatic; the
    /// automatic refresh interval counts from here.
    static var lastRefreshAll: Date?

    /// Desktop refresh_interval choices that suit a phone, in seconds.
    /// 0 is Never (manual refresh only).
    static let refreshIntervals: [(seconds: Double, label: String)] = [
        (0, "Never"), (300, "Every 5 minutes"), (600, "Every 10 minutes"), (1800, "Every 30 minutes"),
        (3600, "Every hour"), (7200, "Every 2 hours"), (86400, "Every day"),
    ]
    /// Desktop default refresh_interval is 300 seconds.
    nonisolated static let defaultRefreshInterval: Double = 300

    init(session: URLSession = .shared) { self.session = session }

    // MARK: Feeds

    func addFeed(urlString: String, category: String = Category.uncategorized,
                 in context: ModelContext) async throws -> Feed {
        var target = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        // Desktop subscribing resolves social page URLs to their native
        // feeds (a Mastodon profile, a subreddit, a Lemmy community, a
        // Groups.io group, a GitHub repo) before fetching.
        if let converted = SocialResolver.feedURL(forPageURL: target) {
            target = converted
        } else if SocialResolver.isYouTubeChannelPage(target),
                  let feedURL = await SocialResolver.youTubeChannelFeedURL(pageURL: target) {
            target = feedURL
        } else if SocialResolver.isSoundCloudProfile(target),
                  let feedURL = await SocialResolver.soundCloudFeedURL(pageURL: target) {
            target = feedURL
        }
        guard let url = URL(string: target),
              url.scheme == "http" || url.scheme == "https" else {
            throw LibraryError.invalidURL
        }
        let parsed = try await fetchFeed(at: url)
        let feed = Feed(id: url.absoluteString, url: url.absoluteString,
                        title: parsed.title, category: category, language: parsed.language)
        feed.feedDescription = parsed.feedDescription
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
        if feed.isHosted {
            await syncHosted(in: context)
            return
        }
        guard let url = URL(string: feed.url) else { return }
        do {
            let parsed = try await fetchFeed(at: url)
            apply(parsed: parsed, to: feed, in: context)
            try? context.save()
            await autoDownloadPodcasts(feed: feed)
        } catch {
            recordError(error, for: feed, in: context)
            try? context.save()
        }
    }

    /// Hosted feeds (Miniflux, Google Reader API) refresh through their
    /// account. Refresh All used to fetch each one's feed URL directly:
    /// 698 requests for the reference Miniflux account, and the results
    /// were stored again under local ids, duplicating every article.
    @discardableResult
    private func syncHosted(in context: ModelContext, quiet: Bool = false) async -> Int {
        guard let config = HostedConfig.load() else { return 0 }
        do {
            let sync = HostedSync()
            sync.quiet = quiet
            return try await sync.sync(config: config, in: context)
        } catch {
            if !quiet { Announcer.announce("Sync failed. \(error.localizedDescription)") }
            return 0
        }
    }

    /// Updates feed state and merges entries. Callers save.
    /// Returns (added, notifiable): notifiable excludes articles a rule
    /// told to skip the notification for and feeds with notifications off.
    @discardableResult
    private func apply(parsed: ParsedFeed, to feed: Feed, in context: ModelContext, quiet: Bool = false) -> (added: Int, notifiable: Int) {
        if !feed.titleIsCustom, feed.title != parsed.title { feed.title = parsed.title }
        if feed.feedDescription != parsed.feedDescription { feed.feedDescription = parsed.feedDescription }
        if feed.lastError != nil { feed.lastError = nil }
        feed.lastSuccessAt = Date()
        if feed.consecutiveFailures != 0 { feed.consecutiveFailures = 0 }
        let merged = merge(entries: parsed.entries, into: feed, in: context)
        if merged.added > 0, !quiet { Announcer.announce("\(feed.title): \(merged.added) new articles.") }
        return merged
    }

    private func recordError(_ error: Error, for feed: Feed, in context: ModelContext) {
        feed.lastError = error.localizedDescription
        feed.lastErrorAt = Date()
        feed.consecutiveFailures += 1
    }

    /// Refresh-all fetches and parses up to 8 feeds at a time (desktop
    /// max_concurrent_refreshes is 16; 8 keeps radio and CPU bursts low
    /// on a phone), then merges one at a time on the main actor, since
    /// ModelContext is not thread-safe. Previously this was one feed at
    /// a time, so 698 feeds meant 698 sequential round trips.
    /// Saves happen every 25 feeds, not after each one: every save
    /// re-runs each open @Query and re-renders the lists.
    /// `quiet` is for automatic refreshes: no per-feed or progress speech,
    /// only the new-article total, and only when there is something new.
    /// `onProgress` hears (feeds done, feed total) as feeds finish; a
    /// long-running Siri refresh reports it to keep its time extension.
    func refreshAll(feeds: [Feed], in context: ModelContext, quiet: Bool = false,
                    onProgress: ((Int, Int) -> Void)? = nil) async {
        // One at a time: an automatic refresh and Refresh All running
        // together would merge the same entries twice.
        guard !Self.isRefreshingAll else {
            if !quiet { Announcer.announce("Refresh already in progress.") }
            return
        }
        Self.isRefreshingAll = true
        Self.lastRefreshAll = Date()
        defer { Self.isRefreshingAll = false }
        var newTotal = 0
        var notifyTotal = 0
        if feeds.contains(where: \.isHosted) {
            let hostedAdded = await syncHosted(in: context, quiet: quiet)
            newTotal += hostedAdded
            notifyTotal += hostedAdded
        }
        let localFeeds = feeds.filter { !$0.isHosted }
        let feedsByID = Dictionary(localFeeds.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let jobs: [(Feed, URL)] = localFeeds.compactMap { feed in
            URL(string: feed.url).map { (feed, $0) }
        }
        await withTaskGroup(of: (String, Result<ParsedFeed, Error>).self) { group in
            var index = 0
            let window = 8
            func enqueueNext() {
                guard index < jobs.count else { return }
                // Read the id here: SwiftData models must not be touched
                // from the child tasks, which run off the main actor.
                let feedID = jobs[index].0.id
                let url = jobs[index].1
                index += 1
                group.addTask { [session] in
                    do {
                        return (feedID, .success(try await Self.fetchParsed(session: session, url: url)))
                    } catch {
                        return (feedID, .failure(error))
                    }
                }
            }
            for _ in 0..<min(window, jobs.count) { enqueueNext() }
            var merged = 0
            for await (feedID, result) in group {
                if let feed = feedsByID[feedID] {
                    switch result {
                    case .success(let parsed):
                        let merged = apply(parsed: parsed, to: feed, in: context, quiet: quiet)
                        newTotal += merged.added
                        notifyTotal += merged.notifiable
                    case .failure(let error):
                        recordError(error, for: feed, in: context)
                    }
                    merged += 1
                    onProgress?(merged, jobs.count)
                    if merged % 25 == 0 { try? context.save() }
                }
                enqueueNext()
            }
        }
        purgeExpiredArticles(in: context)
        try? context.save()
        for feed in localFeeds { await autoDownloadPodcasts(feed: feed) }
        if !quiet {
            Announcer.announce("Refresh complete. \(newTotal) new articles.")
        } else if newTotal > 0 {
            Announcer.announce("\(newTotal) new articles.")
        }
        if notifyTotal > 0, UserDefaults.standard.bool(forKey: "notificationsEnabled") {
            let content = UNMutableNotificationContent()
            content.title = "BlindRSS"
            content.body = "\(notifyTotal) new articles."
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// Article retention (desktop Settings: Feeds and Articles). Stored
    /// articles older than the cutoff are removed; favorites are never
    /// removed, and hosted articles are the server's to keep. The merge
    /// refuses entries past the same cutoff, so a purge is not undone by
    /// the next refresh.
    static var retentionCutoff: Date? {
        let days = UserDefaults.standard.integer(forKey: "retentionDays")
        guard days > 0 else { return nil }
        return Date(timeIntervalSinceNow: -Double(days) * 86_400)
    }

    private func purgeExpiredArticles(in context: ModelContext) {
        guard let cutoff = Self.retentionCutoff else { return }
        let expired = (try? context.fetch(FetchDescriptor<Article>(
            predicate: #Predicate { $0.date != nil && $0.date! < cutoff && !$0.isFavorite }))) ?? []
        for article in expired where article.feed?.isHosted != true {
            context.delete(article)
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
        let feedID = deleted.feedID
        guard let feed = (try? context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.id == feedID })))?.first else { return }
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

    /// Deletes an article following the configured delete behaviour
    /// (desktop Settings: move to Deleted Articles, delete permanently,
    /// or move to a category). The default keeps the desktop behaviour:
    /// snapshot into DeletedArticle (tombstone), then remove, matching
    /// desktop delete/restore in core/db.py.
    func deleteArticle(_ article: Article, in context: ModelContext) {
        guard let feed = article.feed else { return }
        switch UserDefaults.standard.string(forKey: "deleteBehavior") ?? "deleted" {
        case "permanent":
            let title = article.title
            context.delete(article)
            try? context.save()
            Announcer.announce("Deleted \(title) permanently.")
        case "category":
            let category = UserDefaults.standard.string(forKey: "deleteCategory") ?? ""
            let target = category.isEmpty ? "Deleted" : category
            article.movedCategory = target
            article.hiddenFromFeed = true
            try? context.save()
            Announcer.announce("Moved \(article.title) to \(target).")
        default:
            context.insert(DeletedArticle(feedID: feed.id, article: article))
            context.delete(article)
            try? context.save()
            Announcer.announce("Deleted \(article.title).")
        }
    }

    // MARK: Fetching

    func fetchFeed(at url: URL) async throws -> ParsedFeed {
        try await Self.fetchParsed(session: session, url: url)
    }

    /// Network plus XML parsing off the main actor: parsing a large feed
    /// used to block the UI thread for its whole duration.
    nonisolated static func fetchParsed(session: URLSession, url: URL) async throws -> ParsedFeed {
        var request = URLRequest(url: url)
        request.setValue("BlindRSS-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LibraryError.httpStatus(http.statusCode)
        }
        return try await Task.detached(priority: .userInitiated) {
            try FeedParser.parse(data: data, sourceURL: url)
        }.value
    }

    /// Inserts new entries, updates changed ones, respects delete tombstones.
    /// Returns how many articles were added and how many of those may
    /// raise the new-article notification (feed not muted, no rule said
    /// skip, article not deleted by a rule).
    @discardableResult
    private func merge(entries: [ParsedEntry], into feed: Feed, in context: ModelContext) -> (added: Int, notifiable: Int) {
        let feedID = feed.id
        let tombstones = (try? context.fetch(FetchDescriptor<DeletedArticle>(
            predicate: #Predicate { $0.feedID == feedID }))) ?? []
        let tombstonedIDs = Set(tombstones.map(\.articleID))
        // One dictionary build replaces a linear scan per entry: a feed
        // with 2,000 stored articles and 100 new entries used to do
        // 200,000 string comparisons per refresh.
        var existingByID: [String: Article] = [:]
        existingByID.reserveCapacity(feed.articles.count)
        for article in feed.articles { existingByID[article.id] = article }
        // Filter rules are fetched once per merge, not once per article.
        let filterRules = (try? context.fetch(FetchDescriptor<FilterRule>(sortBy: [SortDescriptor(\.position)]))) ?? []
        let cutoff = Self.retentionCutoff
        var added = 0
        var notifiable = 0
        for entry in entries {
            let articleID = "\(feed.id):\(entry.guid)"
            if tombstonedIDs.contains(articleID) || tombstonedIDs.contains(entry.guid) { continue }
            if let existing = existingByID[articleID] {
                // Write only fields that changed. Unconditional writes
                // dirtied every stored article on every refresh, so each
                // refresh re-saved them all and re-rendered every row.
                func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<Article, T>, _ value: T) {
                    if existing[keyPath: keyPath] != value { existing[keyPath: keyPath] = value }
                }
                update(\.title, entry.title)
                update(\.content, entry.contentHTML.isEmpty ? (entry.summaryHTML ?? "") : entry.contentHTML)
                update(\.summary, entry.summaryHTML)
                update(\.date, entry.date)
                update(\.dateRaw, entry.dateRaw)
                update(\.author, entry.author)
                update(\.mediaURL, entry.mediaURL)
                update(\.mediaType, entry.mediaType)
            } else {
                // Retention: a refresh never inserts articles already
                // past the cutoff (desktop issue #106).
                if let cutoff, let date = entry.date, date < cutoff { continue }
                let article = Article(
                    id: articleID, title: entry.title, url: entry.link,
                    content: entry.contentHTML.isEmpty ? (entry.summaryHTML ?? "") : entry.contentHTML,
                    summary: entry.summaryHTML, date: entry.date, dateRaw: entry.dateRaw,
                    author: entry.author, mediaURL: entry.mediaURL,
                    mediaType: entry.mediaType, feed: feed)
                article.chapterURL = entry.chapterURL
                for parsed in entry.inlineChapters {
                    let chapter = Chapter(id: "\(articleID)-ch-\(parsed.start)", start: parsed.start,
                                          title: parsed.title, href: parsed.href, article: article)
                    article.chapters.append(chapter)
                    context.insert(chapter)
                }
                feed.articles.append(article)
                context.insert(article)
                existingByID[articleID] = article
                added += 1
                if applyFilterRules(rules: filterRules, to: article, in: context), feed.notificationsEnabled {
                    notifiable += 1
                }
                if let chapterURL = entry.chapterURL {
                    Task { await self.loadChapters(articleID: articleID, chapterURL: chapterURL, in: context) }
                }
            }
        }
        return (added, notifiable)
    }

    /// Desktop auto-download: after refresh, download newest episodes up
    /// to the configured limit (max_downloads, default 32).
    private func autoDownloadPodcasts(feed: Feed) async {
        guard UserDefaults.standard.bool(forKey: "autoDownloadPodcasts") else { return }
        let limit = max(1, UserDefaults.standard.integer(forKey: "maxDownloads") == 0 ? 32 : UserDefaults.standard.integer(forKey: "maxDownloads"))
        let pending = feed.articles
            .filter { $0.hasMedia && $0.localFileName == nil }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .prefix(limit)
        for article in pending {
            try? await DownloadService.download(article: article)
        }
        if !pending.isEmpty {
            Announcer.announce("Auto-downloaded \(pending.count) episodes from \(feed.title).")
        }
    }

    /// Downloads a Podcasting 2.0 chapters document into Chapter rows.
    func loadChapters(articleID: String, chapterURL: String, in context: ModelContext) async {
        let parsed = await PodcastService.fetchChapters(urlString: chapterURL)
        // Fetch the one article by id. This used to load the whole Article
        // table once per new episode with a chapters URL.
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == articleID })
        descriptor.fetchLimit = 1
        guard !parsed.isEmpty,
              let article = (try? context.fetch(descriptor))?.first,
              article.chapters.isEmpty else { return }
        for item in parsed {
            let chapter = Chapter(id: "\(articleID)-ch-\(item.start)", start: item.start,
                                  title: item.title, href: item.href, article: article)
            article.chapters.append(chapter)
            context.insert(chapter)
        }
        try? context.save()
    }

    /// Wayback Podcast Archive: merges episodes from the oldest feed
    /// snapshot so back catalogues appear beside current episodes.
    func recoverArchive(feed: Feed, in context: ModelContext) async {
        guard let snapshot = await PodcastService.waybackSnapshotURL(forFeed: feed.url) else {
            Announcer.announce("No archived snapshot found for \(feed.title).")
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: snapshot)
            let parsed = try FeedParser.parse(data: data, sourceURL: URL(string: feed.url) ?? snapshot)
            let added = merge(entries: parsed.entries, into: feed, in: context).added
            try context.save()
            Announcer.announce("Archive recovery for \(feed.title) added \(added) episodes.")
        } catch {
            Announcer.announce("Archive recovery failed for \(feed.title).")
        }
    }

    /// Desktop Filter Rules pipeline on arrival (core/filters.py):
    /// every matching rule contributes its actions in order; a stop rule
    /// ends the pipeline. Returns whether the new-article notification
    /// may include this article (not when a rule deleted it or said to
    /// skip its notification).
    private func applyFilterRules(rules: [FilterRule], to article: Article, in context: ModelContext) -> Bool {
        let effects = FilterRule.pipeline(rules: rules, article: article)
        if effects.markRead { article.isRead = true }
        if effects.favorite { article.isFavorite = true }
        if let move = effects.moveCategory { article.movedCategory = move }
        for label in effects.labels where !article.labels.contains(label) {
            article.labels.append(label)
        }
        if effects.delete {
            deleteArticle(article, in: context)
            return false
        }
        return !effects.skipNotification
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
