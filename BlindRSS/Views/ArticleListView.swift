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
/// - Every touch swipe action is also a VoiceOver action with a Label icon
///   on the same row. Neither user group gets an action the other cannot
///   reach. Swipes are touch-only (`touchSwipeActions`): VoiceOver would
///   otherwise list them too, first, out of the chosen order.
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
    @AppStorage(ArticleAction.storageKey) private var storedActionOrder = ""

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
        // Parsed once per render and shared by every row.
        let actionOrder = ArticleAction.order(from: storedActionOrder)
        Group {
            if articles.isEmpty {
                ContentUnavailableView("No Articles", systemImage: "doc.text",
                                       description: Text("Pull to refresh, or choose another view."))
            } else {
                // Rows are tagged, not buttons, so the list selection
                // pushes the reader on iPhone.
                List(articles, selection: $selectedArticle) { article in
                    ArticleRow(article: article, actionOrder: actionOrder) {
                        selectedArticle = article
                    }
                    .tag(article)
                }
                .onChange(of: selectedArticle) { _, article in
                    guard let article else { return }
                    // Opening a podcast plays it, as activating one does on
                    // the desktop; the reader still opens with its notes.
                    if article.hasMedia, player.currentArticle?.id != article.id {
                        player.play(article: article)
                    }
                    // Opening marks read quietly: the reader appearing is the feedback.
                    guard !article.isRead else { return }
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
    let actionOrder: [ArticleAction]
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
        .accessibilityHint(article.hasMedia ? "Plays the episode and opens its notes. Shows article actions."
                                            : "Shows article actions.")
        .accessibilityAddTraits(.isButton)
        // Touch swipe actions (sighted and low-vision path).
        .touchSwipeActions(edge: .trailing, allowsFullSwipe: false) {
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
        .touchSwipeActions(edge: .leading, allowsFullSwipe: false) {
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
        // VoiceOver custom actions: the touch set plus more, in the order
        // chosen in Settings, Article Actions. Label icons are included for
        // Switch Control and Voice Control ("Show actions for ...").
        .accessibilityActions {
            ForEach(actionOrder) { action in
                if let label = label(for: action) {
                    Button { perform(action) } label: { Label(label, systemImage: action.systemImage) }
                }
            }
        }
        .shareSheet(isPresented: $showingShare, urlString: article.url)
    }

    /// The action's name for this article, or nil when it does not apply
    /// (media actions on an article without audio, links without a URL).
    private func label(for action: ArticleAction) -> String? {
        switch action {
        case .openInBrowser, .copyLink, .share:
            return URL(string: article.url) == nil ? nil : action.title
        case .download, .play, .addToQueue:
            return article.hasMedia ? action.title : nil
        case .toggleRead:
            return article.isRead ? "Mark Unread" : "Mark Read"
        case .favorite:
            return article.isFavorite ? "Remove Favorite" : "Favorite"
        case .read, .delete:
            return action.title
        }
    }

    private func perform(_ action: ArticleAction) {
        switch action {
        case .openInBrowser: if let url = URL(string: article.url) { openURL(url) }
        case .download: Task { try? await DownloadService.download(article: article) }
        case .read: onOpen()
        case .toggleRead: store.setRead(article, read: !article.isRead, in: context)
        case .favorite: store.toggleFavorite(article, in: context)
        case .play: player.play(article: article)
        case .addToQueue: player.enqueue(article)
        case .copyLink:
            UIPasteboard.general.string = article.url
            Announcer.announce("Link copied.")
        case .share: showingShare = true
        case .delete: store.deleteArticle(article, in: context)
        }
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

// MARK: - Article actions order

/// Article row actions, in the order VoiceOver offers them. Open in Browser,
/// Download, and Copy Link come first by default; Settings, Article Actions
/// reorders.
enum ArticleAction: String, CaseIterable, Identifiable {
    case openInBrowser, download, copyLink, read, toggleRead, favorite, play, addToQueue, share, delete

    static let storageKey = "articleActionOrder"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openInBrowser: return "Open in Browser"
        case .download: return "Download Media"
        case .read: return "Read"
        case .toggleRead: return "Mark Read or Unread"
        case .favorite: return "Favorite"
        case .play: return "Play"
        case .addToQueue: return "Add to Play Queue"
        case .copyLink: return "Copy Link"
        case .share: return "Share"
        case .delete: return "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .openInBrowser: return "safari"
        case .download: return "arrow.down.circle"
        case .read: return "doc.text"
        case .toggleRead: return "envelope.open"
        case .favorite: return "star"
        case .play: return "play.fill"
        case .addToQueue: return "list.bullet"
        case .copyLink: return "doc.on.doc"
        case .share: return "square.and.arrow.up"
        case .delete: return "trash"
        }
    }

    /// The saved order. Unknown names are dropped and actions added in a
    /// later version go at the end, so an old setting never hides one.
    static func order(from stored: String) -> [ArticleAction] {
        var order: [ArticleAction] = []
        for name in stored.split(separator: ",") {
            if let action = ArticleAction(rawValue: String(name)), !order.contains(action) { order.append(action) }
        }
        return order + allCases.filter { !order.contains($0) }
    }

    static func stored(_ order: [ArticleAction]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }
}

/// Settings, Article Actions: the order of the article actions VoiceOver
/// offers. Reorder by dragging in Edit mode, or with each row's Move actions.
struct ArticleActionOrderView: View {
    @AppStorage(ArticleAction.storageKey) private var stored = ""

    var body: some View {
        let order = ArticleAction.order(from: stored)
        List {
            Section {
                ForEach(Array(order.enumerated()), id: \.element) { index, action in
                    Label(action.title, systemImage: action.systemImage)
                        .accessibilityLabel("\(action.title), \(index + 1) of \(order.count)")
                        .accessibilityHint("Shows move actions.")
                        .accessibilityAction { move(action, to: index - 1, in: order) } label: {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                        .accessibilityAction { move(action, to: index + 1, in: order) } label: {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                        .accessibilityAction { move(action, to: 0, in: order) } label: {
                            Label("Move to Top", systemImage: "arrow.up.to.line")
                        }
                }
                .onMove { source, destination in
                    var reordered = order
                    reordered.move(fromOffsets: source, toOffset: destination)
                    stored = ArticleAction.stored(reordered)
                }
            } footer: {
                Text("VoiceOver offers article actions in this order. Actions that do not apply to an article, such as Play on an article without audio, are left out.")
            }
            Section {
                Button("Reset to Default Order") {
                    stored = ""
                    Announcer.announce("Default order restored.")
                }
            }
        }
        .navigationTitle("Article Actions")
        .toolbar { EditButton() }
    }

    private func move(_ action: ArticleAction, to target: Int, in order: [ArticleAction]) {
        guard order.indices.contains(target), let index = order.firstIndex(of: action), index != target else { return }
        var reordered = order
        reordered.remove(at: index)
        reordered.insert(action, at: target)
        stored = ArticleAction.stored(reordered)
        Announcer.announce("\(action.title) moved to position \(target + 1).")
    }
}

// MARK: - Touch swipe actions

/// Swipe actions for touch only. SwiftUI also lists a row's swipe actions
/// in the VoiceOver Actions rotor, ahead of the row's own accessibility
/// actions, so every action was offered twice and the order chosen in
/// Settings, Article Actions was lost behind Delete, Favorite, and Mark
/// Read. While VoiceOver runs, rows offer only their accessibility actions.
private struct TouchSwipeActions<Actions: View>: ViewModifier {
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    let edge: HorizontalEdge
    let allowsFullSwipe: Bool
    let actions: Actions

    func body(content: Content) -> some View {
        if voiceOverEnabled {
            content
        } else {
            content.swipeActions(edge: edge, allowsFullSwipe: allowsFullSwipe) { actions }
        }
    }
}

extension View {
    func touchSwipeActions<Actions: View>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true,
                                          @ViewBuilder content: () -> Actions) -> some View {
        modifier(TouchSwipeActions(edge: edge, allowsFullSwipe: allowsFullSwipe, actions: content()))
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
