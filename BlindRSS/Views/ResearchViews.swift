// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftData
import SwiftUI

/// Awesome RSS catalogue browser (research round 0.1.13): countries
/// and topics from plenaryapp/awesome-rss-feeds. Opening one downloads
/// only that entry's OPML file; its feeds subscribe with one tap.
struct AwesomeRSSView: View {
    var body: some View {
        List {
            Section {
                ForEach(AwesomeRSSService.catalogue.filter { $0.group == "Countries" }) { entry in
                    NavigationLink { AwesomeRSSEntryView(entry: entry) } label: { Text(entry.name) }
                        .accessibilityLabel("Awesome RSS, \(entry.name)")
                        .accessibilityHint("Lists the catalogue's feeds for \(entry.name).")
                }
            } header: { Text("Countries").accessibilityAddTraits(.isHeader) }
            Section {
                ForEach(AwesomeRSSService.catalogue.filter { $0.group == "Topics" }) { entry in
                    NavigationLink { AwesomeRSSEntryView(entry: entry) } label: { Text(entry.name) }
                        .accessibilityLabel("Awesome RSS, \(entry.name)")
                        .accessibilityHint("Lists the catalogue's feeds about \(entry.name).")
                }
            } header: { Text("Topics").accessibilityAddTraits(.isHeader) }
        }
        .navigationTitle("Awesome RSS Catalogue")
    }
}

struct AwesomeRSSEntryView: View {
    @Environment(\.modelContext) private var context
    @State private var store = LibraryStore()
    @State private var results: [PodcastService.FeedResult] = []
    @State private var isLoading = true
    let entry: AwesomeRSSService.Entry

    var body: some View {
        List {
            ForEach(groupedResults, id: \.category) { group in
                Section {
                    ForEach(group.results) { result in
                        Button {
                            Task { _ = try? await store.addFeed(urlString: result.url, in: context) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.title)
                                Text(result.url).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(result.title)
                        .accessibilityValue(result.url)
                        .accessibilityHint("Subscribes to this feed.")
                    }
                } header: { Text(group.category).accessibilityAddTraits(.isHeader) }
            }
            if !isLoading, results.isEmpty {
                Text("No feeds were found in this catalogue file.")
                    .accessibilityLabel("No feeds were found in this catalogue file.")
            }
        }
        .overlay { if isLoading { ProgressView("Loading").accessibilityLabel("Loading") } }
        .navigationTitle(entry.name)
        .task {
            results = await AwesomeRSSService.feeds(for: entry)
            isLoading = false
            Announcer.announce("\(results.count) feeds in \(entry.name).")
        }
    }

    private var groupedResults: [(category: String, results: [PodcastService.FeedResult])] {
        var order: [String] = []
        var byCategory: [String: [PodcastService.FeedResult]] = [:]
        for result in results {
            let key = result.website ?? "Feeds"
            if byCategory[key] == nil { order.append(key) }
            byCategory[key, default: []].append(result)
        }
        return order.map { (category: $0, results: byCategory[$0] ?? []) }
    }
}

/// One YouTube video from Discover's Video Search (research 0.1.13):
/// the embedded player, native stream playback with SponsorBlock
/// skipping, and the keyless Innertube transcript.
struct VideoResultView: View {
    @Environment(AudioPlayer.self) private var player
    @State private var transcript: [String]?
    @State private var isFetchingTranscript = false
    @State private var isResolvingStream = false
    let video: YouTubeService.VideoResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(video.title)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    if !video.channel.isEmpty { Text(video.channel).foregroundStyle(.secondary) }
                    if !video.durationText.isEmpty { Text(video.durationText).foregroundStyle(.secondary) }
                    if !video.publishedText.isEmpty { Text(video.publishedText).foregroundStyle(.secondary) }
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)

                YouTubePlayerView(videoID: video.videoID)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .accessibilityLabel("YouTube video player")
                    .accessibilityHint("Plays the video on this page.")

                Button {
                    Task { await playStream() }
                } label: {
                    Label(isResolvingStream ? "Resolving Stream" : "Play Stream", systemImage: "play.rectangle")
                }
                .disabled(isResolvingStream)
                .accessibilityHint("Plays this video's stream in the app player, skipping sponsor segments.")

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
                            transcript = await YouTubeService.transcriptParagraphs(videoID: video.videoID)
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

                if let url = URL(string: video.watchURL) {
                    Link("Open in YouTube", destination: url)
                        .accessibilityHint("Opens this video in your browser.")
                }
            }
            .padding()
            // Fluid width: fills the window at every screen size.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Video")
    }

    private func playStream() async {
        isResolvingStream = true
        guard let url = await YouTubeStreamResolver.playbackURL(videoID: video.videoID) else {
            isResolvingStream = false
            Announcer.announce("Could not resolve a playable stream for this video.")
            return
        }
        let article = Article(id: "youtube:\(video.videoID)", title: video.title,
                              url: video.watchURL, content: "", mediaURL: url.absoluteString)
        player.play(article: article)
        isResolvingStream = false
        if player.skipSponsorSegments {
            player.sponsorSegments = await SponsorBlockService.segments(videoID: video.videoID)
        }
    }
}
