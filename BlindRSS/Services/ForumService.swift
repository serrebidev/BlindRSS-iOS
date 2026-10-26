// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation

/// Forum-thread reading (research round 0.1.13). Lemmy's public REST
/// API (https://join-lemmy.org/api/) serves posts and comments with no
/// login, no API key, and no OAuth for public communities, so a Lemmy
/// post article gains its comment thread in the reader, parsed with the
/// same Data -> model pattern as the rest of the app. Reddit is not
/// included: Reddit shut down unauthenticated .json access in 2026
/// (403 responses), and its Data API now requires a registered,
/// approved app — see AUDIT.md. Groups.io threads ride the group's
/// native RSS feed, which the app already subscribes to.
enum ForumService {
    struct ThreadLine: Equatable, Sendable {
        var author: String
        var text: String
        /// 0 for top-level comments; grows with nesting.
        var depth: Int
    }

    struct Thread: Equatable, Sendable {
        var title: String
        var body: String
        var comments: [ThreadLine]
    }

    /// A Lemmy post URL is /post/<id> on any Lemmy instance. Returns the
    /// instance base URL and the post id.
    static func lemmyPost(from urlString: String) -> (base: String, id: String)? {
        guard let url = URL(string: urlString), let host = url.host,
              url.scheme == "http" || url.scheme == "https" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "post", !parts[1].isEmpty,
              parts[1].allSatisfy(\.isNumber) else { return nil }
        return ("\(url.scheme ?? "https")://\(host)", parts[1])
    }

    /// Depth of a Lemmy comment from its path ("0.123.456"): the first
    /// component is the root marker, so a top-level comment has depth 0.
    static func depth(ofPath path: String) -> Int {
        max(0, path.split(separator: ".").count - 2)
    }

    /// Parses the /api/v3/post response into the post's title and body.
    static func parsePost(_ data: Data) -> (title: String, body: String)? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let view = root["post_view"] as? [String: Any],
              let post = view["post"] as? [String: Any] else { return nil }
        let title = post["name"] as? String ?? ""
        var body = post["body"] as? String ?? ""
        if body.isEmpty, let link = post["url"] as? String, !link.isEmpty {
            body = link
        }
        return (title, body)
    }

    /// Parses the /api/v3/comment/list response into indented thread
    /// lines. Removed and deleted comments keep a marker line so the
    /// shape of the thread stays understandable.
    static func parseComments(_ data: Data) -> [ThreadLine] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let comments = root["comments"] as? [[String: Any]] else { return [] }
        return comments.compactMap { item in
            guard let comment = item["comment"] as? [String: Any] else { return nil }
            let creator = item["creator"] as? [String: Any]
            let author = creator?["name"] as? String ?? "unknown"
            var text = comment["content"] as? String ?? ""
            if (comment["deleted"] as? Bool) == true { text = "[deleted]" }
            if (comment["removed"] as? Bool) == true { text = "[removed]" }
            guard !text.isEmpty else { return nil }
            return ThreadLine(author: author, text: text,
                              depth: depth(ofPath: comment["path"] as? String ?? "0"))
        }
    }

    /// Fetches a Lemmy post and its comments (top-scored first, up to
    /// eight levels deep — the API's documented read endpoints).
    static func thread(base: String, postID: String) async -> Thread? {
        guard let postURL = URL(string: "\(base)/api/v3/post?id=\(postID)"),
              let commentsURL = URL(string: "\(base)/api/v3/comment/list?post_id=\(postID)&max_depth=8&sort=Top&limit=50") else { return nil }
        async let postData = data(from: postURL)
        async let commentsData = data(from: commentsURL)
        guard let post = await postData.flatMap(parsePost) else { return nil }
        let comments = await commentsData.map(parseComments) ?? []
        return Thread(title: post.title, body: post.body, comments: comments)
    }

    /// Reader lines: the post body first (when the feed itself did not
    /// carry it), then each comment, indented by depth so VoiceOver
    /// users hear the thread structure in the spoken prefix.
    static func lines(for thread: Thread) -> [String] {
        var lines: [String] = []
        let body = thread.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { lines.append(body) }
        for comment in thread.comments {
            let indent = comment.depth > 0 ? String(repeating: "  ", count: comment.depth) : ""
            let level = comment.depth > 0 ? "Reply, level \(comment.depth), " : "Comment, "
            lines.append("\(indent)\(level)\(comment.author): \(comment.text)")
        }
        return lines
    }

    private static func data(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("BlindRSS-iOS/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
