// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import AVKit
import SwiftData
import SwiftUI

/// Deleted Articles view (desktop Deleted Articles): restore or purge.
/// Every row mirrors touch swipes with VoiceOver actions.
struct DeletedArticlesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DeletedArticle.deletedAt, order: .reverse) private var deleted: [DeletedArticle]
    @State private var store = LibraryStore()

    var body: some View {
        Group {
            if deleted.isEmpty {
                ContentUnavailableView("No Deleted Articles", systemImage: "trash",
                                       description: Text("Deleted articles appear here and can be restored."))
            } else {
                List(deleted) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title ?? "Untitled")
                        Text(item.deletedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(item.title ?? "Untitled")
                    .accessibilityValue("Deleted \(item.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                    .accessibilityHint("Shows restore options.")
                    .touchSwipeActions(edge: .trailing) {
                        Button(role: .destructive) { store.purgeDeleted(item, in: context) } label: { Label("Delete Permanently", systemImage: "trash.fill") }
                        Button { store.restoreDeleted(item, in: context) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                    }
                    .accessibilityAction { store.restoreDeleted(item, in: context) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                    .accessibilityAction { store.purgeDeleted(item, in: context) } label: { Label("Delete Permanently", systemImage: "trash.fill") }
                }
            }
        }
        .navigationTitle("Deleted Articles")
    }
}

/// Smart Folders (desktop Smart Folders): rule-based virtual folders.
struct SmartFoldersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SmartFolder.position) private var folders: [SmartFolder]
    @State private var name = ""
    @State private var readState = "unread"
    @State private var titleContains = ""
    @State private var hasMediaOnly = false

    var body: some View {
        List {
            Section {
                ForEach(folders) { folder in
                    NavigationLink(folder.name) {
                        SmartFolderArticlesView(folder: folder)
                    }
                    .accessibilityLabel(folder.name)
                    .touchSwipeActions(edge: .trailing) {
                        Button(role: .destructive) { context.delete(folder); try? context.save() } label: { Label("Delete", systemImage: "trash") }
                    }
                    .accessibilityAction { context.delete(folder); try? context.save() } label: { Label("Delete Smart Folder", systemImage: "trash") }
                }
            } header: { Text("Folders").accessibilityAddTraits(.isHeader) }

            Section {
                TextField("Folder name", text: $name).accessibilityLabel("Folder name")
                Picker("Articles", selection: $readState) {
                    Text("All").tag("all"); Text("Unread").tag("unread"); Text("Favorites").tag("favorites")
                }
                .accessibilityElement(children: .contain).accessibilityLabel("Articles")
                TextField("Title contains", text: $titleContains).accessibilityLabel("Title contains")
                Toggle("With audio or video only", isOn: $hasMediaOnly)
                Button("Create Smart Folder") {
                    guard !name.isEmpty else { return }
                    context.insert(SmartFolder(name: name, readState: readState, titleContains: titleContains, hasMediaOnly: hasMediaOnly, position: folders.count))
                    try? context.save()
                    Announcer.announce("Created smart folder \(name).")
                    name = ""; titleContains = ""
                }
                .accessibilityHint("Creates a folder that collects matching articles automatically.")
            } header: { Text("New Folder").accessibilityAddTraits(.isHeader) }
        }
        .navigationTitle("Smart Folders")
    }
}

private struct SmartFolderArticlesView: View {
    @Query(sort: \Article.date, order: .reverse) private var all: [Article]
    let folder: SmartFolder
    var body: some View {
        List(all.filter { folder.matches($0) }) { article in
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                Text(article.feed?.title ?? "").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(article.title)
            .accessibilityValue(article.isRead ? "read" : "unread")
        }
        .navigationTitle(folder.name)
    }
}

