// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftData
import SwiftUI

/// Feed and folder list (desktop feed tree). Swipe actions for touch are
/// mirrored as VoiceOver custom actions on the same rows, and hints are
/// present because swipe actions exist (techniques: Accessibility Hint).
struct FeedListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @State private var store = LibraryStore()
    @State private var showingAddFeed = false
    @State private var showingSettings = false
    @State private var editingFeed: Feed?
    @State private var archiveFeed: Feed?
    @State private var isRefreshing = false
    @AccessibilityFocusState private var addButtonFocused: Bool

    @Binding var selection: LibrarySelection
    @Binding var selectedFeed: Feed?

    private var categories: [String] {
        Array(Set(feeds.map(\.category))).sorted()
    }

    var body: some View {
        List {
            Section {
                ForEach(LibrarySelection.allCases) { view in
                    Button {
                        selection = view
                        selectedFeed = nil
                    } label: {
                        Label(view.title, systemImage: view.systemImage)
                    }
                    .accessibilityLabel(view.title)
                    .accessibilityValue(badgeValue(for: view))
                    .accessibilityAddTraits(selection == view && selectedFeed == nil ? [.isSelected] : [])
                }
            } header: {
                Text("Library")
                    .accessibilityAddTraits(.isHeader)
            }

            ForEach(categories, id: \.self) { category in
                Section {
                    ForEach(feeds.filter { $0.category == category }) { feed in
                        feedRow(feed)
                    }
                } header: {
                    Text(category)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .listStyle(.sidebar)
        .refreshable {
            await store.refreshAll(feeds: feeds, in: context)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddFeed = true
                } label: {
                    Label("Add Feed", systemImage: "plus")
                }
                .accessibilityFocused($addButtonFocused)
                .accessibilityHint("Opens the add feed form.")
                .keyboardShortcut("n", modifiers: .command)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task {
                        isRefreshing = true
                        await store.refreshAll(feeds: feeds, in: context)
                        isRefreshing = false
                    }
                } label: {
                    Label("Refresh All", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
                .accessibilityHint("Fetches new articles from every feed.")
                .keyboardShortcut("r", modifiers: .command)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $showingAddFeed, onDismiss: { addButtonFocused = true }) {
            AddFeedView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(item: $editingFeed) { feed in
            FeedEditView(feed: feed)
        }
        .sheet(item: $archiveFeed) { feed in
            NavigationStack { PodcastArchiveView(feed: feed) }
        }
    }

    private func badgeValue(for view: LibrarySelection) -> String {
        let all = feeds.flatMap(\.articles)
        switch view {
        case .unread:
            let count = all.filter { !$0.isRead }.count
            return count > 0 ? "\(count) unread" : ""
        case .favorites:
            return "\(all.filter { $0.isFavorite }.count) favorites"
        case .errors:
            let count = feeds.filter { $0.lastError != nil }.count
            return count > 0 ? "\(count) feeds with errors" : ""
        default: return ""
        }
    }

    @ViewBuilder
    private func feedRow(_ feed: Feed) -> some View {
        Button {
            selectedFeed = feed
            selection = .all
        } label: {
            HStack {
                Text(feed.title)
                Spacer()
                if feed.unreadCount > 0 {
                    Text("\(feed.unreadCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if feed.lastError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(feed.title)
        .accessibilityValue(feedValue(feed))
        .accessibilityHint("Shows feed actions.")
        .accessibilityAddTraits(selectedFeed?.id == feed.id ? [.isSelected] : [])
        // Touch swipe actions.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.removeFeed(feed, in: context)
                if selectedFeed?.id == feed.id { selectedFeed = nil }
            } label: { Label("Delete", systemImage: "trash") }
            Button {
                markAllRead(feed)
            } label: { Label("Mark All Read", systemImage: "envelope.open") }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await store.refresh(feed: feed, in: context) }
            } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .tint(.blue)
        }
        // VoiceOver custom actions: the identical set, with icons for the
        // Switch Control and Voice Control actions menus.
        .accessibilityAction { selectedFeed = feed; selection = .all } label: { Label("Open", systemImage: "doc.text") }
        .accessibilityAction { Task { await store.refresh(feed: feed, in: context) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
        .accessibilityAction { markAllRead(feed) } label: { Label("Mark All Read", systemImage: "envelope.open") }
        .accessibilityAction { editingFeed = feed } label: { Label("Edit Feed", systemImage: "pencil") }
        .accessibilityAction { archiveFeed = feed } label: { Label("Podcast Archive", systemImage: "archivebox") }
        .accessibilityAction {
            store.removeFeed(feed, in: context)
            if selectedFeed?.id == feed.id { selectedFeed = nil }
        } label: { Label("Delete", systemImage: "trash") }
    }

    private func feedValue(_ feed: Feed) -> String {
        var parts: [String] = []
        parts.append(feed.unreadCount > 0 ? "\(feed.unreadCount) unread" : "no unread")
        if let error = feed.lastError { parts.append("Error: \(error)") }
        return parts.joined(separator: ", ")
    }

    private func markAllRead(_ feed: Feed) {
        store.markAllRead(in: feed.articles, context: context)
    }
}
