// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
            errorMessage = error.localizedDescription
            Announcer.announce("Could not subscribe. \(error.localizedDescription)")
        }
        isAdding = false
    }
}

/// Settings (desktop Settings subset for Phase 1). Every Toggle and Picker
/// keeps its visible label; nothing is labels-hidden without a replacement.
struct SettingsView: View {
    @AppStorage("refreshOnStartup") private var refreshOnStartup = true
    @AppStorage("playbackSpeed") private var playbackSpeed = 1.0
    @AppStorage("seekInterval") private var seekInterval = 30.0

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var feeds: [Feed]
    @State private var showingExporter = false
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Refresh on startup", isOn: $refreshOnStartup)
                        .accessibilityHint("Fetches new articles when the app opens.")
                    Toggle("Resume playback", isOn: .constant(true))
                        .accessibilityHint("Continues episodes where you left off.")
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
                } header: {
                    Text("Player")
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
                } header: {
                    Text("Subscriptions")
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
