// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftData
import SwiftUI
import UIKit

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

    @Binding var selection: SidebarItem?

    /// Unread and favorite counts for the whole library in one pass.
    /// Body computes this once per render and hands it to every row; it
    /// used to be a computed property read three times per row, so 698
    /// feeds meant about 2,000 full-library passes per render.
    private struct Counts {
        var unreadByFeedID: [String: Int] = [:]
        var unread = 0
        var favorites = 0
        var errors = 0
    }

    private func libraryCounts() -> Counts {
        var counts = Counts()
        for feed in feeds {
            var unread = 0
            for article in feed.articles {
                if !article.isRead { unread += 1 }
                if article.isFavorite { counts.favorites += 1 }
            }
            counts.unreadByFeedID[feed.id] = unread
            counts.unread += unread
            if feed.lastError != nil { counts.errors += 1 }
        }
        return counts
    }

    var body: some View {
        let counts = libraryCounts()
        let feedsByCategory = Dictionary(grouping: feeds, by: \.category)
        VStack(spacing: 0) {
            if isPhone {
                // iPhone: large Add Feed and More buttons first, then the Feeds
                // heading, so both come before it for VoiceOver and are easy
                // to hit. The navigation bar is hidden here. Outside the List,
                // which left a blank band above its first section.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Button {
                            showingAddFeed = true
                        } label: {
                            Label("Add Feed", systemImage: "plus")
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .accessibilityFocused($addButtonFocused)
                        .accessibilityHint("Opens the add feed form.")
                        .keyboardShortcut("n", modifiers: .command)
                        Menu {
                            refreshAllButton
                            settingsButton
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .menuStyle(.button)
                        .accessibilityHint("Refresh All and Settings.")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .font(.title3)
                    Text("Feeds")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .background(Color(.systemGroupedBackground))
            }
            // Rows are tagged, not buttons: List selection is what makes the
            // split view open the article list on iPhone.
            List(selection: $selection) {
                Section {
                    ForEach(LibrarySelection.allCases) { view in
                        Label(view.title, systemImage: view.systemImage)
                            .tag(SidebarItem.library(view))
                            .accessibilityLabel(view.title)
                            .accessibilityValue(badgeValue(for: view, counts: counts))
                            .accessibilityAddTraits(.isButton)
                    }
                } header: {
                    Text("Library")
                        .accessibilityAddTraits(.isHeader)
                }

                ForEach(feedsByCategory.keys.sorted(), id: \.self) { category in
                    Section {
                        ForEach(feedsByCategory[category] ?? []) { feed in
                            feedRow(feed, unread: counts.unreadByFeedID[feed.id] ?? 0)
                        }
                    } header: {
                        Text(category)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            // Library section sits right under the Feeds heading.
            .contentMargins(.top, isPhone ? 0 : nil, for: .scrollContent)
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
            ToolbarItem(placement: .secondaryAction) { refreshAllButton }
            ToolbarItem(placement: .secondaryAction) { settingsButton }
        }
        .toolbar(isPhone ? .hidden : .automatic, for: .navigationBar)
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

    /// iPad keeps the toolbar: hiding the sidebar's bar there would also
    /// hide the sidebar button.
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private var refreshAllButton: some View {
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

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Label("Settings", systemImage: "gear")
        }
    }

    private func badgeValue(for view: LibrarySelection, counts: Counts) -> String {
        switch view {
        case .unread:
            return counts.unread > 0 ? "\(counts.unread) unread" : ""
        case .favorites:
            return "\(counts.favorites) favorites"
        case .errors:
            return counts.errors > 0 ? "\(counts.errors) feeds with errors" : ""
        default: return ""
        }
    }

    @ViewBuilder
    private func feedRow(_ feed: Feed, unread: Int) -> some View {
        HStack {
            Text(feed.title)
            Spacer()
            if unread > 0 {
                Text("\(unread)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if feed.lastError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .tag(SidebarItem.feed(feed))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(feed.title)
        .accessibilityValue(feedValue(feed, unread: unread))
        .accessibilityHint("Shows feed actions.")
        .accessibilityAddTraits(.isButton)
        // Touch swipe actions.
        .touchSwipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteFeed(feed)
            } label: { Label("Delete", systemImage: "trash") }
            Button {
                markAllRead(feed)
            } label: { Label("Mark All Read", systemImage: "envelope.open") }
        }
        .touchSwipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await store.refresh(feed: feed, in: context) }
            } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .tint(.blue)
        }
        // VoiceOver custom actions: the identical set, with icons for the
        // Switch Control and Voice Control actions menus.
        .accessibilityAction { selection = .feed(feed) } label: { Label("Open", systemImage: "doc.text") }
        .accessibilityAction { Task { await store.refresh(feed: feed, in: context) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
        .accessibilityAction { markAllRead(feed) } label: { Label("Mark All Read", systemImage: "envelope.open") }
        .accessibilityAction { editingFeed = feed } label: { Label("Edit Feed", systemImage: "pencil") }
        .accessibilityAction { archiveFeed = feed } label: { Label("Podcast Archive", systemImage: "archivebox") }
        .accessibilityAction { deleteFeed(feed) } label: { Label("Delete", systemImage: "trash") }
    }

    /// Clears the selection first so the article list never shows a
    /// deleted feed.
    private func deleteFeed(_ feed: Feed) {
        if selection == .feed(feed) { selection = nil }
        store.removeFeed(feed, in: context)
    }

    private func feedValue(_ feed: Feed, unread: Int) -> String {
        var parts: [String] = []
        parts.append(unread > 0 ? "\(unread) unread" : "no unread")
        if let error = feed.lastError { parts.append("Error: \(error)") }
        return parts.joined(separator: ", ")
    }

    private func markAllRead(_ feed: Feed) {
        store.markAllRead(in: feed.articles, context: context)
    }
}
