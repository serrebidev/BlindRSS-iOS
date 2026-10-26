// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// Add-feed form (desktop Add Feed, Ctrl+N). Visible labels on every field;
/// errors are announced, not only shown (technique: Error Validation).
struct AddFeedView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var store = LibraryStore()
    @State private var urlText = ""
    @State private var category = Category.uncategorized
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Feed URL")
                        .accessibilityAddTraits(.isHeader)
                    TextField("Feed URL", text: $urlText)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .accessibilityLabel("Feed URL")
                        .accessibilityHint("Enters the address of an RSS, Atom, or JSON feed.")
                } header: {
                    Text("Subscription")
                }

                Section {
                    TextField("Category", text: $category)
                        .accessibilityLabel("Category")
                        .accessibilityHint("Groups this feed under a category name.")
                } header: {
                    Text("Organization")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Error: \(errorMessage)")
                }
            }
            .navigationTitle("Add Feed")
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink { DiscoverView() } label: {
                        Label("Search Feeds and Podcasts", systemImage: "magnifyingglass")
                    }
                    .accessibilityHint("Searches Apple Podcasts and gPodder by name, or finds feeds for a pasted URL.")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Subscribe") {
                        Task { await subscribe() }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                    .accessibilityHint("Fetches the feed and adds it to your library.")
                }
            }
        }
    }

    private func subscribe() async {
        isAdding = true
        errorMessage = nil
        do {
            _ = try await store.addFeed(urlString: urlText, category: category, in: context)
            dismiss()
        } catch {
            // Feed discovery: the URL may be a web page advertising a feed.
            if let page = URL(string: urlText) {
                let discovered = await FullTextService.discoverFeeds(pageURL: page)
                if let first = discovered.first {
                    do {
                        _ = try await store.addFeed(urlString: first.url.absoluteString, category: category, in: context)
                        dismiss()
                        return
                    } catch { /* fall through to the error below */ }
                }
            }
            errorMessage = error.localizedDescription
            Announcer.announce("Could not subscribe. \(error.localizedDescription)")
            isAdding = false
            return
        }
        isAdding = false
    }

}

