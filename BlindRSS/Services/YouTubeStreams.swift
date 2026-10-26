// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation
import YouTubeKit

/// Native YouTube stream resolution (research round 0.1.13). The audit
/// said "yt-dlp has no iOS equivalent"; the research found YouTubeKit
/// (alexeichhorn/YouTubeKit, MIT, actively maintained): a pure-Swift
/// extractor that fetches the watch page, queries Innertube clients,
/// and decrypts signatures locally with JavaScriptCore — the same work
/// yt-dlp does, as a Swift package. Resolved URLs feed AVPlayer, so
/// YouTube articles gain stream playback in the app's own player
/// (resume, speed, chapters, SponsorBlock skipping) and stream
/// downloads, alongside the embedded web player.
enum YouTubeStreamResolver {
    /// Best playable stream URL for a video: a combined audio+video
    /// stream AVPlayer can decode natively when one exists, else the
    /// best audio-only stream (BlindRSS is a listening-first app).
    static func playbackURL(videoID: String) async -> URL? {
        let video = YouTube(videoID: videoID)
        guard let streams = try? await video.streams, !streams.isEmpty else { return nil }
        if let combined = streams.filterVideoAndAudio()
            .filter({ $0.isNativelyPlayable })
            .highestResolutionStream() {
            return combined.url
        }
        if let audio = streams.filterAudioOnly().highestAudioBitrateStream() {
            return audio.url
        }
        return streams.first?.url
    }
}
