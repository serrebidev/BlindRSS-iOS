// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation

/// SponsorBlock (https://sponsor.ajay.app): crowdsourced segment times
/// for YouTube videos, from the documented public API
/// (https://wiki.sponsor.ajay.app/index.php?title=API_Docs). The desktop
/// gets segments through yt-dlp; on iOS the API is queried directly and
/// the player skips the segments during stream playback. Research round
/// 0.1.13: no Swift client library exists, but the API is a single GET
/// returning JSON, so a thin client in the app's service style suffices.
enum SponsorBlockService {
    struct Segment: Equatable, Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var category: String
    }

    /// Categories the desktop skips by default.
    static let defaultCategories = ["sponsor", "intro", "outro", "selfpromo",
                                    "interaction", "music_offtopic", "preview", "filler"]

    /// Parses the /api/skipSegments response: an array of objects with a
    /// two-element "segment" array of seconds. The API answers 404 with
    /// the plain text "Not Found" when a video has no segments, which
    /// parses to an empty list here.
    static func parseSegments(_ data: Data) -> [Segment] {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            guard let times = item["segment"] as? [Any], times.count == 2,
                  let start = (times[0] as? NSNumber)?.doubleValue,
                  let end = (times[1] as? NSNumber)?.doubleValue, end > start else { return nil }
            return Segment(start: start, end: end, category: item["category"] as? String ?? "sponsor")
        }.sorted(by: { $0.start < $1.start })
    }

    /// The segment covering a playback position, if any. Positions in
    /// the last quarter second of a segment do not count, so a skip
    /// never retriggers on its own landing point.
    static func segment(at time: TimeInterval, in segments: [Segment]) -> Segment? {
        segments.first { time >= $0.start && time < $0.end - 0.25 }
    }

    static func segments(videoID: String) async -> [Segment] {
        let categories = defaultCategories.map { "\"\($0)\"" }.joined(separator: ",")
        let encoded = "[\(categories)]".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://sponsor.ajay.app/api/skipSegments?videoID=\(videoID)&categories=\(encoded)"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return parseSegments(data)
    }
}
