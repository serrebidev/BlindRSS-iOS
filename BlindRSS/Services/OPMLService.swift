// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Compression
import Foundation

/// OPML import/export, matching desktop core.utils.parse_opml / write_opml.
/// Format: nested <outline> folders are categories; xmlUrl is the feed.
enum OPMLService {
    struct OPMLFeed: Equatable {
        var title: String
        var xmlURL: String
        var category: String
    }

    static func parse(data: Data) -> [OPMLFeed] {
        let delegate = OPMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.feeds
    }

    static func export(feeds: [Feed]) -> Data {
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                     "<opml version=\"1.0\">", "<head><title>BlindRSS Subscriptions</title></head>", "<body>"]
        for category in Set(feeds.map(\.category)).sorted() {
            let inCategory = feeds.filter { $0.category == category }
            if category == Category.uncategorized {
                for feed in inCategory { lines.append(outline(for: feed, indent: "  ")) }
            } else {
                lines.append("  <outline text=\"\(escape(category))\" title=\"\(escape(category))\">")
                for feed in inCategory { lines.append(outline(for: feed, indent: "    ")) }
                lines.append("  </outline>")
            }
        }
        lines.append("</body>")
        lines.append("</opml>")
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func outline(for feed: Feed, indent: String) -> String {
        "\(indent)<outline type=\"rss\" text=\"\(escape(feed.title))\" title=\"\(escape(feed.title))\" xmlUrl=\"\(escape(feed.url))\"/>"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private final class OPMLDelegate: NSObject, XMLParserDelegate {
    private(set) var feeds: [OPMLService.OPMLFeed] = []
    private var categoryStack: [String] = []
    private var outlineIsFolder: [Bool] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        guard elementName == "outline" else { return }
        let title = attributeDict["title"] ?? attributeDict["text"] ?? ""
        if let xmlURL = attributeDict["xmlUrl"], !xmlURL.isEmpty {
            outlineIsFolder.append(false)
            feeds.append(.init(title: title, xmlURL: xmlURL,
                               category: categoryStack.last ?? Category.uncategorized))
        } else {
            outlineIsFolder.append(true)
            categoryStack.append(title)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard elementName == "outline" else { return }
        if outlineIsFolder.popLast() == true, !categoryStack.isEmpty {
            categoryStack.removeLast()
        }
    }
}

// MARK: - YouTube Takeout import (desktop OPML and YouTube Takeout dialog)

/// Reads a Google Takeout ZIP the way the desktop importer does
/// (core/takeout.py): subscription CSVs, the owner's channel CSV,
/// playlist CSVs, and channel links in watch-history.html all become
/// native YouTube RSS feeds. Pure functions over Data so the whole
/// pipeline is unit-tested without the file system.
enum TakeoutService {
    struct ChannelEntry: Equatable {
        let title: String
        let feedURL: String
    }

    static func feedEntries(fromTakeout data: Data) -> [ChannelEntry] {
        var out: [ChannelEntry] = []
        var seen = Set<String>()
        func add(_ entries: [ChannelEntry]) {
            for entry in entries where seen.insert(entry.feedURL).inserted { out.append(entry) }
        }
        for file in unzip(data) {
            let name = file.name.lowercased()
            guard let text = String(data: file.data, encoding: .utf8) else { continue }
            if name.hasSuffix("subscriptions.csv") || name.hasSuffix("channel.csv") {
                add(csvEntries(text: text, idHeader: "channel id", titleHeader: "channel title",
                               template: "https://www.youtube.com/feeds/videos.xml?channel_id={id}"))
            } else if name.hasSuffix("playlists.csv") {
                add(csvEntries(text: text, idHeader: "playlist id", titleHeader: "playlist title",
                               template: "https://www.youtube.com/feeds/videos.xml?playlist_id={id}"))
            } else if name.hasSuffix("watch-history.html") {
                add(historyEntries(html: text))
            }
        }
        return out
    }

    static func csvEntries(text: String, idHeader: String, titleHeader: String, template: String) -> [ChannelEntry] {
        let rows = parseCSV(text)
        guard let header = rows.first else { return [] }
        let lowered = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let idIndex = lowered.firstIndex(where: { $0.contains(idHeader) }) else { return [] }
        let titleIndex = lowered.firstIndex(where: { $0.contains(titleHeader) })
        return rows.dropFirst().compactMap { row in
            guard row.count > idIndex else { return nil }
            let id = row[idIndex].trimmingCharacters(in: .whitespaces)
            guard id.count >= 2 else { return nil }
            let title = titleIndex.flatMap { row.count > $0 ? row[$0].trimmingCharacters(in: .whitespaces) : nil } ?? ""
            return ChannelEntry(title: title.isEmpty ? id : title,
                                feedURL: template.replacingOccurrences(of: "{id}", with: id))
        }
    }

    static func historyEntries(html: String) -> [ChannelEntry] {
        var entries: [ChannelEntry] = []
        var seen = Set<String>()
        var cursor = html.startIndex
        while let range = html.range(of: "youtube.com/channel/", range: cursor..<html.endIndex) {
            let id = html[range.upperBound...].prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
            if id.hasPrefix("UC"), seen.insert(String(id)).inserted {
                entries.append(ChannelEntry(title: "YouTube channel",
                                            feedURL: "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)"))
            }
            cursor = range.upperBound
        }
        return entries
    }

    /// Minimal quoted-CSV parser (commas, quotes, "" escapes, CRLF).
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        func endField() { row.append(field); field = "" }
        func endRow() { endField(); rows.append(row); row = [] }
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                endField()
            } else if c == "\n" {
                endRow()
            } else if c == "\r\n" {
                // CRLF is a single Character (grapheme cluster) in Swift,
                // so it never matches the "\n" or "\r" cases above.
                endRow()
            } else if c == "\r" {
                if i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                endRow()
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows.filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    // MARK: Minimal ZIP reader (stored and deflated entries)

    struct ZipFile {
        let name: String
        let data: Data
    }

    static func unzip(_ data: Data) -> [ZipFile] {
        guard data.count >= 22 else { return [] }
        let bytes = [UInt8](data)
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        // Locate the End Of Central Directory record by scanning back.
        var eocd: Int?
        let floor = max(0, bytes.count - 22 - 65_536)
        var i = bytes.count - 22
        while i >= floor {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard let eocdOffset = eocd, bytes.count >= eocdOffset + 22 else { return [] }
        let count = u16(eocdOffset + 10)
        var cursor = u32(eocdOffset + 16)
        var files: [ZipFile] = []
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count,
                  bytes[cursor] == 0x50, bytes[cursor + 1] == 0x4B,
                  bytes[cursor + 2] == 0x01, bytes[cursor + 3] == 0x02 else { break }
            let method = u16(cursor + 10)
            let compressedSize = u32(cursor + 20)
            let nameLength = u16(cursor + 28)
            let extraLength = u16(cursor + 30)
            let commentLength = u16(cursor + 32)
            let localOffset = u32(cursor + 42)
            let nameStart = cursor + 46
            guard nameStart + nameLength <= bytes.count else { break }
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            cursor = nameStart + nameLength + extraLength + commentLength
            // Find the payload through the local header.
            guard localOffset + 30 <= bytes.count,
                  bytes[localOffset] == 0x50, bytes[localOffset + 1] == 0x4B,
                  bytes[localOffset + 2] == 0x03, bytes[localOffset + 3] == 0x04 else { continue }
            let dataStart = localOffset + 30 + u16(localOffset + 26) + u16(localOffset + 28)
            guard dataStart + compressedSize <= bytes.count else { continue }
            let payload = Array(bytes[dataStart..<(dataStart + compressedSize)])
            if method == 0 {
                files.append(ZipFile(name: name, data: Data(payload)))
            } else if method == 8, let inflated = inflate(payload) {
                files.append(ZipFile(name: name, data: inflated))
            }
        }
        return files
    }

    /// Raw DEFLATE (RFC 1951) via the Compression framework.
    static func inflate(_ payload: [UInt8]) -> Data? {
        guard !payload.isEmpty else { return Data() }
        var capacity = max(payload.count * 4, 65_536)
        for _ in 0..<6 {
            var output = [UInt8](repeating: 0, count: capacity)
            let written = payload.withUnsafeBufferPointer { source in
                output.withUnsafeMutableBufferPointer { destination in
                    compression_decode_buffer(destination.baseAddress!, capacity,
                                              source.baseAddress!, payload.count, nil, COMPRESSION_ZLIB)
                }
            }
            if written == 0 { return nil }
            if written < capacity { return Data(output[..<written]) }
            capacity *= 4
        }
        return nil
    }
}
