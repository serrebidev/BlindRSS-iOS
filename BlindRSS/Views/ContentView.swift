// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftData
import SwiftUI

/// Root layout, mirroring the desktop main window: feed tree on the left,
/// article list and reading pane on the right (gui/mainframe.py). On iPhone
/// this collapses to a navigation stack; on iPad it stays split.
/// Every tab and pushed view carries a navigation title (WCAG 2.4.2).
struct ContentView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.modelContext) private var context
    /// Sidebar and article list selections. On iPhone the split view
    /// collapses to a stack and only pushes the next column when a
    /// List(selection:) changes; buttons that set state push nothing,
    /// which is why feeds and views could not be opened before 0.1.3.
    @State private var sidebarSelection: SidebarItem?
    @State private var selectedArticle: Article?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("refreshInterval") private var refreshInterval = LibraryStore.defaultRefreshInterval
    @AppStorage("refreshOnStartup") private var refreshOnStartup = true
    @State private var autoRefresher = LibraryStore()
    @State private var didStartupRefresh = false
    /// An article Siri, Spotlight, or visual intelligence asked to open.
    @State private var requestedArticle: Article?

    private var selectedView: LibrarySelection {
        if case .library(let view)? = sidebarSelection { return view }
        return .all
    }

    private var selectedFeed: Feed? {
        if case .feed(let feed)? = sidebarSelection { return feed }
        return nil
    }

    private var selectedSearch: SavedSearch? {
        if case .savedSearch(let search)? = sidebarSelection { return search }
        return nil
    }

    private var selectedCategoryName: String? {
        if case .category(let name)? = sidebarSelection { return name }
        return nil
    }

    /// Desktop remembers the last tree selection (last_view /
    /// last_feed_id in state.json) and restores it at launch.
    @AppStorage("lastSidebarView") private var lastSidebarView = ""
    @AppStorage("lastSidebarFeedID") private var lastSidebarFeedID = ""
    @State private var didRestoreSelection = false

    private var contentTitle: String {
        selectedFeed?.title ?? selectedSearch?.name ?? selectedCategoryName ?? selectedView.title
    }

    var body: some View {
        NavigationSplitView {
            FeedListView(selection: $sidebarSelection)
                .navigationTitle("Feeds")
        } content: {
            ArticleListView(selection: selectedView, feed: selectedFeed,
                            savedSearch: selectedSearch, categoryName: selectedCategoryName,
                            selectedArticle: $selectedArticle)
                .navigationTitle(contentTitle)
        } detail: {
            if let article = selectedArticle {
                // New identity per article: on iPad the reader stayed on
                // screen and kept the previous article's full text.
                ArticleReaderView(article: article)
                    .id(article.id)
                    .navigationTitle(article.title)
            } else {
                ContentUnavailableView("No Article Selected",
                                       systemImage: "doc.text",
                                       description: Text("Choose an article to read."))
                    .navigationTitle("Reader")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if player.currentArticle != nil {
                MiniPlayerView()
            }
        }
        // Magic Tap (two-finger double tap) toggles playback anywhere,
        // the VoiceOver equivalent of the desktop Ctrl+P play/pause command.
        .accessibilityAction(.magicTap) {
            player.togglePlayPause()
        }
        .onAppear { wirePlaybackState(); restoreSelection() }
        // A new feed or view starts with no article open; a stale one
        // would jump straight to the old reader on iPhone.
        .onChange(of: sidebarSelection) {
            selectedArticle = nil
            rememberSelection()
        }
        // Desktop Ctrl+1..5 switch library views; mirrored as Cmd+1..5.
        .background {
            ZStack {
                ForEach(Array(LibrarySelection.allCases.enumerated()), id: \.element) { index, view in
                    Button(view.title) { sidebarSelection = .library(view) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        // Automatic refresh (desktop refresh_interval) while the app is
        // open; BlindRSSApp asks iOS for background refreshes otherwise.
        .task(id: "\(refreshInterval) \(scenePhase == .active)") { await autoRefreshLoop() }
        // Siri, Spotlight, and visual intelligence open articles here.
        // A sheet, not the split view's selection: it works from any
        // sidebar state on iPhone and iPad alike.
        .task(id: AppNavigator.shared.articleIDToOpen) { openRequestedArticle() }
        .task(id: AppNavigator.shared.searchText) {
            if AppNavigator.shared.searchText != nil { sidebarSelection = .library(.all) }
        }
        .sheet(item: $requestedArticle) { article in
            NavigationStack {
                ArticleReaderView(article: article)
                    .navigationTitle(article.title)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { requestedArticle = nil }
                        }
                    }
            }
            .environment(player)
        }
    }

    private func openRequestedArticle() {
        guard let id = AppNavigator.shared.articleIDToOpen else { return }
        AppNavigator.shared.articleIDToOpen = nil
        let found = (try? context.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.id == id }))) ?? []
        guard let article = found.first else {
            Announcer.announce("That article is no longer in BlindRSS.")
            return
        }
        if !article.isRead {
            article.isRead = true
            article.openedAt = Date()
            try? context.save()
        }
        requestedArticle = article
    }

    private func restoreSelection() {
        guard !didRestoreSelection else { return }
        didRestoreSelection = true
        guard sidebarSelection == nil else { return }
        if !lastSidebarFeedID.isEmpty {
            let feedID = lastSidebarFeedID
            let feeds = (try? context.fetch(FetchDescriptor<Feed>(
                predicate: #Predicate { $0.id == feedID }))) ?? []
            if let feed = feeds.first {
                sidebarSelection = .feed(feed)
                return
            }
        }
        if lastSidebarView.hasPrefix("search:") {
            let searchID = String(lastSidebarView.dropFirst("search:".count))
            let searches = (try? context.fetch(FetchDescriptor<SavedSearch>(
                predicate: #Predicate { $0.id == searchID }))) ?? []
            if let search = searches.first {
                sidebarSelection = .savedSearch(search)
                return
            }
        }
        if lastSidebarView.hasPrefix("category:") {
            sidebarSelection = .category(String(lastSidebarView.dropFirst("category:".count)))
            return
        }
        if let view = LibrarySelection(rawValue: lastSidebarView) {
            sidebarSelection = .library(view)
        }
    }

    private func rememberSelection() {
        switch sidebarSelection {
        case .feed(let feed):
            lastSidebarFeedID = feed.id
            lastSidebarView = ""
        case .library(let view):
            lastSidebarView = view.rawValue
            lastSidebarFeedID = ""
        case .savedSearch(let search):
            lastSidebarView = "search:\(search.id)"
            lastSidebarFeedID = ""
        case .category(let name):
            lastSidebarView = "category:\(name)"
            lastSidebarFeedID = ""
        case nil:
            break
        }
    }

    /// Refresh on startup, then every interval, counted from the last
    /// Refresh All of any kind. Restarts when the interval or the app's
    /// active state changes.
    private func autoRefreshLoop() async {
        guard scenePhase == .active else { return }
        if !didStartupRefresh {
            didStartupRefresh = true
            if refreshOnStartup {
                await refreshAllFeeds()
            } else if LibraryStore.lastRefreshAll == nil {
                LibraryStore.lastRefreshAll = Date()
            }
        }
        guard refreshInterval > 0 else { return }
        while !Task.isCancelled {
            let wait = (LibraryStore.lastRefreshAll ?? .distantPast)
                .addingTimeInterval(refreshInterval).timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            } else {
                await refreshAllFeeds()
            }
        }
    }

    private func refreshAllFeeds() async {
        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        guard !feeds.isEmpty else {
            LibraryStore.lastRefreshAll = Date()
            return
        }
        // Unstructured on purpose: leaving the app cancels the loop, and a
        // cancelled refresh would record every unfinished feed as failed.
        await Task { await autoRefresher.refreshAll(feeds: feeds, in: context, quiet: true) }.value
        await SpotlightIndex.update()
    }

    /// Connects the player to SwiftData: resume positions, progress saves,
    /// finished episodes marked read, and the persisted play queue.
    private func wirePlaybackState() {
        // Fetch the playback-state table once. The previous version
        // fetched every row on each play and again on every 15-second
        // progress save.
        let states = (try? context.fetch(FetchDescriptor<PlaybackState>())) ?? []
        var stateByID: [String: PlaybackState] = [:]
        for state in states { stateByID[state.id] = state }
        player.resumeProvider = { id in
            guard let state = stateByID[id], !state.completed else { return nil }
            return (state.position, state.duration)
        }
        player.positionSaver = { id, position, duration, completed, title in
            if let existing = stateByID[id] {
                existing.position = position
                existing.duration = duration
                existing.completed = completed
                existing.updatedAt = Date()
                existing.title = title
            } else {
                let created = PlaybackState(id: id, position: position, duration: duration,
                                            completed: completed, title: title)
                context.insert(created)
                stateByID[id] = created
            }
            try? context.save()
        }
        player.onArticleFinished = { article in
            article.isRead = true
            try? context.save()
        }
        // Fetch only the queued articles. This used to be an @Query of the
        // whole library on the root view, so every article change anywhere
        // re-rendered the entire window.
        let queuedIDs = AudioPlayer.persistedQueueIDs
        if player.queue.isEmpty, !queuedIDs.isEmpty {
            let queued = (try? context.fetch(FetchDescriptor<Article>(
                predicate: #Predicate { queuedIDs.contains($0.id) }))) ?? []
            player.restoreQueue(articles: queued)
        }
    }
}

/// One sidebar row: a fixed library view, a feed, a persistent search,
/// or a browsable article category.
enum SidebarItem: Hashable {
    case library(LibrarySelection)
    case feed(Feed)
    case savedSearch(SavedSearch)
    case category(String)
}

/// The desktop's fixed views: All / Unread / Read / Favorites, plus Errors.
enum LibrarySelection: String, CaseIterable, Identifiable {
    case all, unread, read, favorites, errors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Articles"
        case .unread: return "Unread"
        case .read: return "Read"
        case .favorites: return "Favorites"
        case .errors: return "Feeds with Errors"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .unread: return "envelope.badge"
        case .read: return "envelope.open"
        case .favorites: return "star"
        case .errors: return "exclamationmark.triangle"
        }
    }

    func includes(_ article: Article) -> Bool {
        switch self {
        case .all: return true
        case .unread: return !article.isRead
        case .read: return article.isRead
        case .favorites: return article.isFavorite
        case .errors: return false
        }
    }
}
