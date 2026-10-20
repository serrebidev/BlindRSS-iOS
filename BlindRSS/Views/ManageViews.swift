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
                    .swipeActions(edge: .trailing) {
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
                    .swipeActions(edge: .trailing) {
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
struct FilterRulesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FilterRule.position) private var rules: [FilterRule]
    @State private var name = ""
    @State private var field = "title"
    @State private var contains = ""
    @State private var action = "markRead"

    var body: some View {
        List {
            Section {
                ForEach(rules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.name)
                            Text("\(rule.field) contains \(rule.contains): \(rule.action)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Enabled", isOn: Binding(get: { rule.enabled }, set: { rule.enabled = $0; try? context.save() }))
                            .labelsHidden().accessibilityLabel("Enabled")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(rule.name)
                    .accessibilityHint("Shows rule actions.")
                    .swipeActions(edge: .trailing) {
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
                Picker("Action", selection: $action) {
                    Text("Mark read").tag("markRead"); Text("Favorite").tag("favorite"); Text("Delete").tag("delete")
                }.accessibilityElement(children: .contain).accessibilityLabel("Action")
                Button("Create Filter Rule") {
                    guard !name.isEmpty, !contains.isEmpty else { return }
                    context.insert(FilterRule(name: name, field: field, contains: contains, action: action, position: rules.count))
                    try? context.save()
                    Announcer.announce("Created filter rule \(name).")
                    name = ""; contains = ""
                }
                .accessibilityHint("Applies this rule to new articles as feeds refresh.")
            } header: { Text("New Rule").accessibilityAddTraits(.isHeader) }
        }
        .navigationTitle("Filter Rules")
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
                Button(isSyncing ? "Syncing" : "Save and Sync Now") {
                    HostedConfig(kind: kind, baseURL: baseURL, username: username, token: token).save()
                    Task {
                        isSyncing = true
                        if let config = HostedConfig.load() { _ = try? await HostedSync().sync(config: config, in: context) }
                        isSyncing = false
                    }
                }
                .disabled(token.isEmpty || isSyncing)
                .accessibilityHint("Saves the account and pulls feeds and articles into this device.")
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

/// Feed properties (desktop Feed Properties): rename and recategorize.
struct FeedEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var feed: Feed
    @State private var title: String = ""
    @State private var category: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Feed title", text: $title).accessibilityLabel("Feed title")
                TextField("Category", text: $category).accessibilityLabel("Category")
                Text(feed.url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .accessibilityLabel("Feed URL \(feed.url)")
            }
            .navigationTitle("Feed Properties")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        feed.title = title; feed.titleIsCustom = true; feed.category = category
                        Announcer.announce("Saved \(title).")
                        dismiss()
                    }
                }
            }
            .onAppear { title = feed.title; category = feed.category }
        }
    }
}

/// Downloads list (desktop Downloading Media) with the equalizer player.
struct DownloadsView: View {
    @Query(sort: \Article.date, order: .reverse) private var all: [Article]
    private var downloaded: [Article] { all.filter { DownloadService.localURL(for: $0) != nil } }

    var body: some View {
        Group {
            if downloaded.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle",
                                       description: Text("Download an episode from an article to listen offline."))
            } else {
                List(downloaded) { article in
                    NavigationLink(article.title) {
                        if let url = DownloadService.localURL(for: article) {
                            EnginePlayerView(fileURL: url, title: article.title)
                        }
                    }
                    .accessibilityLabel(article.title)
                    .accessibilityHint("Opens the equalizer player for this download.")
                }
            }
        }
        .navigationTitle("Downloads")
    }
}

/// Equalizer player for a downloaded file (desktop Equalizer).
struct EnginePlayerView: View {
    @State private var engine = EnginePlayer()
    let fileURL: URL
    let title: String
    private let bandNames = ["60 Hz", "230 Hz", "910 Hz", "3.6 kHz", "14 kHz"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Button { engine.togglePlayPause() } label: {
                    Label(engine.isPlaying ? "Pause" : "Play", systemImage: engine.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
                .accessibilityHint("Plays this download through the equalizer.")

                Text("Equalizer").font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(0..<5, id: \.self) { index in
                    VStack(alignment: .leading) {
                        Text("\(bandNames[index]): \(Int(engine.bandGains[index])) dB")
                        Slider(value: Binding(get: { engine.bandGains[index] }, set: { engine.bandGains[index] = $0 }), in: -12...12, step: 1)
                            .accessibilityLabel("\(bandNames[index]) gain")
                            .accessibilityValue("\(Int(engine.bandGains[index])) decibels")
                    }
                    .accessibilityElement(children: .combine)
                }
                Toggle("Skip silence", isOn: $engine.skipSilence)
                    .accessibilityHint("Jumps over quiet parts of the download.")
                AirPlayRouteView().frame(width: 44, height: 44).accessibilityLabel("AirPlay and output devices")
            }
            .padding()
        }
        .navigationTitle("Equalizer Player")
        .onAppear { if engine.currentTitle.isEmpty { engine.play(fileURL: fileURL, title: title) } }
        .onDisappear { engine.stop() }
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
