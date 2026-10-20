// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftData
import SwiftUI

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

    let selection: LibrarySelection
    let feed: Feed?
    @Binding var selectedArticle: Article?

    private var articles: [Article] {
        var result = feed != nil ? allArticles.filter { $0.feed?.id == feed?.id } : allArticles
        result = result.filter { selection.includes($0) }
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || HTMLText.plainText(from: $0.content).localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        Group {
            if articles.isEmpty {
                ContentUnavailableView("No Articles", systemImage: "doc.text",
                                       description: Text("Pull to refresh, or choose another view."))
            } else {
                List(articles, selection: $selectedArticle) { article in
                    ArticleRow(article: article, isSelected: selectedArticle?.id == article.id) {
                        selectedArticle = article
                        store.setRead(article, read: true, in: context)
                    }
                    .tag(article)
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
    let isSelected: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
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
            }
        }
        .frame(minHeight: 44)
        // One VoiceOver element per row, spoken once in a fixed order.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(article.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows article actions.")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
