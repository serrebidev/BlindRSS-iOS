// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation

/// One parsed entry, format-neutral. Mirrors the fields the desktop local
/// provider (providers/local.py) extracts from RSS, Atom, and JSON Feed.
struct ParsedChapter: Equatable {
    var start: Double
    var title: String
    var href: String?
}

struct ParsedEntry: Equatable {
    var guid: String
    var title: String
    var link: String
    var contentHTML: String
    var summaryHTML: String?
    var author: String
    var dateRaw: String
    var date: Date?
    var mediaURL: String?
    var mediaType: String?
    /// Podcasting 2.0 <podcast:chapters url="..."> document for this episode.
    var chapterURL: String?
    /// Inline chapters (psc:chapter / podcast:chapter start/title).
    var inlineChapters: [ParsedChapter] = []
}

struct ParsedFeed: Equatable {
    var title: String
    var siteLink: String?
    var language: String?
    var entries: [ParsedEntry]
}

enum FeedParserError: Error {
    case notAFeed
}

/// Parses RSS 2.0, Atom, and JSON Feed documents into ParsedFeed values.
/// Port of the format handling in desktop providers/local.py
/// (_parse_feed_document, _parse_json_feed, and the XML entry helpers).
enum FeedParser {
    static func parse(data: Data, sourceURL: URL) throws -> ParsedFeed {
        if let feed = try? parseJSONFeed(data: data) { return feed }
        let delegate = FeedXMLDelegate(sourceURL: sourceURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse(), let feed = delegate.result else {
            throw FeedParserError.notAFeed
        }
        return feed
    }

    // MARK: JSON Feed (https://jsonfeed.org)

    private static func parseJSONFeed(data: Data) throws -> ParsedFeed {
        struct JSONFeed: Decodable {
            struct Item: Decodable {
                struct Attachment: Decodable { let url: String; let mime_type: String? }
                let id: String
                let url: String?
                let external_url: String?
                let title: String?
                let content_html: String?
                let content_text: String?
                let summary: String?
                let date_published: String?
                let authors: [Author]?
                let attachments: [Attachment]?
                struct Author: Decodable { let name: String? }
            }
            let title: String
            let home_page_url: String?
            let language: String?
            let items: [Item]
        }
        let decoded = try JSONDecoder().decode(JSONFeed.self, from: data)
        let entries = decoded.items.map { item in
            ParsedEntry(
                guid: item.id,
                title: item.title ?? "Untitled",
                link: item.external_url ?? item.url ?? "",
                contentHTML: item.content_html ?? item.content_text ?? "",
                summaryHTML: item.summary,
                author: item.authors?.compactMap(\.name).joined(separator: ", ") ?? "",
                dateRaw: item.date_published ?? "",
                date: ISO8601DateFormatter().date(from: item.date_published ?? ""),
                mediaURL: item.attachments?.first?.url,
                mediaType: item.attachments?.first?.mime_type
            )
        }
        return ParsedFeed(title: decoded.title, siteLink: decoded.home_page_url,
                          language: decoded.language, entries: entries)
    }

    /// Parses "90", "1:30", or "1:02:30" chapter timestamps to seconds.
    static func parseTimestamp(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let plain = Double(trimmed) { return plain }
        let bits = trimmed.split(separator: ":").compactMap { Double($0) }
        guard bits.count == 2 || bits.count == 3 else { return nil }
        return bits.reduce(0) { $0 * 60 + $1 }
    }

    /// RFC 822 / RFC 3339 date parsing, matching desktop parse_datetime_utc.
    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz",
                       "dd MMM yyyy HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss"] {
            rfc.dateFormat = format
            if let date = rfc.date(from: trimmed) { return date }
        }
        return nil
    }
}

// MARK: - XML parsing (RSS 2.0 channel/item, Atom feed/entry)

private final class FeedXMLDelegate: NSObject, XMLParserDelegate {
    private let sourceURL: URL
    private(set) var result: ParsedFeed?

    private var path: [String] = []
    private var text = ""

    private var feedTitle = ""
    private var feedLink: String?
    private var feedLanguage: String?

    private var inEntry = false
    private var entry = ParsedEntry(guid: "", title: "", link: "", contentHTML: "", author: "", dateRaw: "")
    private var entryLinkRel: String?
    private var entryLinkType: String?
    private var entryLinkHref: String?

    init(sourceURL: URL) { self.sourceURL = sourceURL }

    private func local(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = local(elementName)
        path.append(name)
        text = ""
        if name == "item" || name == "entry" {
            inEntry = true
            entry = ParsedEntry(guid: "", title: "", link: "", contentHTML: "", author: "", dateRaw: "")
        }
        if inEntry && name == "link" {
            entryLinkRel = attributeDict["rel"]
            entryLinkType = attributeDict["type"]
            entryLinkHref = attributeDict["href"]
        }
        if inEntry && name == "chapters" {
            entry.chapterURL = attributeDict["url"]
        }
        if inEntry && name == "chapter" {
            let startRaw = attributeDict["start"] ?? attributeDict["starttime"] ?? attributeDict["start_time"] ?? "0"
            if let start = FeedParser.parseTimestamp(startRaw) {
                entry.inlineChapters.append(ParsedChapter(
                    start: start,
                    title: attributeDict["title"] ?? "Chapter",
                    href: attributeDict["href"] ?? attributeDict["url"] ?? attributeDict["link"]))
            }
        }
        if inEntry && (name == "enclosure" || name == "link") {
            // RSS enclosure or Atom enclosure link: podcast/video media.
            let isEnclosure = name == "enclosure" || entryLinkRel == "enclosure"
            if isEnclosure {
                entry.mediaURL = attributeDict["url"] ?? entryLinkHref
                entry.mediaType = attributeDict["type"] ?? entryLinkType
            }
        }
        if !inEntry && name == "link", feedLink == nil {
            feedLink = attributeDict["href"]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let name = local(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { path.removeLast(); text = "" }

        if name == "item" || name == "entry" {
            if entry.guid.isEmpty { entry.guid = entry.link.isEmpty ? entry.title : entry.link }
            entry.date = FeedParser.parseDate(entry.dateRaw)
            entries.append(entry)
            inEntry = false
            return
        }
        if inEntry {
            switch name {
            case "title": entry.title = value
            case "link":
                if let href = entryLinkHref, entryLinkRel == nil || entryLinkRel == "alternate" {
                    entry.link = href
                } else if !value.isEmpty { entry.link = value }
            case "guid", "id": entry.guid = value
            case "encoded", "content": if !value.isEmpty { entry.contentHTML = value }
            case "description", "summary": entry.summaryHTML = value
            case "author", "name": if entry.author.isEmpty { entry.author = value }
            case "pubDate", "published", "updated", "date": if entry.dateRaw.isEmpty { entry.dateRaw = value }
            default: break
            }
        } else {
            switch name {
            case "title": if feedTitle.isEmpty { feedTitle = value }
            case "link": if feedLink == nil, !value.isEmpty { feedLink = value }
            case "language": feedLanguage = value
            default: break
            }
        }
    }

    private var entries: [ParsedEntry] = []

    func parserDidEndDocument(_ parser: XMLParser) {
        guard !feedTitle.isEmpty || !entries.isEmpty else { return }
        result = ParsedFeed(title: feedTitle.isEmpty ? (sourceURL.host ?? "Feed") : feedTitle,
                            siteLink: feedLink, language: feedLanguage, entries: entries)
    }
}