/// Settings (desktop Settings subset for Phase 1). Every Toggle and Picker
/// keeps its visible label; nothing is labels-hidden without a replacement.
struct SettingsView: View {
    @AppStorage("refreshOnStartup") private var refreshOnStartup = true
    @AppStorage("refreshInterval") private var refreshInterval = LibraryStore.defaultRefreshInterval
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("autoDownloadPodcasts") private var autoDownloadPodcasts = false
    @AppStorage("maxDownloads") private var maxDownloads = 32
    @AppStorage("playbackSpeed") private var playbackSpeed = 1.0
    @AppStorage("seekInterval") private var seekInterval = 30.0
    @AppStorage("retentionDays") private var retentionDays = 0
    @AppStorage("deleteBehavior") private var deleteBehavior = "deleted"
    @AppStorage("deleteCategory") private var deleteCategory = ""
    @AppStorage("confirmDeleteArticles") private var confirmDeleteArticles = true
    @AppStorage("searchScope") private var searchScope = "titlesText"
    @AppStorage("skipSponsorSegments") private var skipSponsorSegments = true
    @AppStorage("reader.bullets") private var readerBullets = false
    @AppStorage("reader.quotes") private var readerQuotes = false
    @AppStorage("reader.links") private var readerLinks = false
    @AppStorage("reader.altText") private var readerAltText = false
    @AppStorage("appleIntelligence.enabled") private var appleIntelligenceEnabled = true

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var feeds: [Feed]
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingTakeoutImporter = false
    @State private var youtubeAccount = YouTubeAccount.shared
    @State private var showingYouTubeSignIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Refresh on startup", isOn: $refreshOnStartup)
                        .accessibilityHint("Fetches new articles when the app opens.")
                    Picker("Refresh automatically", selection: $refreshInterval) {
                        ForEach(LibraryStore.refreshIntervals, id: \.seconds) { choice in
                            Text(choice.label).tag(choice.seconds)
                        }
                    }
                    .accessibilityHint("Fetches new articles on this schedule. When the app is closed, iOS chooses the exact time.")
                    .onChange(of: refreshInterval) { BackgroundRefresh.schedule() }
                    Toggle("Resume playback", isOn: .constant(true))
                        .accessibilityHint("Continues episodes where you left off.")
                    Toggle("Auto-download podcasts", isOn: $autoDownloadPodcasts)
                        .accessibilityHint("Downloads new episodes after each refresh.")
                    Stepper("Max auto-downloads: \(maxDownloads)", value: $maxDownloads, in: 1...100)
                        .accessibilityLabel("Maximum auto-downloads")
                        .accessibilityValue("\(maxDownloads)")
                } header: {
                    Text("General")
                        .accessibilityAddTraits(.isHeader)
                }

                Section {
                    Picker("Playback speed", selection: $playbackSpeed) {
                        Text("0.75×").tag(0.75)
                        Text("1×").tag(1.0)
                        Text("1.25×").tag(1.25)
                        Text("1.5×").tag(1.5)
                        Text("2×").tag(2.0)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Playback speed")
                    Picker("Seek interval", selection: $seekInterval) {
                        Text("10 seconds").tag(10.0)
                        Text("30 seconds").tag(30.0)
                        Text("60 seconds").tag(60.0)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Seek interval")
                    Toggle("Skip sponsor segments", isOn: $skipSponsorSegments)
                        .accessibilityHint("Skips SponsorBlock segments during YouTube stream playback.")
                } header: {
                    Text("Player")
                        .accessibilityAddTraits(.isHeader)
                }

                Section {
                    NavigationLink { ProviderSettingsView() } label: { Label("Online Account", systemImage: "person.crop.circle") }
                        .accessibilityHint("Connects Miniflux, Inoreader, The Old Reader, or BazQux.")
                    NavigationLink { SmartFoldersView() } label: { Label("Smart Folders", systemImage: "folder.badge.gearshape") }
                    NavigationLink { FilterRulesView() } label: { Label("Filter Rules", systemImage: "line.3.horizontal.decrease") }
                    NavigationLink { SavedSearchesView() } label: { Label("Persistent Searches", systemImage: "magnifyingglass") }
                    NavigationLink { CategoriesManageView() } label: { Label("Categories", systemImage: "tag") }
                    NavigationLink { DeletedArticlesView() } label: { Label("Deleted Articles", systemImage: "trash") }
                    NavigationLink { DownloadsView() } label: { Label("Downloads", systemImage: "arrow.down.circle") }
                    NavigationLink { ArticleActionOrderView() } label: { Label("Article Actions", systemImage: "list.number") }
                    Toggle("Notifications for new articles", isOn: $notificationsEnabled)
                        .accessibilityHint("Posts a notification after a refresh finds new articles.")
                        .onChange(of: notificationsEnabled) { _, enabled in
                            if enabled { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } }
                        }
                } header: {
                    Text("Library")
                        .accessibilityAddTraits(.isHeader)
                }

                Section {
                    if youtubeAccount.isSignedIn {
                        Text("Signed in to YouTube")
                            .accessibilityLabel("Signed in to YouTube")
                        Text("Subscriptions and Recommendations are in Search Feeds and Podcasts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Sign Out of YouTube", role: .destructive) {
                            youtubeAccount.signOut()
                        }
                        .accessibilityHint("Removes the saved YouTube sign-in from this device.")
                    } else {
                        Button {
                            showingYouTubeSignIn = true
                        } label: {
                            Label("Sign In to YouTube", systemImage: "person.crop.circle")
                        }
                        .accessibilityHint("Shows a code to enter on YouTube's activation page. Your password is never typed into the app.")
                    }
                } header: {
                    Text("YouTube Account")
                        .accessibilityAddTraits(.isHeader)
                }

                Section {
                    Toggle("Bullet markers on lists", isOn: $readerBullets)
                        .accessibilityHint("Reads list items with a bullet marker in the reader.")
                    Toggle("Announce quotes", isOn: $readerQuotes)
                        .accessibilityHint("Marks quoted passages with Quote and End of quote in the reader.")
                    Toggle("Say link targets", isOn: $readerLinks)
                        .accessibilityHint("Reads each link's address after its text in feed articles.")
                    Toggle("Say image descriptions", isOn: $readerAltText)
                        .accessibilityHint("Reads image alt text as Image descriptions in feed articles.")
                    Picker("Search covers", selection: $searchScope) {
                        Text("Titles only").tag("titles")
                        Text("Titles and article text").tag("titlesText")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Search covers")
                } header: {
                    Text("Reading")
                        .accessibilityAddTraits(.isHeader)
                }

                Section {
                    Text(AppleIntelligence.status.message)
                    if AppleIntelligence.isSupported {
                        Toggle("Apple Intelligence actions", isOn: $appleIntelligenceEnabled)
                            .accessibilityHint("Shows Summarize, Key Points, Ask, and Brief Me. Everything runs privately on this device.")
                    }
                    Text("With Siri or Shortcuts, say \"Brief me with BlindRSS\", \"Summarize an article in BlindRSS\", \"Ask BlindRSS about an article\", \"How many unread articles in BlindRSS\", or \"Refresh BlindRSS\". Siri can also act on the article you are reading, and Spotlight finds recent articles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Apple Intelligence and Siri")
                        .accessibilityAddTraits(.isHeader)
                }

                Section {
                    Picker("Remove old articles", selection: $retentionDays) {
                        Text("Never").tag(0)
                        Text("After 7 days").tag(7)
                        Text("After 30 days").tag(30)
                        Text("After 90 days").tag(90)
                        Text("After 180 days").tag(180)
                        Text("After 1 year").tag(365)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Remove old articles")
                    .accessibilityHint("Favorites are never removed. Hosted accounts keep their own history.")
                    Picker("When articles are deleted", selection: $deleteBehavior) {
                        Text("Move to Deleted Articles").tag("deleted")
                        Text("Delete permanently").tag("permanent")
                        Text("Move to a category").tag("category")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("When articles are deleted")
                    if deleteBehavior == "category" {
                        TextField("Category for deleted articles", text: $deleteCategory)
                            .accessibilityLabel("Category for deleted articles")
                    }
                    Toggle("Ask before deleting articles", isOn: $confirmDeleteArticles)
                        .accessibilityHint("Shows a confirmation before an article is deleted.")
                } header: {
                    Text("Articles")
                        .accessibilityAddTraits(.isHeader)
                }

                Section {
                    NavigationLink { UserGuideView() } label: { Label("User Guide", systemImage: "book") }
                    NavigationLink { OpenArticleByURLView() } label: { Label("Open Article by URL", systemImage: "link") }
                    NavigationLink { OpenMediaURLView() } label: { Label("Open Media URL", systemImage: "play.circle") }
                    NavigationLink { SiteCookiesView() } label: { Label("Site Cookies", systemImage: "birthday.cake") }
                } header: {
                    Text("Tools")
                        .accessibilityAddTraits(.isHeader)
                }

                Section {
                    Button {
                        showingExporter = true
                    } label: {
                        Label("Export OPML", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityHint("Saves your subscriptions as an OPML file.")
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import OPML", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityHint("Adds subscriptions from an OPML file.")
                    Button {
                        showingTakeoutImporter = true
                    } label: {
                        Label("Import YouTube Takeout", systemImage: "square.and.arrow.down.on.square")
                    }
                    .accessibilityHint("Adds your YouTube subscriptions and playlists from a Google Takeout ZIP file.")
                } header: {
                    Text("Subscriptions")
                        .accessibilityAddTraits(.isHeader)
                }

                Section {
                    Text("BlindRSS for iOS \(appVersion)")
                        .accessibilityLabel("BlindRSS for iOS version \(appVersion)")
                    Link("BlindRSS on GitHub", destination: URL(string: "https://github.com/serrebidev/BlindRSS-iOS")!)
                        .accessibilityHint("Opens the project page in your browser.")
                    Link("Desktop BlindRSS", destination: URL(string: "https://github.com/serrebidev/BlindRSS")!)
                        .accessibilityHint("Opens the desktop project page in your browser.")
                } header: {
                    Text("About")
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(isPresented: $showingExporter,
                          document: OPMLDocument(data: OPMLService.export(feeds: feeds)),
                          contentType: .xml, defaultFilename: "blindrss-subscriptions") { _ in }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.xml, .data]) { result in
                importOPML(result)
            }
            .fileImporter(isPresented: $showingTakeoutImporter, allowedContentTypes: [.zip]) { result in
                importTakeout(result)
            }
            .sheet(isPresented: $showingYouTubeSignIn) {
                YouTubeSignInView()
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private func importTakeout(_ result: Result<URL, Error>) {
        guard let url = try? result.get(),
              url.startAccessingSecurityScopedResource(),
              let data = try? Data(contentsOf: url) else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        let entries = TakeoutService.feedEntries(fromTakeout: data)
        guard !entries.isEmpty else {
            Announcer.announce("No YouTube subscriptions found in that Takeout file.")
            return
        }
        let existing = Set(feeds.map(\.url))
        let fresh = entries.filter { !existing.contains($0.feedURL) }
        Announcer.announce("Found \(entries.count) YouTube feeds. Importing \(fresh.count) new ones.")
        Task {
            var added = 0
            for entry in fresh {
                if (try? await LibraryStore().addFeed(urlString: entry.feedURL, in: context)) != nil { added += 1 }
            }
            Announcer.announce("YouTube Takeout import complete. \(added) subscriptions added.")
        }
    }

    private func importOPML(_ result: Result<URL, Error>) {
        guard let url = try? result.get(),
              url.startAccessingSecurityScopedResource(),
              let data = try? Data(contentsOf: url) else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        let parsed = OPMLService.parse(data: data)
        Announcer.announce("Found \(parsed.count) feeds in OPML file. Importing.")
        Task {
            for item in parsed {
                _ = try? await LibraryStore().addFeed(urlString: item.xmlURL, category: item.category, in: context)
            }
            Announcer.announce("OPML import complete.")
        }
    }
}

struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Persistent Searches (desktop Searches)

/// Saved searches, created here and browsed from the sidebar's
/// Searches section. Desktop keeps these in state.json's searches.
struct SavedSearchesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedSearch.position) private var searches: [SavedSearch]
    @State private var name = ""
    @State private var term = ""

    var body: some View {
        List {
            if !searches.isEmpty {
                Section {
                    ForEach(searches) { search in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(search.name)
                            Text(search.term).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(search.name), searches for \(search.term)")
                        .accessibilityHint("Shows search actions.")
                        .touchSwipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(search) } label: { Label("Delete", systemImage: "trash") }
                        }
                        .accessibilityAction { delete(search) } label: { Label("Delete Search", systemImage: "trash") }
                    }
                } header: { Text("Saved Searches").accessibilityAddTraits(.isHeader) }
            }
            Section {
                TextField("Search name", text: $name).accessibilityLabel("Search name")
                TextField("Search for", text: $term).accessibilityLabel("Search for")
                    .accessibilityHint("Articles whose title, text, or author contains this are collected.")
                Button("Save Search") {
                    let trimmedName = name.trimmingCharacters(in: .whitespaces)
                    let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
                    guard !trimmedName.isEmpty, !trimmedTerm.isEmpty else { return }
                    context.insert(SavedSearch(name: trimmedName, term: trimmedTerm, position: searches.count))
                    try? context.save()
                    Announcer.announce("Saved search \(trimmedName). Find it under Searches in the feed list.")
                    name = ""; term = ""
                }
                .accessibilityHint("Adds this search to the Searches section of the feed list.")
            } header: { Text("New Search").accessibilityAddTraits(.isHeader) }
        }
        .navigationTitle("Persistent Searches")
    }

    private func delete(_ search: SavedSearch) {
        context.delete(search)
        try? context.save()
        Announcer.announce("Deleted search \(search.name).")
    }
}

// MARK: - Category management (desktop Categories preferences page)

/// Rename or delete the categories articles are browsed under. Renaming
/// moves feeds in the category and updates article moves and labels;
/// deleting returns feeds to Uncategorized and un-moves articles.
struct CategoriesManageView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query private var articles: [Article]
    @State private var renaming: String?
    @State private var newName = ""

    private var names: [String] {
        var set = Set<String>()
        for feed in feeds { set.insert(feed.category) }
        for article in articles {
            if let moved = article.movedCategory { set.insert(moved) }
            set.formUnion(article.labels)
        }
        return set.sorted()
    }

    var body: some View {
        List {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .accessibilityLabel("Category \(name)")
                    .accessibilityHint("Shows category actions.")
                    .touchSwipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(name) } label: { Label("Delete", systemImage: "trash") }
                        Button { renaming = name; newName = name } label: { Label("Rename", systemImage: "pencil") }
                    }
                    .accessibilityAction { renaming = name; newName = name } label: { Label("Rename", systemImage: "pencil") }
                    .accessibilityAction { delete(name) } label: { Label("Delete Category", systemImage: "trash") }
            }
        }
        .navigationTitle("Categories")
        .alert("Rename Category", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("New name", text: $newName).accessibilityLabel("New category name")
            Button("Rename") { if let old = renaming { rename(from: old, to: newName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func rename(from old: String, to raw: String) {
        let new = raw.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != old else { return }
        for feed in feeds where feed.category == old { feed.category = new }
        for article in articles {
            if article.movedCategory == old { article.movedCategory = new }
            if article.labels.contains(old) {
                article.labels = article.labels.map { $0 == old ? new : $0 }
            }
        }
        try? context.save()
        Announcer.announce("Category \(old) renamed to \(new).")
    }

    private func delete(_ name: String) {
        for feed in feeds where feed.category == name { feed.category = Category.uncategorized }
        for article in articles {
            if article.movedCategory == name { article.movedCategory = nil; article.hiddenFromFeed = false }
            article.labels.removeAll { $0 == name }
        }
        try? context.save()
        Announcer.announce("Category \(name) deleted.")
    }
}

// MARK: - Open by URL (desktop Open Article by URL / Open Media URL)

/// Fetches and reads one web article by address, without subscribing.
struct OpenArticleByURLView: View {
    @State private var urlText = ""
    @State private var blocks: [ReaderBlock] = []
    @State private var status = ""
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                TextField("Article URL", text: $urlText)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .accessibilityLabel("Article URL")
                Button("Open Article") { Task { await open() } }
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                    .accessibilityHint("Fetches the page and shows its readable text here.")
                if isLoading { ProgressView("Loading").accessibilityLabel("Loading") }
                if !status.isEmpty { Text(status).accessibilityLabel(status) }
            }
            if !blocks.isEmpty {
                Section {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        Text(block.text)
                            .font(block.isHeading ? .headline : .body)
                            .accessibilityAddTraits(block.isHeading ? .isHeader : [])
                            .accessibilityLabel(block.text)
                    }
                } header: { Text("Article").accessibilityAddTraits(.isHeader) }
            }
        }
        .navigationTitle("Open Article by URL")
    }

    private func open() async {
        let raw = urlText.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: raw.hasPrefix("http") ? raw : "https://\(raw)") else {
            status = "That is not a valid URL."
            return
        }
        isLoading = true
        status = ""
        blocks = []
        do {
            blocks = try await FullTextService.fetchFullText(articleID: url.absoluteString,
                                                             url: url.absoluteString, feedText: "")
            status = blocks.isEmpty ? "No readable text was found on that page." : ""
            if !blocks.isEmpty { Announcer.announce("Article loaded. \(blocks.count) paragraphs.") }
        } catch {
            status = "Could not load that page. \(error.localizedDescription)"
        }
        isLoading = false
    }
}

