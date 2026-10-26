// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftData
import UniformTypeIdentifiers
#if canImport(VisualIntelligence)
import VisualIntelligence
#endif

// Apple Intelligence and Siri (0.1.17). App Intents put the library in
// Siri, Shortcuts, Spotlight, and the Action button: ask for a briefing
// of unread articles, a summary of or an answer about one article, the
// unread count, a refresh, or a new subscription, by voice and without
// opening the app. Articles are app entities, so Siri can see the one
// on screen (onscreen awareness, iOS 18.2), Spotlight finds recent
// articles (IndexedEntity), and visual intelligence offers articles
// whose titles match what the camera or a screenshot shows (iOS 26).

// MARK: - Article entity

struct ArticleEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Article")
    static let defaultQuery = ArticleQuery()

    let id: String
    @Property(title: "Title") var title: String
    @Property(title: "Feed") var feedTitle: String
    @Property(title: "Date") var date: Date?
    @Property(title: "Link") var link: String
    /// The start of the article's text, for Spotlight and for the
    /// library search Apple Intelligence runs over Spotlight (iOS 27).
    let snippet: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(feedTitle)")
    }

    @MainActor init(_ article: Article) {
        // Plain stored properties first: the @Property setters need
        // every stored property initialized.
        id = article.id
        snippet = String(HTMLText.plainText(from: String((article.summary ?? article.content).prefix(1500))).prefix(400))
        title = article.title
        feedTitle = article.feed?.title ?? ""
        date = article.date
        link = article.url
    }
}

/// Spotlight lists recent articles by title and feed; tapping one runs
/// OpenArticleIntent. The snippet and date make them findable by
/// content and let "Ask Your Library" answer from them.
@available(iOS 18, *)
extension ArticleEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = snippet
        attributes.contentCreationDate = date
        attributes.authorNames = feedTitle.isEmpty ? nil : [feedTitle]
        return attributes
    }
}

/// Siri and Apple Intelligence read an article (the one on screen, or one
/// a shortcut passes along) as plain text: title, link, then the best
/// text the app has.
extension ArticleEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { entity in
            let text = await MainActor.run { () -> String? in
                guard let article = ArticleQuery.fetch(ids: [entity.id]).first else { return nil }
                return FullTextCache.shared.spokenText(for: article.id) ?? AppleIntelligence.feedText(of: article)
            }
            return Data("\(entity.title)\n\(entity.link)\n\n\(text ?? "")".utf8)
        }
    }
}

struct ArticleQuery: EntityStringQuery {
    @MainActor static func fetch(ids: [String]) -> [Article] {
        let descriptor = FetchDescriptor<Article>(predicate: #Predicate { ids.contains($0.id) })
        return (try? LibraryContainer.shared.mainContext.fetch(descriptor)) ?? []
    }

    /// Newest articles first, optionally only unread ones.
    @MainActor static func newest(limit: Int, unreadOnly: Bool = false) -> [Article] {
        var descriptor = unreadOnly
            ? FetchDescriptor<Article>(predicate: #Predicate { !$0.isRead }, sortBy: [SortDescriptor(\.date, order: .reverse)])
            : FetchDescriptor<Article>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? LibraryContainer.shared.mainContext.fetch(descriptor)) ?? []
    }

    func entities(for identifiers: [String]) async throws -> [ArticleEntity] {
        await MainActor.run { Self.fetch(ids: identifiers).map(ArticleEntity.init) }
    }

    func entities(matching string: String) async throws -> [ArticleEntity] {
        await MainActor.run {
            var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.title.localizedStandardContains(string) },
                                                      sortBy: [SortDescriptor(\.date, order: .reverse)])
            descriptor.fetchLimit = 50
            return ((try? LibraryContainer.shared.mainContext.fetch(descriptor)) ?? []).map(ArticleEntity.init)
        }
    }

    func suggestedEntities() async throws -> [ArticleEntity] {
        await MainActor.run { Self.newest(limit: 20, unreadOnly: true).map(ArticleEntity.init) }
    }
}

// MARK: - Spotlight

