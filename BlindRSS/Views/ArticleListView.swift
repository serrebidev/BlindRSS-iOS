// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftData
import SwiftUI
import UIKit

/// Article list (desktop article list). This view carries the port's core
/// VoiceOver pattern, from ios-swiftui-accessibility-techniques:
///
/// - Each row is one combined element: title, feed, date, read and favorite
///   state, and "has audio" are spoken once, in that order.
/// - Every touch `.swipeActions` entry is duplicated as a VoiceOver
///   `.accessibilityAction` with a Label icon on the same row. Neither user
///   group gets an action the other cannot reach.
/// - A hint is present because swipe actions exist; it names the result,
///   never the gesture.
/// - Custom Rotors (Unread, Favorites, With Audio) use `.accessibilityRotor`
///   so rotate-plus-swipe jumps between matching articles.
/// - `.isHeader` traits on section headers enable Rotor heading navigation.
struct ArticleListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AudioPlayer.self) private var player
    @Query(sort: \Article.date, order: .reverse) private var allArticles: [Article]
    @State private var store = LibraryStore()
    @State private var searchText = ""
    @State private var articleToShare: Article?
    /// Desktop article filters and sorting (Ctrl+1..6 views, Sort menu).
    @State private var mediaFilter = "all"
    @State private var sortNewestFirst = true

    let selection: LibrarySelection
    let feed: Feed?
    @Binding var selectedArticle: Article?

    /// One filtering pass. Body calls this once per render and shares the
    /// result with the list, rotors, and toolbar; it used to be a computed
    /// property evaluated five times per render, each a full filter and sort.
    private func filteredArticles() -> [Article] {
        let feedID = feed?.id
        var result = allArticles.filter { article in
            if let feedID, article.feed?.id != feedID { return false }
            if !selection.includes(article) { return false }
            switch mediaFilter {
            case "with": if !article.hasMedia { return false }
            case "without": if article.hasMedia { return false }
            default: break
            }
            // Raw content search only: stripping HTML for every article
            // on every render was the list's biggest CPU cost.
            return searchText.isEmpty
                || article.title.localizedCaseInsensitiveContains(searchText)
                || article.content.localizedCaseInsensitiveContains(searchText)
                || article.author.localizedCaseInsensitiveContains(searchText)
        }
        // The query already sorts newest first.
        if !sortNewestFirst { result.reverse() }
        return result
    }

    var body: some View {
        let articles = filteredArticles()
        Group {
            if articles.isEmpty {
                ContentUnavailableView("No Articles", systemImage: "doc.text",
                                       description: Text("Pull to refresh, or choose another view."))
            } else {
                // Rows are tagged, not buttons, so the list selection
                // pushes the reader on iPhone.
                List(articles, selection: $selectedArticle) { article in
                    ArticleRow(article: article) {
                        selectedArticle = article
                    }
                    .tag(article)
                }
                .onChange(of: selectedArticle) { _, article in
                    // Opening marks read quietly: the reader appearing is the feedback.
                    guard let article, !article.isRead else { return }
                    article.isRead = true
                    article.openedAt = Date()
                    try? context.save()
                }
                // Custom Rotors: two-finger rotate, then swipe to jump
                // between matching articles (technique: Rotor).
                .accessibilityRotor("Unread") {
                    ForEach(articles.filter { !$0.isRead }) { article in
                        AccessibilityRotorEntry(article.title, id: article.id)
                    }
                }
                .accessibilityRotor("Favorites") {
                    ForEach(articles.filter { $0.isFavorite }) { article in
                        AccessibilityRotorEntry(article.title, id: article.id)
                    }
                }
                .accessibilityRotor("With Audio") {
                    ForEach(articles.filter { $0.hasMedia }) { article in
                        AccessibilityRotorEntry(article.title, id: article.id)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search articles")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.markAllRead(in: articles, context: context)
                } label: {
                    Label("Mark All Read", systemImage: "envelope.open")
                }
                .accessibilityHint("Marks every article in this list as read.")
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Picker("Media", selection: $mediaFilter) {
                        Text("Media and Non-media").tag("all")
                        Text("With Media Only").tag("with")
                        Text("Without Media Only").tag("without")
                    }
                    Button(sortNewestFirst ? "Sort Oldest First" : "Sort Newest First") {
                        sortNewestFirst.toggle()
                    }
                } label: {
                    Label("Filter and Sort", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityHint("Filters by media and changes sort order.")
            }
        }
    }
}

/// One article row. Touch swipes and VoiceOver actions are kept in sync here:
/// adding an action means adding it in both places.
private struct ArticleRow: View {
    @Environment(\.modelContext) private var context
    @Environment(AudioPlayer.self) private var player
    @Environment(\.openURL) private var openURL
    @State private var store = LibraryStore()
    @State private var showingShare = false

    let article: Article
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusImage)
                .foregroundStyle(article.isRead ? Color.secondary : Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(article.isRead ? .body : .body.bold())
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    if let feedTitle = article.feed?.title {
                        Text(feedTitle).font(.caption).foregroundStyle(.secondary)
                    }
                    if let date = article.date {
                        Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    if article.isFavorite {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityHidden(true)
                    }
                    if article.hasMedia {
                        Image(systemName: "play.circle").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        // One VoiceOver element per row, spoken once in a fixed order.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(article.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows article actions.")
        .accessibilityAddTraits(.isButton)
        // Touch swipe actions (sighted and low-vision path).
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.deleteArticle(article, in: context)
            } label: { Label("Delete", systemImage: "trash") }
            Button {
                store.toggleFavorite(article, in: context)
            } label: { Label(article.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: article.isFavorite ? "star.slash" : "star") }
                .tint(.yellow)
            Button {
                store.setRead(article, read: !article.isRead, in: context)
            } label: { Label(article.isRead ? "Mark Unread" : "Mark Read",
                            systemImage: article.isRead ? "envelope.badge" : "envelope.open") }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if article.hasMedia {
                Button {
                    player.play(article: article)
                } label: { Label("Play", systemImage: "play.fill") }
                    .tint(.green)
            }
            Button {
                showingShare = true
            } label: { Label("Share", systemImage: "square.and.arrow.up") }
        }
        // VoiceOver custom actions: identical set, Label icons included for
        // Switch Control and Voice Control ("Show actions for ...").
        .accessibilityAction { onOpen() } label: { Label("Read", systemImage: "doc.text") }
        .accessibilityAction {
            store.setRead(article, read: !article.isRead, in: context)
        } label: { Label(article.isRead ? "Mark Unread" : "Mark Read",
                         systemImage: article.isRead ? "envelope.badge" : "envelope.open") }
        .accessibilityAction {
            store.toggleFavorite(article, in: context)
        } label: { Label(article.isFavorite ? "Remove Favorite" : "Favorite", systemImage: "star") }
        .accessibilityAction {
            if article.hasMedia { player.play(article: article) }
        } label: { Label("Play", systemImage: "play.fill") }
        .accessibilityAction {
            if article.hasMedia { player.enqueue(article) }
        } label: { Label("Add to Play Queue", systemImage: "list.bullet") }
        .accessibilityAction {
            if let url = URL(string: article.url) { openURL(url) }
        } label: { Label("Open in Browser", systemImage: "safari") }
        .accessibilityAction {
            UIPasteboard.general.string = article.url
            Announcer.announce("Link copied.")
        } label: { Label("Copy Link", systemImage: "doc.on.doc") }
        .accessibilityAction {
            Task { try? await DownloadService.download(article: article) }
        } label: { Label("Download Media", systemImage: "arrow.down.circle") }
        .accessibilityAction {
            store.deleteArticle(article, in: context)
        } label: { Label("Delete", systemImage: "trash") }
        .shareSheet(isPresented: $showingShare, urlString: article.url)
    }

    private var statusImage: String {
        if article.hasMedia { return "play.circle.fill" }
        return article.isRead ? "envelope.open" : "envelope.fill"
    }

    /// Spoken after the label: feed, date, then state, so a blind user hears
    /// the same scan pattern on every row.
    private var accessibilityValue: String {
        var parts: [String] = []
        if let feedTitle = article.feed?.title { parts.append(feedTitle) }
        if let date = article.date {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        parts.append(article.isRead ? "read" : "unread")
        if article.isFavorite { parts.append("favorite") }
        if article.hasMedia { parts.append("has audio") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Share sheet bridge

private struct ShareSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let urlString: String

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            if let url = URL(string: urlString) {
                ShareSheet(items: [url])
            }
        }
    }
}

private extension View {
    func shareSheet(isPresented: Binding<Bool>, urlString: String) -> some View {
        modifier(ShareSheetModifier(isPresented: isPresented, urlString: urlString))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
