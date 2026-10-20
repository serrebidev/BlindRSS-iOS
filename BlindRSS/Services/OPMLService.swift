// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

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