/// Plays one media address directly in the player.
struct OpenMediaURLView: View {
    @Environment(AudioPlayer.self) private var player
    @State private var urlText = ""

    var body: some View {
        Form {
            Section {
                TextField("Media URL", text: $urlText)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .accessibilityLabel("Media URL")
                    .accessibilityHint("The address of an audio or video file or stream.")
                Button("Play") { play() }
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityHint("Starts playing this media in the player.")
            }
        }
        .navigationTitle("Open Media URL")
    }

    private func play() {
        let raw = urlText.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: raw.hasPrefix("http") ? raw : "https://\(raw)") else {
            Announcer.announce("That is not a valid URL.")
            return
        }
        // A detached article carries the media to the player; it is
        // never inserted into the library.
        let article = Article(id: "url:\(url.absoluteString)",
                              title: url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent,
                              url: url.absoluteString, content: "",
                              mediaURL: url.absoluteString)
        player.play(article: article)
        Announcer.announce("Playing \(article.title).")
    }
}

// MARK: - Site Cookies (desktop Site Cookies)

/// Imports a Netscape cookies.txt (exported from a browser) into the
/// shared cookie storage, so paywalled feeds and full-text fetches can
/// use the signed-in session, as the desktop's cookie jar does.
struct SiteCookiesView: View {
    @State private var cookieCount = HTTPCookieStorage.shared.cookies?.count ?? 0
    @State private var showingImporter = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Text("\(cookieCount) cookies stored")
                    .accessibilityLabel("\(cookieCount) cookies stored")
                Button {
                    showingImporter = true
                } label: {
                    Label("Import Cookies (cookies.txt)", systemImage: "square.and.arrow.down")
                }
                .accessibilityHint("Imports cookies exported from a browser in Netscape cookies.txt format.")
                if cookieCount > 0 {
                    Button(role: .destructive) {
                        for cookie in HTTPCookieStorage.shared.cookies ?? [] {
                            HTTPCookieStorage.shared.deleteCookie(cookie)
                        }
                        cookieCount = 0
                        Announcer.announce("All cookies cleared.")
                    } label: {
                        Label("Clear All Cookies", systemImage: "trash")
                    }
                }
                if let message {
                    Text(message).accessibilityLabel(message)
                }
            } footer: {
                Text("Cookies are used when fetching feeds and full article text from sites that need a sign-in.")
            }
        }
        .navigationTitle("Site Cookies")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.data, .plainText, .text]) { result in
            importCookies(result)
        }
    }

    private func importCookies(_ result: Result<URL, Error>) {
        guard let url = try? result.get(),
              url.startAccessingSecurityScopedResource(),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
            message = "Could not read that file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        var imported = 0
        for line in text.split(whereSeparator: \.isNewline) {
            var trimmed = String(line)
            if trimmed.hasPrefix("#HttpOnly_") { trimmed = String(trimmed.dropFirst("#HttpOnly_".count)) }
            else if trimmed.hasPrefix("#") { continue }
            let fields = trimmed.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7 else { continue }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: fields[0], .path: fields[2].isEmpty ? "/" : fields[2],
                .name: fields[5], .value: fields[6],
            ]
            if fields[3].uppercased() == "TRUE" { properties[.secure] = "TRUE" }
            if let expiry = Double(fields[4]), expiry > 0 {
                properties[.expires] = Date(timeIntervalSince1970: expiry)
            }
            if let cookie = HTTPCookie(properties: properties) {
                HTTPCookieStorage.shared.setCookie(cookie)
                imported += 1
            }
        }
        cookieCount = HTTPCookieStorage.shared.cookies?.count ?? 0
        message = imported > 0 ? "Imported \(imported) cookies." : "No cookies found in that file."
        Announcer.announce(message ?? "")
    }
}

