// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftUI

/// Reading pane (desktop reading pane and article window). Continuous text
/// in a ScrollView so it stays usable at the largest Dynamic Type sizes;
/// headings carry the header trait for Rotor navigation (WCAG 1.3.1).
struct ArticleReaderView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.openURL) private var openURL
    @State private var fullText: [ReaderBlock]?
    @State private var isFetchingFullText = false
    let article: Article

    private var youTubeID: String? { YouTubeService.videoID(from: article.url) }

    var body: some View {
        // Strip the HTML once per render. Body text and description
        // chapters each used to strip it, and chapters did so twice.
        let plainContent = HTMLText.plainText(from: article.content)
        let feedText = plainContent.isEmpty ? HTMLText.plainText(from: article.summary) : plainContent
        let bodyBlocks = fullText ?? HTMLText.blocks(fromPlainText: feedText)
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
                        .frame(height: 220)
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
                                fullText = try await FullTextService.fetchFullText(articleID: articleID, url: url, feedText: feedText)
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

                if let url = URL(string: article.url) {
                    Link("Open original article", destination: url)
                        .accessibilityHint("Opens the full article in your browser.")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Chapters rotor: rotate to Chapters, swipe to jump between them.
        .accessibilityRotor("Chapters") {
            ForEach(article.chapters.sorted(by: { $0.start < $1.start })) { chapter in
                AccessibilityRotorEntry(chapter.title, id: chapter.id)
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
}
