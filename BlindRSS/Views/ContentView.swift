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
