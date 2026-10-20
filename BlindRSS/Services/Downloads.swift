// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation

/// Media downloads (desktop Downloading Media). Files land in
/// Documents/Downloads so downloaded episodes play offline and can use
/// the equalizer engine player.
enum DownloadService {
    /// Resolved and created once, not on every lookup.
    static let downloadsDirectory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

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
    enum Failure: LocalizedError {
        case noLink
        case httpStatus(Int)
        case noArticle
        case notLonger

        var errorDescription: String? {
            switch self {
            case .noLink: return "This article has no web page to fetch."
            case .httpStatus(let code): return "The site refused the request, HTTP \(code)."
            case .noArticle: return "Could not find the article text on its web page."
            case .notLonger: return "The feed already has the full article."
            }
        }
    }

    /// Recovers the complete article as reader paragraphs. Miniflux articles
    /// ask the server first, whose extractor also handles sites that block
    /// apps (Android does the same); otherwise the page is fetched as Safari
    /// would and the article is pulled out of it. Takes plain values, not
    /// the Article: this runs off the main actor, where SwiftData models
    /// must not be read.
    static func fetchFullText(articleID: String, url: String, feedText: String) async throws -> [ReaderBlock] {
        var blocks: [ReaderBlock] = []
        if articleID.hasPrefix("miniflux:"), let config = HostedConfig.load(), config.kind == .miniflux,
           let html = try? await minifluxContent(entryID: String(articleID.dropFirst("miniflux:".count)), config: config) {
            blocks = HTMLText.articleBlocks(fromPage: html)
        }
        if textLength(blocks) < 200 {
            guard let pageURL = URL(string: url), pageURL.scheme?.hasPrefix("http") == true else { throw Failure.noLink }
            blocks = HTMLText.articleBlocks(fromPage: try await fetchPage(pageURL))
        }
        let length = textLength(blocks)
        guard length >= 200 else { throw Failure.noArticle }
        guard length > feedText.count else { throw Failure.notLonger }
        return blocks
    }

    private static func textLength(_ blocks: [ReaderBlock]) -> Int {
        blocks.reduce(0) { $0 + $1.text.count }
    }

    /// Miniflux "fetch original content" (GET /v1/entries/{id}/fetch-content).
    private static func minifluxContent(entryID: String, config: HostedConfig) async throws -> String {
        let base = HostedSync.normalizedBaseURL(config.baseURL)
        guard let url = URL(string: "\(base)/v1/entries/\(entryID)/fetch-content") else { throw Failure.noLink }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(config.token, forHTTPHeaderField: "X-Auth-Token")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(MinifluxFetchedContent.self, from: data).content
    }

    private static func fetchPage(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // The old "BlindRSS-iOS/0.1" agent got 403 and bot-check pages from
        // many news sites, and their text was then shown as the article.
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.httpStatus(http.statusCode)
        }
        return decodePage(data, charset: response.textEncodingName)
    }

    /// The declared charset, then UTF-8, then Windows Latin. UTF-8 only
    /// used to make every non-UTF-8 page fail.
    private static func decodePage(_ data: Data, charset: String?) -> String {
        if let charset {
            let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if encoding != kCFStringEncodingInvalidId,
               let text = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))) {
                return text
            }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
    }

    /// Finds feed URLs advertised by a web page via link rel=alternate.
    static func discoverFeeds(pageURL: URL) async -> [(title: String, url: URL)] {
        guard let (data, response) = try? await URLSession.shared.data(from: pageURL) else { return [] }
        let html = decodePage(data, charset: response.textEncodingName)
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

private struct MinifluxFetchedContent: Decodable {
    let content: String
}
