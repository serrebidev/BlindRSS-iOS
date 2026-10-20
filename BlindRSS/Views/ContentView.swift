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
    @State private var selectedFeed: Feed?
    @State private var selectedView: LibrarySelection = .all
    @State private var selectedArticle: Article?

    var body: some View {
        NavigationSplitView {
            FeedListView(selection: $selectedView, selectedFeed: $selectedFeed)
                .navigationTitle("Feeds")
        } content: {
            ArticleListView(selection: selectedView, feed: selectedFeed, selectedArticle: $selectedArticle)
                .navigationTitle(selectedView.title)
        } detail: {
            if let article = selectedArticle {
                ArticleReaderView(article: article)
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
        .onAppear { wirePlaybackState() }
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