/// Filter Rules (desktop Filter Rules): act on articles as they arrive.
/// A rule can combine the desktop's actions — mark read, favorite,
/// delete, skip notification, move to a category, label — and can stop
/// the pipeline so later rules do not run for that article.
struct FilterRulesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FilterRule.position) private var rules: [FilterRule]
    @State private var name = ""
    @State private var field = "title"
    @State private var contains = ""
    @State private var doMarkRead = true
    @State private var doFavorite = false
    @State private var doDelete = false
    @State private var skipNotification = false
    @State private var moveCategory = ""
    @State private var labelCategory = ""
    @State private var stop = false

    static func actionsSummary(_ rule: FilterRule) -> String {
        let actions = rule.effectiveActions
        var parts: [String] = []
        if actions.markRead { parts.append("mark read") }
        if actions.favorite { parts.append("favorite") }
        if actions.delete { parts.append("delete") }
        if rule.skipNotification { parts.append("skip notification") }
        if !rule.moveCategory.isEmpty { parts.append("move to \(rule.moveCategory)") }
        if !rule.labelCategory.isEmpty { parts.append("label \(rule.labelCategory)") }
        if rule.stop { parts.append("stop") }
        return parts.isEmpty ? "no actions" : parts.joined(separator: ", ")
    }

    var body: some View {
        List {
            Section {
                ForEach(rules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.name)
                            Text("\(rule.field) contains \(rule.contains): \(Self.actionsSummary(rule))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Enabled", isOn: Binding(get: { rule.enabled }, set: { rule.enabled = $0; try? context.save() }))
                            .labelsHidden().accessibilityLabel("Enabled")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(rule.name)
                    .accessibilityHint("Shows rule actions.")
                    .touchSwipeActions(edge: .trailing) {
                        Button(role: .destructive) { context.delete(rule); try? context.save() } label: { Label("Delete", systemImage: "trash") }
                    }
                    .accessibilityAction { context.delete(rule); try? context.save() } label: { Label("Delete Rule", systemImage: "trash") }
                }
            } header: { Text("Rules").accessibilityAddTraits(.isHeader) }

            Section {
                TextField("Rule name", text: $name).accessibilityLabel("Rule name")
                Picker("Field", selection: $field) {
                    Text("Title").tag("title"); Text("Content").tag("content"); Text("Feed").tag("feed"); Text("Author").tag("author")
                }.accessibilityElement(children: .contain).accessibilityLabel("Field")
                TextField("Contains", text: $contains).accessibilityLabel("Contains")
                Toggle("Mark as Read", isOn: $doMarkRead).accessibilityLabel("Mark as Read")
                Toggle("Mark as Favorite", isOn: $doFavorite).accessibilityLabel("Mark as Favorite")
                Toggle("Delete Article", isOn: $doDelete).accessibilityLabel("Delete Article")
                Toggle("Do Not Notify", isOn: $skipNotification).accessibilityLabel("Do Not Notify")
                TextField("Move to Category (optional)", text: $moveCategory).accessibilityLabel("Move to Category")
                TextField("Label (optional)", text: $labelCategory).accessibilityLabel("Label")
                Toggle("Stop Processing Further Rules", isOn: $stop).accessibilityLabel("Stop Processing Further Rules")
                Button("Create Filter Rule") {
                    guard !name.isEmpty, !contains.isEmpty else { return }
                    let legacy = doDelete ? "delete" : (doFavorite ? "favorite" : "markRead")
                    let rule = FilterRule(name: name, field: field, contains: contains, action: legacy, position: rules.count)
                    rule.doMarkRead = doMarkRead
                    rule.doFavorite = doFavorite
                    rule.doDelete = doDelete
                    rule.skipNotification = skipNotification
                    rule.moveCategory = moveCategory.trimmingCharacters(in: .whitespaces)
                    rule.labelCategory = labelCategory.trimmingCharacters(in: .whitespaces)
                    rule.stop = stop
                    context.insert(rule)
                    try? context.save()
                    Announcer.announce("Created filter rule \(name).")
                    name = ""; contains = ""; moveCategory = ""; labelCategory = ""
                }
                .accessibilityHint("Applies this rule to new articles as feeds refresh.")
            } header: { Text("New Rule").accessibilityAddTraits(.isHeader) }
        }
        .navigationTitle("Filter Rules")
    }
}

/// Unified discovery (desktop Finding Podcasts, Detecting Feeds on a
/// Page, and the podcast directories in one place). One search field:
/// type a name to search Apple Podcasts and gPodder together, or paste
/// a site or feed URL to detect its feeds via the page itself and
/// feedsearch.dev. Every result subscribes with one tap.
struct DiscoverView: View {
    @Environment(\.modelContext) private var context
    @State private var store = LibraryStore()
    @State private var query = ""
    @State private var podcasts: [PodcastService.SearchResult] = []
    @State private var feeds: [PodcastService.FeedResult] = []
    @State private var isSearching = false
    @State private var hasSearched = false

    var body: some View {
        List {
            if !podcasts.isEmpty {
                Section {
                    ForEach(podcasts) { result in
                        subscribeButton(title: result.title, detail: result.artistName ?? "Podcast",
                                        feedURL: result.feedUrl)
                    }
                } header: { Text("Podcasts").accessibilityAddTraits(.isHeader) }
            }
            // Directory results group under their source, the way the
            // desktop's directory search lists each directory's hits.
            ForEach(groupedFeeds, id: \.source) { group in
                Section {
                    ForEach(group.results) { result in
                        subscribeButton(title: result.title, detail: result.website ?? "RSS feed",
                                        feedURL: result.url)
                    }
                } header: { Text(group.source).accessibilityAddTraits(.isHeader) }
            }
            if hasSearched, podcasts.isEmpty, feeds.isEmpty, !isSearching {
                Text("No feeds or podcasts found.")
                    .accessibilityLabel("No feeds or podcasts found.")
            }
        }
        .searchable(text: $query, prompt: "Search feeds and podcasts, or paste a URL")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .overlay { if isSearching { ProgressView("Searching").accessibilityLabel("Searching") } }
        .navigationTitle("Search Feeds and Podcasts")
    }