enum SpotlightIndex {
    /// ponytail: re-indexes the newest 300 articles after each refresh;
    /// deleted ones drop out on the next pass. Index per change if the
    /// whole pass ever shows up in a profile.
    @MainActor static func update() async {
        guard #available(iOS 18, *) else { return }
        let entities = ArticleQuery.newest(limit: 300).map(ArticleEntity.init)
        let index = CSSearchableIndex.default()
        try? await index.deleteAppEntities(ofType: ArticleEntity.self)
        try? await index.indexAppEntities(entities)
    }
}

// MARK: - Visual intelligence

#if canImport(VisualIntelligence)
/// Visual intelligence (camera or screenshot) search: articles whose
/// titles share words with what the system recognized.
@available(iOS 26, *)
struct ArticleVisualSearch: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [ArticleEntity] {
        let labels = input.labels
        guard !labels.isEmpty else { return [] }
        return await MainActor.run {
            ArticleQuery.newest(limit: 1000)
                .map { (article: $0, score: AppleIntelligence.relevance(of: $0.title, to: labels)) }
                .filter { $0.score > 0 }
                .sorted { $0.score > $1.score }
                .prefix(20)
                .map { ArticleEntity($0.article) }
        }
    }
}
#endif

// MARK: - Shared helpers

extension AppleIntelligence {
    /// The article's own text from the feed, HTML removed.
    @MainActor static func feedText(of article: Article) -> String {
        let content = HTMLText.plainText(from: article.content)
        return content.isEmpty ? HTMLText.plainText(from: article.summary) : content
    }

    /// The best text for the model: the recovered full article when it
    /// can be had (feeds often send only a teaser), else the feed text.
    @MainActor static func readableText(of article: Article) async -> String {
        if let cached = FullTextCache.shared.spokenText(for: article.id) { return cached }
        let feedText = feedText(of: article)
        let id = article.id
        let url = article.url
        if let fetched = try? await FullTextService.fetchFullText(articleID: id, url: url, feedText: feedText,
                                                                  transcribeVideo: true),
           !fetched.blocks.isEmpty {
            FullTextCache.shared.store(fetched.blocks, for: id)
            adoptVideo(fetched.videoURL, for: article)
            return fetched.blocks.map(\.text).joined(separator: "\n")
        }
        return feedText
    }

    /// A video page's video becomes the article's media, so Play,
    /// Download, and the play queue work on it like a podcast episode.
    @MainActor static func adoptVideo(_ videoURL: URL?, for article: Article) {
        guard let videoURL, !article.hasMedia else { return }
        article.mediaURL = videoURL.absoluteString
        article.mediaType = videoURL.pathExtension.lowercased() == "m3u8" ? "application/vnd.apple.mpegurl" : "video/mp4"
        try? article.modelContext?.save()
    }

    /// A briefing of the given articles (newest unread, usually).
    @MainActor static func briefing(of articles: [Article]) async throws -> String {
        let items = articles.map { article in
            (title: article.title, feed: article.feed?.title ?? "",
             snippet: HTMLText.plainText(from: String((article.summary ?? article.content).prefix(1500))))
        }
        return try await run(.briefing, text: briefingText(for: items))
    }

    /// Spoken fallback when the model cannot run: the headlines themselves.
    @MainActor static func headlines(of articles: [Article], limit: Int = 10) -> String {
        articles.prefix(limit).map { article in
            article.feed.map { "\($0.title): \(article.title)" } ?? article.title
        }
        .joined(separator: "\n")
    }
}

/// An intent failure Siri speaks as is.
struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

// MARK: - Intents

/// Opens an article in the app (Spotlight, visual intelligence, Siri).
struct OpenArticleIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Article"
    static let description = IntentDescription("Opens an article in BlindRSS.")

    @Parameter(title: "Article", requestValueDialog: "Which article?")
    var target: ArticleEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.articleIDToOpen = target.id
        return .result()
    }
}

enum SummaryStyle: String, AppEnum {
    case summary, keyPoints

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Summary Style")
    static let caseDisplayRepresentations: [SummaryStyle: DisplayRepresentation] = [
        .summary: "Summary",
        .keyPoints: "Key Points",
    ]
}

