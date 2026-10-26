// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import AVFoundation
import Foundation
import Observation
import Speech

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

    /// Downloads a resolved stream URL (a YouTubeKit-resolved YouTube
    /// stream) against an existing article, so the download attaches
    /// to the article the user is reading.
    static func downloadStream(url: URL, for article: Article) async throws {
        let (temp, _) = try await URLSession.shared.download(from: url)
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
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
    /// The recovered article, and the page's video when the page is a
    /// news video (its soundtrack, transcribed, is then the text).
    struct FullText {
        var blocks: [ReaderBlock]
        var videoURL: URL?
    }

    /// `transcribeVideo` is for the reader and Apple Intelligence asking
    /// directly: a video page with only a caption of text yields the
    /// caption plus an on-device transcript of the video (iOS 26 speech
    /// recognition), and the video itself so it can be played. List
    /// prefetching leaves it off and never downloads video.
    static func fetchFullText(articleID: String, url: String, feedText: String,
                              transcribeVideo: Bool = false) async throws -> FullText {
        var best: [ReaderBlock] = []
        var page: String?
        if articleID.hasPrefix("miniflux:"), let config = HostedConfig.load(), config.kind == .miniflux,
           let html = try? await minifluxContent(entryID: String(articleID.dropFirst("miniflux:".count)), config: config) {
            best = HTMLText.articleBlocks(fromPage: html)
        }
        // A thin server extraction is often only part of the article (the
        // site truncated what its fetcher saw), so anything short still
        // earns a direct fetch and the longer result wins.
        var directError: Error?
        if textLength(best) < 1000 {
            if let pageURL = URL(string: url), pageURL.scheme?.hasPrefix("http") == true {
                do {
                    let html = try await fetchPage(pageURL)
                    page = html
                    let direct = HTMLText.articleBlocks(fromPage: html)
                    if textLength(direct) > textLength(best) { best = direct }
                } catch { directError = error }
            } else if best.isEmpty {
                throw Failure.noLink
            }
        }
        let length = textLength(best)
        // A video page (Reuters wire video on The Globe and Mail, for
        // one) has nothing to extract but its caption, which the feed
        // already sent; the words are in the video.
        if transcribeVideo, length < 200 || length <= feedText.count,
           let page, let videoURL = HTMLText.pageVideoURL(fromPage: page) {
            var blocks = length > feedText.count || feedText.isEmpty ? best : HTMLText.blocks(fromPlainText: feedText)
            if let transcript = await VideoTranscriber.transcript(of: videoURL, language: HTMLText.pageLanguage(fromPage: page)),
               !transcript.isEmpty {
                blocks.append(ReaderBlock(isHeading: true, text: "Video transcript"))
                blocks += transcript
            } else {
                blocks.append(ReaderBlock(isHeading: false, text:
                    "This article is a video with no written text. Use Play to listen to it. A transcript needs iOS 26 or later and speech recognition for the video's language."))
            }
            return FullText(blocks: blocks, videoURL: videoURL)
        }
        guard length >= 200 else { throw (directError as? Failure) ?? Failure.noArticle }
        guard length > feedText.count else { throw Failure.notLonger }
        return FullText(blocks: best)
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

/// On-device speech-to-text of a video's soundtrack (iOS 26
/// SpeechAnalyzer). The video is downloaded to a temporary file, its
/// audio exported to M4A, and transcribed in the page's language, or
/// the device language when that is not supported. Nothing leaves the
/// device but the video download.
enum VideoTranscriber {
    static func transcript(of videoURL: URL, language: String?) async -> [ReaderBlock]? {
        guard #available(iOS 26, *) else { return nil }
        let temporary = FileManager.default.temporaryDirectory
        let video = temporary.appendingPathComponent(UUID().uuidString + ".mp4")
        let audio = temporary.appendingPathComponent(UUID().uuidString + ".m4a")
        defer {
            try? FileManager.default.removeItem(at: video)
            try? FileManager.default.removeItem(at: audio)
        }
        do {
            let locale: Locale
            if let language, let match = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) {
                locale = match
            } else if let match = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) {
                locale = match
            } else {
                return nil
            }
            var request = URLRequest(url: videoURL)
            request.timeoutInterval = 60
            let (downloaded, response) = try await URLSession.shared.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            try FileManager.default.moveItem(at: downloaded, to: video)
            guard let export = AVAssetExportSession(asset: AVURLAsset(url: video), presetName: AVAssetExportPresetAppleM4A) else {
                return nil
            }
            try await export.export(to: audio, as: .m4a)

            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await install.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            async let phrases = transcriber.results.reduce(into: [String]()) { list, result in
                if result.isFinal { list.append(String(result.text.characters)) }
            }
            // Finishing (or cancelling) the analyzer ends the results
            // sequence, so the reduce above always returns.
            do {
                if let end = try await analyzer.analyzeSequence(from: AVAudioFile(forReading: audio)) {
                    try await analyzer.finalizeAndFinish(through: end)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
            } catch {
                await analyzer.cancelAndFinishNow()
                throw error
            }
            return HTMLText.paragraphs(fromPhrases: try await phrases)
        } catch {
            return nil
        }
    }
}

private struct MinifluxFetchedContent: Decodable {
    let content: String
}

/// Session cache of recovered full text, shared by the article list
/// (which reads the full text at the end of each row's announcement)
/// and the reader (which then opens with the text already loaded).
/// Stores reader blocks; the spoken form joins them in order.
@MainActor
@Observable
final class FullTextCache {
    static let shared = FullTextCache()

    private(set) var blocksByID: [String: [ReaderBlock]] = [:]
    private var order: [String] = []
    private var inFlight: Set<String> = []
    private let limit = 200

    func blocks(for articleID: String) -> [ReaderBlock]? { blocksByID[articleID] }

    func spokenText(for articleID: String) -> String? {
        blocksByID[articleID].map { $0.map(\.text).joined(separator: "\n") }
    }

    func store(_ blocks: [ReaderBlock], for articleID: String) {
        if blocksByID[articleID] == nil { order.append(articleID) }
        blocksByID[articleID] = blocks
        while order.count > limit { blocksByID.removeValue(forKey: order.removeFirst()) }
    }

    /// Fetches in the background when needed. When the feed already
    /// carries the full article (the fetch reports notLonger), the feed
    /// text itself is cached as the full text, so the list announcement
    /// and the reader both use the longest version available. Failures
    /// stay silent here; the reader's Fetch Full Text button reports
    /// them when the user asks directly.
    func prefetch(articleID: String, url: String, feedText: String) {
        guard blocksByID[articleID] == nil, !inFlight.contains(articleID) else { return }
        inFlight.insert(articleID)
        Task {
            defer { inFlight.remove(articleID) }
            do {
                store(try await FullTextService.fetchFullText(articleID: articleID, url: url, feedText: feedText).blocks,
                      for: articleID)
            } catch FullTextService.Failure.notLonger {
                store(HTMLText.blocks(fromPlainText: feedText), for: articleID)
            } catch {}
        }
    }
}