// MARK: - User Guide (desktop User Guide)

/// A short built-in guide, mirroring the desktop's User Guide dialog:
/// the same workflows, written for VoiceOver.
struct UserGuideView: View {
    var body: some View {
        List {
            Section {
                Text("BlindRSS keeps your feeds, podcasts, and articles in one list. The feed list shows library views first (All Articles, Unread, Read, Favorites, Feeds with Errors), then your saved Searches, then Categories, then feeds grouped by category. Choose a feed or view to read its articles; opening an article marks it read, and opening a podcast episode also starts playing it.")
            } header: { Text("Getting Around").accessibilityAddTraits(.isHeader) }
            Section {
                Text("Add Feed takes a feed address, a site address (its feed is detected), or a profile page from Mastodon, Bluesky, Reddit, Lemmy, Groups.io, GitHub, or YouTube; profiles are converted to their feeds automatically. Search Feeds and Podcasts searches Apple Podcasts, gPodder, and a dozen directories at once. Subscriptions can move between devices and the desktop app with OPML import and export, and YouTube subscriptions come in with a Google Takeout ZIP.")
            } header: { Text("Adding Feeds").accessibilityAddTraits(.isHeader) }
            Section {
                Text("Every row carries its actions in the VoiceOver actions menu: articles can be read, marked, favorited, downloaded, shared, and deleted in the order set in Settings, Article Actions; feeds can be refreshed, edited, archived, and deleted. Rotors jump between unread, favorite, and audio articles. A two-finger double tap (Magic Tap) pauses and resumes playback anywhere.")
            } header: { Text("VoiceOver").accessibilityAddTraits(.isHeader) }
            Section {
                Text("Filter Rules act on articles as they arrive: mark read, favorite, delete, skip the notification, move to a category, or label. Smart Folders collect articles by saved conditions. Persistent Searches in Settings add named searches to the feed list. Deleted articles rest in Deleted Articles until restored or purged, unless Settings sends deletes to a category or deletes permanently.")
            } header: { Text("Organizing").accessibilityAddTraits(.isHeader) }
            Section {
                Text("The player resumes episodes where you stopped, keeps a play queue, skips silence, and has a sleep timer and a ten-band equalizer. Downloads play offline. AirPlay sends audio to other devices from the player's route picker.")
            } header: { Text("Player").accessibilityAddTraits(.isHeader) }
        }
        .navigationTitle("User Guide")
    }
}