struct SummarizeArticleIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize Article"
    static let description = IntentDescription("Summarizes an article with Apple Intelligence, on this device.")

    @Parameter(title: "Article", requestValueDialog: "Which article?")
    var article: ArticleEntity

    @Parameter(title: "Style", default: .summary)
    var style: SummaryStyle

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize \(\.$article) as \(\.$style)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let found = ArticleQuery.fetch(ids: [article.id]).first else {
            throw IntentFailure(message: "That article is no longer in BlindRSS.")
        }
        let text = await AppleIntelligence.readableText(of: found)
        do {
            let result = try await AppleIntelligence.run(style == .keyPoints ? .keyPoints : .summary,
                                                         title: found.title, text: text)
            return .result(value: result, dialog: "\(result)")
        } catch {
            throw IntentFailure(message: error.localizedDescription)
        }
    }
}

struct AskAboutArticleIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask About Article"
    static let description = IntentDescription("Answers a question about an article with Apple Intelligence, using only the article.")

    @Parameter(title: "Article", requestValueDialog: "Which article?")
    var article: ArticleEntity

    @Parameter(title: "Question", requestValueDialog: "What do you want to know?")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$article) \(\.$question)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let found = ArticleQuery.fetch(ids: [article.id]).first else {
            throw IntentFailure(message: "That article is no longer in BlindRSS.")
        }
        let text = await AppleIntelligence.readableText(of: found)
        do {
            let answer = try await AppleIntelligence.run(.question(question), title: found.title, text: text)
            return .result(value: answer, dialog: "\(answer)")
        } catch {
            throw IntentFailure(message: error.localizedDescription)
        }
    }
}

/// "Brief me": an Apple Intelligence briefing of the newest unread
/// articles, or their headlines when the model cannot run.
struct BriefingIntent: AppIntent {
    static let title: LocalizedStringResource = "Brief Me on Unread Articles"
    static let description = IntentDescription("Gives a short spoken briefing of your newest unread articles.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let unread = ArticleQuery.newest(limit: 30, unreadOnly: true)
        guard !unread.isEmpty else {
            return .result(value: "", dialog: "You have no unread articles.")
        }
        let text: String
        if AppleIntelligence.status.isAvailable, let briefing = try? await AppleIntelligence.briefing(of: unread) {
            text = briefing
        } else {
            text = "Newest unread articles:\n" + AppleIntelligence.headlines(of: unread)
        }
        return .result(value: text, dialog: "\(text)")
    }
}

struct UnreadCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Unread Article Count"
    static let description = IntentDescription("Says how many unread articles you have.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let count = (try? LibraryContainer.shared.mainContext.fetchCount(
            FetchDescriptor<Article>(predicate: #Predicate { !$0.isRead }))) ?? 0
        let spoken = count == 1 ? "You have 1 unread article." : "You have \(count) unread articles."
        return .result(value: count, dialog: "\(spoken)")
    }
}

struct RefreshFeedsIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Feeds"
    static let description = IntentDescription("Fetches new articles for every feed.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = LibraryContainer.shared.mainContext
        let feedCount = (try? context.fetchCount(FetchDescriptor<Feed>())) ?? 0
        guard feedCount > 0 else { return .result(dialog: "You have no feeds yet.") }
        if #available(iOS 27, *) {
            // Hundreds of feeds outlast the 30-second intent limit: a
            // long-running intent keeps going while it reports progress.
            let progress = self.progress
            progress.totalUnitCount = Int64(feedCount)
            try await performBackgroundTask {
                await Self.refresh { done, _ in progress.completedUnitCount = Int64(done) }
            }
        } else {
            await Self.refresh()
        }
        let unread = (try? context.fetchCount(FetchDescriptor<Article>(predicate: #Predicate { !$0.isRead }))) ?? 0
        return .result(dialog: "Feeds refreshed. \(unread) unread articles.")
    }

    @MainActor
    private static func refresh(onProgress: ((Int, Int) -> Void)? = nil) async {
        let context = LibraryContainer.shared.mainContext
        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        await LibraryStore().refreshAll(feeds: feeds, in: context, quiet: true, onProgress: onProgress)
        await SpotlightIndex.update()
    }
}

@available(iOS 27, *)
extension RefreshFeedsIntent: LongRunningIntent {}

/// "Search BlindRSS for ...": Siri and Apple Intelligence route searches
/// here (the system search schema), and the app opens on All Articles
/// with the search filled in.
@available(iOS 18, *)
@AppIntent(schema: .system.search)
struct SearchArticlesIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]
    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.searchText = criteria.term
        return .result()
    }
}