    private var groupedFeeds: [(source: String, results: [PodcastService.FeedResult])] {
        var order: [String] = []
        var bySource: [String: [PodcastService.FeedResult]] = [:]
        for result in feeds {
            let key = result.source.isEmpty ? "gPodder" : result.source
            if bySource[key] == nil { order.append(key) }
            bySource[key, default: []].append(result)
        }
        return order.map { (source: $0, results: bySource[$0] ?? []) }
    }

    private func subscribeButton(title: String, detail: String, feedURL: String?) -> some View {
        Button {
            Task {
                if let feedURL { _ = try? await store.addFeed(urlString: feedURL, in: context) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
        .accessibilityHint("Subscribes to this feed.")
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        hasSearched = true
        podcasts = []
        feeds = []
        if PodcastService.looksLikeURL(trimmed), let page = URL(string: trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)") {
            // URL: page discovery plus feedsearch.dev, and try it AS a feed.
            async let discovered = FullTextService.discoverFeeds(pageURL: page)
            async let searched = PodcastService.searchFeedsearch(siteURL: page.absoluteString)
            var found = await searched.map { result in
                var copy = result
                if copy.source.isEmpty { copy.source = "Site" }
                return copy
            }
            for item in await discovered where !found.contains(where: { $0.url == item.url.absoluteString }) {
                found.append(.init(title: item.title, url: item.url.absoluteString, website: page.absoluteString, source: "Site"))
            }
            feeds = found
        } else {
            // Name: Apple Podcasts, gPodder, and the desktop's keyless
            // directories together.
            async let podcastResults = PodcastService.searchPodcasts(term: trimmed)
            async let feedResults = PodcastService.searchFeeds(term: trimmed)
            async let directoryResults = DirectorySearch.searchAll(term: trimmed)
            podcasts = (try? await podcastResults) ?? []
            var combined = await feedResults
            for result in await directoryResults where !combined.contains(where: { $0.url == result.url }) {
                combined.append(result)
            }
            feeds = combined
        }
        isSearching = false
        Announcer.announce("\(podcasts.count + feeds.count) results found.")
    }
}

/// Podcast Archive (desktop Podcast Archive): back catalogue from the
/// Wayback Machine, with batch download.
struct PodcastArchiveView: View {
    @Environment(\.modelContext) private var context
    @State private var store = LibraryStore()
    @State private var filter = ""
    @Bindable var feed: Feed

    private var episodes: [Article] {
        feed.articles.filter { $0.hasMedia }
            .filter { filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var body: some View {
        List {
            Section {
                Button("Rescan Archive") {
                    Task { await store.recoverArchive(feed: feed, in: context) }
                }
                .accessibilityHint("Recovers older episodes from the Wayback Machine.")
                Button("Download All") {
                    Task {
                        for episode in episodes where episode.localFileName == nil {
                            try? await DownloadService.download(article: episode)
                        }
                        Announcer.announce("Batch download finished.")
                    }
                }
                .accessibilityHint("Downloads every episode in this list.")
            }
            Section {
                ForEach(episodes) { episode in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.title)
                            if let date = episode.date {
                                Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if episode.localFileName != nil {
                            Image(systemName: "arrow.down.circle.fill").accessibilityHidden(true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(episode.title)
                    .accessibilityValue(episode.localFileName != nil ? "downloaded" : "not downloaded")
                    .accessibilityHint("Shows episode actions.")
                    .accessibilityAction {
                        Task { try? await DownloadService.download(article: episode) }
                    } label: { Label("Download", systemImage: "arrow.down.circle") }
                }
            } header: { Text("Episodes").accessibilityAddTraits(.isHeader) }
        }
        .searchable(text: $filter, prompt: "Filter episodes")
        .navigationTitle("Podcast Archive")
    }
}

/// Hosted provider account (desktop Online Accounts and Providers).
struct ProviderSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var kind: HostedProviderKind = .miniflux
    @State private var baseURL = ""
    @State private var username = ""
    @State private var token = ""
    @State private var isSyncing = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $kind) {
                    ForEach(HostedProviderKind.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityElement(children: .contain).accessibilityLabel("Provider")
                .onChange(of: kind) { _, new in if baseURL.isEmpty { baseURL = new.defaultBaseURL } }
                TextField("Server URL", text: $baseURL).keyboardType(.URL).autocapitalization(.none)
                    .accessibilityLabel("Server URL").accessibilityHint("Required for Miniflux. Prefilled for other providers.")
                TextField("Username", text: $username).autocapitalization(.none).accessibilityLabel("Username")
                SecureField("API token", text: $token).accessibilityLabel("API token")
                    .accessibilityHint("Miniflux API token, or Google Reader auth token for other providers.")
            } header: { Text("Account").accessibilityAddTraits(.isHeader) }

            Section {
                Button(isSyncing ? "Syncing, please wait" : "Save and Sync Now") {
                    HostedConfig(kind: kind, baseURL: HostedSync.normalizedBaseURL(baseURL),
                                 username: username, token: token.trimmingCharacters(in: .whitespacesAndNewlines)).save()
                    Task {
                        isSyncing = true
                        statusMessage = "Connecting."
                        do {
                            if let config = HostedConfig.load() {
                                let added = try await HostedSync().sync(config: config, in: context)
                                statusMessage = "Sync complete. \(added) new articles."
                            }
                        } catch {
                            statusMessage = "Sync failed: \(error.localizedDescription)"
                            Announcer.announce("Sync failed. \(error.localizedDescription)")
                        }
                        isSyncing = false
                    }
                }
                .disabled(token.isEmpty || isSyncing)
                .accessibilityHint("Saves the account and pulls feeds and articles into this device.")
                if isSyncing {
                    ProgressView("Syncing feeds and articles")
                        .accessibilityLabel("Syncing feeds and articles")
                }
                if let statusMessage {
                    Text(statusMessage)
                        .accessibilityLabel(statusMessage)
                }
                Button("Remove Account", role: .destructive) {
                    HostedConfig.clear(); token = ""
                    Announcer.announce("Hosted account removed from this device.")
                }
            }
        }
        .navigationTitle("Online Account")
        .onAppear {
            if let config = HostedConfig.load() {
                kind = config.kind; baseURL = config.baseURL; username = config.username; token = config.token
            }
        }
    }
}

/// Feed properties (desktop Feed Properties): rename, recategorize,
/// per-feed notifications, the feed's own description, and reset title.
/// The description and notifications are stored on the feed; the rest
/// were already here.
struct FeedEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var feed: Feed
    @State private var title: String = ""
    @State private var category: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feed title", text: $title).accessibilityLabel("Feed title")
                    Button("Reset Title") {
                        // Desktop Feed Properties: restore the title the
                        // feed publishes and let refresh maintain it.
                        feed.titleIsCustom = false
                        Task {
                            if let url = URL(string: feed.url),
                               let parsed = try? await LibraryStore().fetchFeed(at: url) {
                                title = parsed.title
                                feed.title = parsed.title
                                try? context.save()
                                Announcer.announce("Title reset to \(parsed.title).")
                            }
                        }
                    }
                    .accessibilityHint("Restores the title published by the feed.")
                    TextField("Category", text: $category).accessibilityLabel("Category")
                    Toggle("Notifications for This Feed", isOn: $feed.notificationsEnabled)
                        .accessibilityLabel("Notifications for This Feed")
                        .accessibilityHint("When off, new articles from this feed never raise a notification.")
                }
                if let description = feed.feedDescription, !description.isEmpty {
                    Section {
                        Text(description)
                            .accessibilityLabel("Feed description: \(description)")
                    } header: { Text("Description").accessibilityAddTraits(.isHeader) }
                }
                Section {
                    Text(feed.url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        .accessibilityLabel("Feed URL \(feed.url)")
                }
            }
            .navigationTitle("Feed Properties")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if feed.title != title { feed.title = title; feed.titleIsCustom = true }
                        feed.category = category
                        try? context.save()
                        Announcer.announce("Saved \(feed.title).")
                        dismiss()
                    }
                }
            }
            .onAppear { title = feed.title; category = feed.category }
        }
    }
}

/// Downloads list (desktop Downloading Media). Downloads play in the mini
/// player, which has the equalizer and silence skipping for every episode.
struct DownloadsView: View {
    @Environment(AudioPlayer.self) private var player
    // Only rows with a download: this used to load every article and
    // check the disk for each one, twice per render.
    @Query(filter: #Predicate<Article> { $0.localFileName != nil },
           sort: \Article.date, order: .reverse) private var all: [Article]

    var body: some View {
        let downloaded = all.filter { DownloadService.localURL(for: $0) != nil }
        Group {
            if downloaded.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle",
                                       description: Text("Download an episode from an article to listen offline."))
            } else {
                List(downloaded) { article in
                    Button(article.title) { player.play(article: article) }
                        .frame(minHeight: 44)
                        .accessibilityHint("Plays this download in the player.")
                }
            }
        }
        .navigationTitle("Downloads")
    }
}

/// AirPlay route picker (desktop casting covers AirPlay natively).
struct AirPlayRouteView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = .systemBlue
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
