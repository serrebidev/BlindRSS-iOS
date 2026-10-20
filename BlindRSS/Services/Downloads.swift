// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation

/// Media downloads (desktop Downloading Media). Files land in
/// Documents/Downloads so downloaded episodes play offline and can use
/// the equalizer engine player.
enum DownloadService {
    static var downloadsDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func localURL(for article: Article) -> URL? {
        guard let name = article.localFileName else { return nil }
        let url = downloadsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func download(article: Article) async throws {
        guard let media = article.mediaURL, let url = URL(string: media) else { return }
        let (temp, _) = try await URLSession.shared.download(from: url)
        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        let safeID = article.id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let name = "\(safeID).\(ext)"
        let dest = downloadsDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: temp, to: dest)
        article.localFileName = name
        Announcer.announce("Downloaded \(article.title).")
    }

    static func removeDownload(article: Article) {
        if let name = article.localFileName {
            try? FileManager.default.removeItem(at: downloadsDirectory.appendingPathComponent(name))
        }
        article.localFileName = nil
        Announcer.announce("Download removed.")
    }
}

/// Full-text recovery (desktop Full-Text Article Recovery) and feed
/// discovery (desktop Detecting Feeds on a Page).
enum FullTextService {
    /// Fetches the article page and returns cleaned readable text, keeping
    /// whichever is longer: the feed content or the recovered page text.
    static func fetchFullText(for article: Article) async -> String? {
        guard let url = URL(string: article.url) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("BlindRSS-iOS/0.1", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }
        let pageText = HTMLText.plainText(from: html)
        let feedText = HTMLText.plainText(from: article.content)
        return pageText.count > feedText.count ? pageText : nil
    }

    /// Finds feed URLs advertised by a web page via link rel=alternate.
    static func discoverFeeds(pageURL: URL) async -> [(title: String, url: URL)] {
        guard let (data, _) = try? await URLSession.shared.data(from: pageURL),
              let html = String(data: data, encoding: .utf8) else { return [] }
        var results: [(String, URL)] = []
        let lower = html.lowercased()
        var searchRange = lower.startIndex..<lower.endIndex
        while let linkStart = lower.range(of: "<link", range: searchRange) {
            guard let linkEnd = lower.range(of: ">", range: linkStart.upperBound..<lower.endIndex) else { break }
            let tag = String(html[linkStart.lowerBound..<linkEnd.upperBound])
            searchRange = linkEnd.upperBound..<lower.endIndex
            let tagLower = tag.lowercased()
            guard tagLower.contains("alternate"),
                  tagLower.contains("rss") || tagLower.contains("atom") || tagLower.contains("feed") else { continue }
            if let href = attribute("href", in: tag),
               let url = URL(string: href, relativeTo: pageURL) {
                results.append((attribute("title", in: tag) ?? url.absoluteString, url.absoluteURL))
            }
        }
        // Common well-known feed paths as a fallback.
        if results.isEmpty {
            for path in ["/feed", "/rss", "/feed.xml", "/rss.xml", "/atom.xml"] {
                if let url = URL(string: pageURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) {
                    results.append((path, url))
                }
            }
        }
        return results
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let range = tag.range(of: "\(name)=", options: .caseInsensitive) else { return nil }
        let rest = tag[range.upperBound...]
        if let first = rest.first, first == "\"" || first == "'" {
            let afterQuote = rest.dropFirst()
            return afterQuote.split(separator: first).first.map(String.init)
        }
        return rest.split(separator: " ").first.map(String.init)
    }
}