/// A question about everything in the library (iOS 27).
struct AskLibraryIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Your Library"
    static let description = IntentDescription("Answers a question from all your articles with Apple Intelligence, naming the articles it used.")

    @Parameter(title: "Question", requestValueDialog: "What do you want to know?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        do {
            let answer = try await AppleIntelligence.askLibrary(question)
            return .result(value: answer, dialog: "\(answer)")
        } catch {
            throw IntentFailure(message: error.localizedDescription)
        }
    }
}

/// Spoken descriptions of an article's images (iOS 27).
struct DescribeArticleImagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Describe Article Images"
    static let description = IntentDescription("Describes the pictures in an article with Apple Intelligence.")

    @Parameter(title: "Article", requestValueDialog: "Which article?")
    var article: ArticleEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let found = ArticleQuery.fetch(ids: [article.id]).first else {
            throw IntentFailure(message: "That article is no longer in BlindRSS.")
        }
        do {
            let descriptions = try await AppleIntelligence.describeImages(html: found.content, pageURL: found.url)
            return .result(value: descriptions, dialog: "\(descriptions)")
        } catch {
            throw IntentFailure(message: error.localizedDescription)
        }
    }
}

struct AddFeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Feed"
    static let description = IntentDescription("Subscribes to a feed, podcast, YouTube channel, or social profile by its address.")

    @Parameter(title: "Address", requestValueDialog: "What is the feed's address?")
    var address: URL

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let feed = try await LibraryStore().addFeed(urlString: address.absoluteString,
                                                        in: LibraryContainer.shared.mainContext)
            return .result(dialog: "Subscribed to \(feed.title).")
        } catch {
            throw IntentFailure(message: "Could not subscribe: \(error.localizedDescription)")
        }
    }
}

// MARK: - App Shortcuts (Siri phrases, Spotlight, Action button)

struct BlindRSSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: BriefingIntent(), phrases: [
            "Brief me with \(.applicationName)",
            "What's new in \(.applicationName)",
            "Read my \(.applicationName) briefing",
        ], shortTitle: "Brief Me", systemImageName: "newspaper")
        AppShortcut(intent: SummarizeArticleIntent(), phrases: [
            "Summarize an article in \(.applicationName)",
            "Summarize with \(.applicationName)",
        ], shortTitle: "Summarize Article", systemImageName: "text.append")
        AppShortcut(intent: AskAboutArticleIntent(), phrases: [
            "Ask \(.applicationName) about an article",
        ], shortTitle: "Ask About Article", systemImageName: "questionmark.bubble")
        AppShortcut(intent: AskLibraryIntent(), phrases: [
            "Ask \(.applicationName)",
            "Ask my \(.applicationName) library",
        ], shortTitle: "Ask Your Library", systemImageName: "books.vertical")
        AppShortcut(intent: DescribeArticleImagesIntent(), phrases: [
            "Describe the images in \(.applicationName)",
        ], shortTitle: "Describe Images", systemImageName: "photo")
        AppShortcut(intent: UnreadCountIntent(), phrases: [
            "How many unread articles in \(.applicationName)",
            "\(.applicationName) unread count",
        ], shortTitle: "Unread Count", systemImageName: "envelope.badge")
        AppShortcut(intent: RefreshFeedsIntent(), phrases: [
            "Refresh \(.applicationName)",
            "Refresh feeds in \(.applicationName)",
        ], shortTitle: "Refresh Feeds", systemImageName: "arrow.clockwise")
        AppShortcut(intent: AddFeedIntent(), phrases: [
            "Add a feed to \(.applicationName)",
            "Subscribe in \(.applicationName)",
        ], shortTitle: "Add Feed", systemImageName: "plus")
        AppShortcut(intent: OpenArticleIntent(), phrases: [
            "Open an article in \(.applicationName)",
        ], shortTitle: "Open Article", systemImageName: "doc.text")
    }
}
