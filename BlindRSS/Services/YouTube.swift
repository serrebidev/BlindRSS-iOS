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
    // MARK: Transcript (desktop YouTube Transcript section)

    /// Fetches the video's captions through the same keyless Innertube
    /// route the desktop uses (services/youtube_service.py): player
    /// response, caption track, json3 timed text, grouped into
    /// paragraphs. Empty when the video has no captions.
    static func transcriptParagraphs(videoID: String) async -> [String] {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "videoId": videoID,
            "context": ["client": ["clientName": "WEB", "clientVersion": "2.20251010.01.00", "hl": "en"]],
            "contentCheckOk": true, "racyCheckOk": true,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let trackURL = captionTrackURL(fromPlayerResponse: data),
              let (captionData, captionResponse) = try? await URLSession.shared.data(from: trackURL),
              (captionResponse as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return parseTranscriptJSON3(captionData)
    }

    /// Picks the caption track from a player response: a human track
    /// when one exists, the automatic (asr) track otherwise, matching
    /// the desktop's preference order. Appends fmt=json3.
    static func captionTrackURL(fromPlayerResponse data: Data) -> URL? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let captions = root["captions"] as? [String: Any],
              let renderer = captions["playerCaptionsTracklistRenderer"] as? [String: Any],
              let tracks = renderer["captionTracks"] as? [[String: Any]] else { return nil }
        var automatic: String?
        for track in tracks {
            guard let base = track["baseUrl"] as? String, !base.isEmpty else { continue }
            if (track["kind"] as? String) == "asr" {
                if automatic == nil { automatic = base }
            } else {
                return URL(string: base + "&fmt=json3")
            }
        }
        return automatic.map { URL(string: $0 + "&fmt=json3") } ?? nil
    }

    /// json3 timed text -> readable paragraphs: each event's segments
    /// joined, music markers dropped, events accumulated into a
    /// paragraph until a sentence ends past 200 characters.
    static func parseTranscriptJSON3(_ data: Data) -> [String] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }
        var lines: [String] = []
        for event in events {
            guard let segs = event["segs"] as? [[String: Any]] else { continue }
            let text = segs.compactMap { $0["utf8"] as? String }.joined()
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !(text.hasPrefix("[") && text.hasSuffix("]")) else { continue }
            lines.append(text)
        }
        var paragraphs: [String] = []
        var current = ""
        for line in lines {
            current = current.isEmpty ? line : current + " " + line
            if current.count >= 200, let last = current.last, ".!?".contains(last) {
                paragraphs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs
    }

    // MARK: Video Search (desktop Video Search)

    struct VideoResult: Identifiable, Equatable, Sendable {
        var videoID: String
        var title: String
        var channel: String
        var durationText: String
        var publishedText: String
        var id: String { videoID }
        var watchURL: String { "https://www.youtube.com/watch?v=\(videoID)" }
    }

    /// Parses an Innertube search or browse response into video
    /// results. Search answers with videoRenderer items; account
    /// browse feeds (Subscriptions, Home) answer with TV grid items
    /// (gridVideoRenderer) and rich items wrapping a videoRenderer.
    /// Shelves and ads carry neither and are skipped.
    static func parseSearchResults(_ data: Data) -> [VideoResult] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        var renderers: [[String: Any]] = []
        func collect(_ value: Any?) {
            guard let dict = value as? [String: Any] else {
                if let array = value as? [Any] { array.forEach(collect) }
                return
            }
            if let renderer = dict["videoRenderer"] as? [String: Any] { renderers.append(renderer) }
            if let grid = dict["gridVideoRenderer"] as? [String: Any] { renderers.append(grid) }
            for child in dict.values { collect(child) }
        }
        collect(root["contents"])
        collect(root["onResponseReceivedActions"])
        var seen = Set<String>()
        return renderers.compactMap { renderer in
            guard let id = renderer["videoId"] as? String, !id.isEmpty, seen.insert(id).inserted else { return nil }
            func runsText(_ key: String) -> String {
                let container = renderer[key] as? [String: Any]
                let runs = container?["runs"] as? [[String: Any]] ?? []
                let joined = runs.compactMap { $0["text"] as? String }.joined()
                if !joined.isEmpty { return joined }
                return (container?["simpleText"] as? String) ?? ""
            }
            // Grid items carry the duration in a thumbnail overlay
            // instead of a lengthText field.
            var duration = runsText("lengthText")
            if duration.isEmpty,
               let overlays = renderer["thumbnailOverlays"] as? [[String: Any]] {
                for overlay in overlays {
                    if let status = overlay["thumbnailOverlayTimeStatusRenderer"] as? [String: Any],
                       let text = status["text"] as? [String: Any],
                       let simple = text["simpleText"] as? String { duration = simple; break }
                }
            }
            let channel = runsText("longBylineText").isEmpty ? runsText("shortBylineText") : runsText("longBylineText")
            return VideoResult(videoID: id,
                               title: runsText("title").isEmpty ? id : runsText("title"),
                               channel: channel,
                               durationText: duration,
                               publishedText: runsText("publishedTimeText"))
        }
    }

    /// Keyless video search through the same public Innertube client
    /// the transcript fetch uses (the desktop searches with yt-dlp;
    /// Innertube's search endpoint is the iOS route, research 0.1.13).
    static func searchVideos(term: String) async -> [VideoResult] {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/search?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "query": term,
            "context": ["client": ["clientName": "WEB", "clientVersion": "2.20251010.01.00", "hl": "en"]],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return parseSearchResults(data)
    }

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
