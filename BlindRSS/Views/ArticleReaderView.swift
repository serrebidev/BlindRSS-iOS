// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import AppIntents
import SwiftUI

/// Reading pane (desktop reading pane and article window). Continuous text
/// in a ScrollView so it stays usable at the largest Dynamic Type sizes;
/// headings carry the header trait for Rotor navigation (WCAG 1.3.1).
struct ArticleReaderView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.openURL) private var openURL
    @State private var fullText: [ReaderBlock]?
    @State private var isFetchingFullText = false
    @State private var transcript: [String]?
    @State private var isFetchingTranscript = false
    @State private var translatedBlocks: [ReaderBlock]?
    @State private var showTranslation = false
    @State private var isTranslating = false
    @State private var threadLines: [String]?
    @State private var isFetchingThread = false
    @State private var isResolvingStream = false
    @State private var aiHeading: String?
    @State private var aiText: String?
    @State private var isThinking = false
    @State private var question = ""
    @AppStorage("appleIntelligence.enabled") private var appleIntelligenceEnabled = true
    let article: Article

    private var youTubeID: String? { YouTubeService.videoID(from: article.url) }
    private var lemmyPost: (base: String, id: String)? { ForumService.lemmyPost(from: article.url) }

    var body: some View {
        // Strip the HTML once per render. Body text and description
        // chapters each used to strip it, and chapters did so twice.
        let plainContent = HTMLText.plainText(from: article.content)
        let feedText = plainContent.isEmpty ? HTMLText.plainText(from: article.summary) : plainContent
        let bodyBlocks = (showTranslation ? translatedBlocks : nil) ?? fullText ?? HTMLText.blocks(fromPlainText: feedText)
        let descriptionChapters = YouTubeService.chapters(fromDescription: plainContent)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(article.title)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 8) {
                    if let feedTitle = article.feed?.title {
                        Text(feedTitle).foregroundStyle(.secondary)
                    }
                    if !article.author.isEmpty {
                        Text(article.author).foregroundStyle(.secondary)
                    }
                    if let date = article.date {
                        Text(date, style: .date).foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)

                if article.hasMedia {
                    Button {
                        player.play(article: article)
                    } label: {
                        Label(player.currentArticle?.id == article.id && player.isPlaying ? "Pause" : "Play",
                              systemImage: player.currentArticle?.id == article.id && player.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .accessibilityHint("Plays the audio or video attached to this article.")
                }

                if let youTubeID {
                    YouTubePlayerView(videoID: youTubeID)
                        // Full width at 16:9; a fixed 220 points was a
                        // thin strip on iPad and cropped on small phones.
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .accessibilityLabel("YouTube video player")
                        .accessibilityHint("Plays the video on this page.")
                }

                HStack(spacing: 12) {
                    Button {
                        // Read the model here on the main actor; the fetch runs off it.
                        let articleID = article.id
                        let url = article.url
                        Task {
                            isFetchingFullText = true
                            do {
                                let fetched = try await FullTextService.fetchFullText(articleID: articleID, url: url, feedText: feedText)
                                fullText = fetched
                                FullTextCache.shared.store(fetched, for: articleID)
                                Announcer.announce("Full text loaded.")
                            } catch {
                                Announcer.announce(error.localizedDescription)
                            }
                            isFetchingFullText = false
                        }
                    } label: {
                        Label(isFetchingFullText ? "Fetching" : "Fetch Full Text", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(isFetchingFullText)
                    .accessibilityHint("Recovers the complete article when the feed only sent a summary.")
                    if article.hasMedia {
                        Button {
                            Task { try? await DownloadService.download(article: article) }
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                        .accessibilityHint("Downloads the media for offline listening.")
                    }
                    Button {
                        if showTranslation {
                            showTranslation = false
                            Announcer.announce("Showing the original article.")
                        } else if translatedBlocks != nil {
                            showTranslation = true
                            Announcer.announce("Showing the translation.")
                        } else {
                            Task { await translateBody(blocks: bodyBlocks) }
                        }
                    } label: {
                        Label(isTranslating ? "Translating" : (showTranslation ? "Show Original" : "Translate"),
                              systemImage: "character.bubble")
                    }
                    .disabled(isTranslating)
                    .accessibilityHint("Translates this article into your device language: on this device with Apple Translate when both languages are downloaded, otherwise with a public translation service. No account or key is needed.")
                }

                if let youTubeID {
                    // Native stream playback (research 0.1.13): the
                    // resolved stream plays in the app's own player,
                    // with resume, speed, and SponsorBlock skipping,
                    // and can be downloaded for offline listening.
                    HStack(spacing: 12) {
                        Button {
                            Task { await playStream(videoID: youTubeID) }
                        } label: {
                            Label(isResolvingStream ? "Resolving Stream" : "Play Stream", systemImage: "play.rectangle")
                        }
                        .disabled(isResolvingStream)
                        .accessibilityHint("Plays this video's stream in the app player instead of the embedded web player.")
                        Button {
                            Task { await downloadStream(videoID: youTubeID) }
                        } label: {
                            Label("Download Stream", systemImage: "arrow.down.circle")
                        }
                        .disabled(isResolvingStream)
                        .accessibilityHint("Downloads this video's stream for offline listening.")
                    }
                }

                if appleIntelligenceEnabled, AppleIntelligence.isSupported {
                    appleIntelligenceSection(bodyBlocks: bodyBlocks)
                }

                if !descriptionChapters.isEmpty, article.chapters.isEmpty {
                    Text("Chapters").font(.headline).accessibilityAddTraits(.isHeader)
                    ForEach(descriptionChapters) { chapter in
                        Text("\(AudioPlayer.formatTime(chapter.start)) \(chapter.title)")
                            .accessibilityLabel("\(chapter.title), \(AudioPlayer.formatTime(chapter.start))")
                    }
                }

                if !article.chapters.isEmpty {
                    Text("Chapters")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(article.chapters.sorted(by: { $0.start < $1.start })) { chapter in
                        Button {
                            player.seek(to: chapter.start)
                        } label: {
                            Label("\(AudioPlayer.formatTime(chapter.start)) \(chapter.title)", systemImage: "list.bullet")
                        }
                        .accessibilityLabel("\(chapter.title), \(AudioPlayer.formatTime(chapter.start))")
                        .accessibilityHint("Moves playback to this chapter.")
                    }
                }

                // One element per paragraph, so VoiceOver can move through a
                // long article by paragraph and by heading.
                ForEach(Array(bodyBlocks.enumerated()), id: \.offset) { _, block in
                    Text(block.text)
                        .font(block.isHeading ? .headline : .body)
                        .accessibilityAddTraits(block.isHeading ? .isHeader : [])
                        .textSelection(.enabled)
                }

                if let youTubeID {
                    // Desktop YouTube Transcript section: captions as
                    // readable paragraphs under the article.
                    Text("Transcript").font(.headline).accessibilityAddTraits(.isHeader)
                    if let transcript {
                        if transcript.isEmpty {
                            Text("No transcript is available for this video.")
                                .accessibilityLabel("No transcript is available for this video.")
                        } else {
                            ForEach(Array(transcript.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .accessibilityLabel(paragraph)
                                    .textSelection(.enabled)
                            }
                        }
                    } else {
                        Button {
                            Task {
                                isFetchingTranscript = true
                                transcript = await YouTubeService.transcriptParagraphs(videoID: youTubeID)
                                isFetchingTranscript = false
                                Announcer.announce(transcript?.isEmpty == false
                                    ? "Transcript loaded." : "No transcript is available for this video.")
                            }
                        } label: {
                            Label(isFetchingTranscript ? "Loading Transcript" : "Load Transcript", systemImage: "captions.bubble")
                        }
                        .disabled(isFetchingTranscript)
                        .accessibilityHint("Fetches this video's captions and shows them as text.")
                    }
                }

                if let lemmyPost {
                    // Lemmy threads (research 0.1.13): the post's
                    // comments from the instance's public API, indented
                    // by depth like the desktop's thread view.
                    Text("Thread").font(.headline).accessibilityAddTraits(.isHeader)
                    if let threadLines {
                        if threadLines.isEmpty {
                            Text("No comments on this post yet.")
                                .accessibilityLabel("No comments on this post yet.")
                        } else {
                            ForEach(Array(threadLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .accessibilityLabel(line)
                                    .textSelection(.enabled)
                            }
                        }
                    } else {
                        Button {
                            Task {
                                isFetchingThread = true
                                if let thread = await ForumService.thread(base: lemmyPost.base, postID: lemmyPost.id) {
                                    threadLines = ForumService.lines(for: thread)
                                    Announcer.announce("Thread loaded. \(thread.comments.count) comments.")
                                } else {
                                    threadLines = []
                                    Announcer.announce("Could not load this thread.")
                                }
                                isFetchingThread = false
                            }
                        } label: {
                            Label(isFetchingThread ? "Loading Thread" : "Load Thread", systemImage: "text.bubble")
                        }
                        .disabled(isFetchingThread)
                        .accessibilityHint("Fetches this post's comments from its Lemmy instance.")
                    }
                }

                if let url = URL(string: article.url) {
                    Link("Open original article", destination: url)
                        .accessibilityHint("Opens the full article in your browser.")
                }
            }
            .padding()
            // Fluid width: the reader fills the window at every screen
            // size, iPhone SE through iPad Pro, portrait and landscape.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Writing Tools (iOS 18) on selected article text: proofread,
        // summarize, or rewrite a passage.
        .writingTools()
        // Siri onscreen awareness (iOS 18.2): "summarize this" or "send
        // this to Mom" acts on the open article (ArticleEntity).
        .userActivity("org.serrebidev.BlindRSS.article") { activity in
            activity.title = article.title
            if #available(iOS 18.2, *) {
                activity.appEntityIdentifier = EntityIdentifier(for: ArticleEntity.self, identifier: article.id)
            }
        }
        // Chapters rotor: rotate to Chapters, swipe to jump between them.
        .accessibilityRotor("Chapters") {
            ForEach(article.chapters.sorted(by: { $0.start < $1.start })) { chapter in
                AccessibilityRotorEntry(chapter.title, id: chapter.id)
            }
        }
        .task {
            // The article list prefetches full text into the shared
            // cache; open with it already loaded when it is there.
            if fullText == nil, let cached = FullTextCache.shared.blocks(for: article.id) {
                fullText = cached
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let url = URL(string: article.url) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    /// Translates the visible blocks into the device's preferred
    /// language through the keyless public backends, keeping each
    /// block's heading flag so the translated article navigates the
    /// same way.
    private func translateBody(blocks: [ReaderBlock]) async {
        let target = Locale.current.language.languageCode?.identifier ?? "en"
        isTranslating = true
        // Apple Translate first: private, offline, and no rate limits,
        // when the article's language and the device language are both
        // downloaded on this device.
        if let onDevice = await AppleIntelligence.translateOnDevice(blocks.map(\.text), to: Locale.current.language) {
            translatedBlocks = zip(blocks, onDevice).map { ReaderBlock(isHeading: $0.isHeading, text: $1) }
            showTranslation = true
            isTranslating = false
            Announcer.announce("Translation loaded.")
            return
        }
        var result: [ReaderBlock] = []
        var failed = false
        for block in blocks {
            if let translated = await TranslateService.translate(block.text, to: target) {
                result.append(ReaderBlock(isHeading: block.isHeading, text: translated))
            } else {
                failed = true
                break
            }
        }
        isTranslating = false
        if failed {
            Announcer.announce("Translation failed. The public translation services did not answer.")
        } else {
            translatedBlocks = result
            showTranslation = true
            Announcer.announce("Translation loaded.")
        }
    }

    /// Summarize, Key Points, and a question box (Apple Intelligence,
    /// on device). The answer shows under its own heading, one line per
    /// paragraph or point, and is spoken when it arrives.
    @ViewBuilder
    private func appleIntelligenceSection(bodyBlocks: [ReaderBlock]) -> some View {
        Text("Apple Intelligence").font(.headline).accessibilityAddTraits(.isHeader)
        HStack(spacing: 12) {
            Button {
                Task { await runAppleIntelligence(.summary, bodyBlocks: bodyBlocks) }
            } label: {
                Label("Summarize", systemImage: "text.append")
            }
            .accessibilityHint("Summarizes this article privately on this device with Apple Intelligence.")
            Button {
                Task { await runAppleIntelligence(.keyPoints, bodyBlocks: bodyBlocks) }
            } label: {
                Label("Key Points", systemImage: "list.bullet")
            }
            .accessibilityHint("Lists this article's key points with Apple Intelligence.")
        }
        .disabled(isThinking)
        HStack(spacing: 12) {
            TextField("Ask about this article", text: $question)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit { askQuestion(bodyBlocks: bodyBlocks) }
                .accessibilityHint("Type a question, then send. Apple Intelligence answers from this article only.")
            Button("Ask") { askQuestion(bodyBlocks: bodyBlocks) }
                .disabled(isThinking || question.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        if isThinking {
            ProgressView("Apple Intelligence is working")
        }
        if let aiHeading, let aiText {
            Text(aiHeading).font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(Array(aiText.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                Text(line).textSelection(.enabled)
            }
        }
    }

    private func askQuestion(bodyBlocks: [ReaderBlock]) {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty, !isThinking else { return }
        Task { await runAppleIntelligence(.question(asked), bodyBlocks: bodyBlocks) }
    }

    /// Feeds often send only a teaser, so the full article is recovered
    /// first (and shown); YouTube videos add their transcript.
    private func runAppleIntelligence(_ request: AppleIntelligence.Request, bodyBlocks: [ReaderBlock]) async {
        guard !isThinking else { return }
        isThinking = true
        defer { isThinking = false }
        Announcer.announce("Apple Intelligence is working.")
        var text = bodyBlocks.map(\.text).joined(separator: "\n")
        if fullText == nil, !showTranslation {
            text = await AppleIntelligence.readableText(of: article)
            fullText = FullTextCache.shared.blocks(for: article.id)
        }
        if let youTubeID, transcript == nil {
            transcript = await YouTubeService.transcriptParagraphs(videoID: youTubeID)
        }
        if let transcript, !transcript.isEmpty {
            text += "\nTranscript:\n" + transcript.joined(separator: "\n")
        }
        do {
            let result = try await AppleIntelligence.run(request, title: article.title, text: text)
            aiHeading = request.heading
            aiText = result
            Announcer.announce("\(request.heading). \(result)")
        } catch is CancellationError {
        } catch {
            aiHeading = "Apple Intelligence"
            aiText = error.localizedDescription
            Announcer.announce(error.localizedDescription)
        }
    }

    /// Resolves the video's stream and plays it in the app player on a
    /// detached copy of the article, so resume state stays keyed to
    /// the real article; SponsorBlock segments load alongside.
    private func playStream(videoID: String) async {
        isResolvingStream = true
        guard let url = await YouTubeStreamResolver.playbackURL(videoID: videoID) else {
            isResolvingStream = false
            Announcer.announce("Could not resolve a playable stream for this video.")
            return
        }
        let copy = Article(id: article.id, title: article.title, url: article.url,
                           content: "", mediaURL: url.absoluteString)
        player.play(article: copy)
        isResolvingStream = false
        if player.skipSponsorSegments {
            player.sponsorSegments = await SponsorBlockService.segments(videoID: videoID)
        }
    }

    private func downloadStream(videoID: String) async {
        isResolvingStream = true
        if let url = await YouTubeStreamResolver.playbackURL(videoID: videoID) {
            try? await DownloadService.downloadStream(url: url, for: article)
        } else {
            Announcer.announce("Could not resolve a downloadable stream for this video.")
        }
        isResolvingStream = false
    }
}

extension View {
    /// Full Apple Intelligence Writing Tools on this view's text (iOS 18).
    @ViewBuilder
    func writingTools() -> some View {
        if #available(iOS 18, *) {
            writingToolsBehavior(.complete)
        } else {
            self
        }
    }
}
