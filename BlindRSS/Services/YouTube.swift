// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI
import WebKit

/// YouTube handling (desktop YouTube Videos). Channel and playlist RSS
/// feeds already parse as normal feeds. A video article plays in the
/// embedded player (yt-dlp has no iOS equivalent), and chapters are
/// parsed from timestamp lines in the description.
enum YouTubeService {
    static func videoID(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        if host.contains("youtu.be") { return url.lastPathComponent }
        if host.contains("youtube.com") {
            if url.pathComponents.contains("shorts"), let last = url.pathComponents.last { return last }
            if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               let v = query.first(where: { $0.name == "v" })?.value { return v }
        }
        return nil
    }

    static func isYouTube(_ urlString: String) -> Bool { videoID(from: urlString) != nil }

    /// Parses "0:00 Intro" style lines into chapters.
    static func chapters(fromDescription text: String) -> [Chapter] {
        var result: [Chapter] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let seconds = parseTimestamp(String(parts[0])) else { continue }
            result.append(Chapter(id: "yt-\(seconds)-\(result.count)", start: seconds, title: String(parts[1])))
        }
        return result.sorted(by: { $0.start < $1.start })
    }

    private static func parseTimestamp(_ value: String) -> Double? {
        let bits = value.split(separator: ":").compactMap { Double($0) }
        guard bits.count == 2 || bits.count == 3 else { return nil }
        return bits.reduce(0) { $0 * 60 + $1 }
    }
}

/// Embedded YouTube player. Web content is not directly VoiceOver friendly,
/// so the surrounding controls (Play in Player, chapters, description text)
/// remain native and labeled.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.scrollView.isScrollEnabled = false
        if let url = URL(string: "https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1") {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}
}
