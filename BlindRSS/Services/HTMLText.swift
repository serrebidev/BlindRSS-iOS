// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation

/// Plain-text rendering of feed HTML, the iOS counterpart of desktop
/// core.utils.html_to_text. VoiceOver reads the reader as text, so block
/// elements become line breaks and markup never reaches the user.
enum HTMLText {
    // Reader presentation (desktop Settings: Reading; all off by
    // default there, matching desktop render_presentation defaults).
    static var presentationBullets: Bool { UserDefaults.standard.bool(forKey: "reader.bullets") }
    static var presentationQuotes: Bool { UserDefaults.standard.bool(forKey: "reader.quotes") }
    static var presentationLinks: Bool { UserDefaults.standard.bool(forKey: "reader.links") }
    static var presentationAltText: Bool { UserDefaults.standard.bool(forKey: "reader.altText") }

    /// Rewrites <a href>text</a> as "text (URL)" so links stay usable
    /// once tags are stripped (desktop presentation links toggle).
    static func rewritingLinkTargets(_ html: String) -> String {
        let pattern = "<a[^>]*href=\"(https?://[^\"]+)\"[^>]*>(.*?)</a>"
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return html }
        var result = html
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html),
                  let whole = Range(match.range, in: result) else { continue }
            let url = String(html[urlRange])
            let inner = String(html[textRange])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = inner.isEmpty ? url : "\(inner) (\(url))"
            result.replaceSubrange(whole, with: replacement)
        }
        return result
    }

    /// Rewrites <img alt="..."> as "[Image: ...]" (desktop alt-text toggle).
    static func rewritingImageAltText(_ html: String) -> String {
        html.replacingOccurrences(of: "<img[^>]*alt=\"([^\"]+)\"[^>]*>",
                                  with: "[Image: $1]", options: [.regularExpression, .caseInsensitive])
    }

    static func plainText(from html: String?) -> String {
        guard var text = html, !text.isEmpty else { return "" }
        // Drop script/style bodies entirely.
        for tag in ["script", "style"] {
            while let open = text.range(of: "<\(tag)", options: .caseInsensitive),
                  let close = text.range(of: "</\(tag)>", options: .caseInsensitive, range: open.upperBound..<text.endIndex) {
                text.removeSubrange(open.lowerBound..<close.upperBound)
            }
        }
        // Presentation rewrites run before tags are stripped.
        if presentationAltText { text = rewritingImageAltText(text) }
        if presentationLinks { text = rewritingLinkTargets(text) }
        if presentationBullets {
            text = text.replacingOccurrences(of: "<li( [^>]*)?>", with: "\n• ",
                                             options: [.regularExpression, .caseInsensitive])
        }
        if presentationQuotes {
            text = text.replacingOccurrences(of: "<blockquote( [^>]*)?>", with: "\nQuote: ",
                                             options: [.regularExpression, .caseInsensitive])
            text = text.replacingOccurrences(of: "</blockquote>", with: "\nEnd of quote.\n",
                                             options: .caseInsensitive)
        }
        let blockBreaks = ["</p>", "<br>", "<br/>", "<br />", "</li>", "</h1>", "</h2>",
                           "</h3>", "</h4>", "</h5>", "</h6>", "</div>", "</tr>", "</blockquote>"]
        for br in blockBreaks {
            text = text.replacingOccurrences(of: br, with: "\n", options: .caseInsensitive)
        }
        // Strip remaining tags.
        var out = ""
        var inTag = false
        for ch in text {
            if ch == "<" { inTag = true }
            else if ch == ">" { inTag = false }
            else if !inTag { out.append(ch) }
        }
        out = decodeEntities(out)
        // Collapse runs of blank lines and trailing spaces per line.
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var collapsed: [String] = []
        var lastBlank = true
        for line in lines {
            if line.isEmpty {
                if !lastBlank { collapsed.append("") }
                lastBlank = true
            } else {
                collapsed.append(line)
                lastBlank = false
            }
        }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func preview(from html: String?, maxChars: Int = 320) -> String {
        let text = plainText(from: html).replacingOccurrences(of: "\n", with: " ")
        guard text.count > maxChars else { return text }
        return String(text.prefix(maxChars)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
        "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}", "bull": "\u{2022}",
        "middot": "\u{00B7}", "copy": "\u{00A9}", "reg": "\u{00AE}", "trade": "\u{2122}",
        "deg": "\u{00B0}", "times": "\u{00D7}", "eacute": "\u{00E9}", "laquo": "\u{00AB}",
        "raquo": "\u{00BB}", "euro": "\u{20AC}", "pound": "\u{00A3}", "shy": "",
    ]

    /// One pass, so "&amp;lt;" stays "&lt;" instead of becoming "<".
    /// Numeric entities (&#8217; and &#x2019;) are decoded too: web pages
    /// use them for most punctuation, and VoiceOver read them out raw.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(10).firstIndex(of: ";") {
                let name = after[..<semi]
                var decoded: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    decoded = namedEntities[String(name)]
                }
                if let decoded {
                    out += decoded
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        return out + rest
    }
}

/// One paragraph or heading in the reader. Each is its own VoiceOver stop,
/// so a long article can be moved through by paragraph and headings show
/// up in the Headings rotor.
struct ReaderBlock: Hashable {
    var isHeading: Bool
    var text: String
}

extension HTMLText {
    /// Feed text as reader paragraphs: one block per line of plainText.
    static func blocks(fromPlainText text: String) -> [ReaderBlock] {
        text.split(separator: "\n").map { ReaderBlock(isHeading: false, text: String($0)) }
    }

    // MARK: Video pages

    /// The video a news video page plays (an Arc XP stream list, JSON-LD
    /// contentUrl, og:video, or a video tag all spell it out as a plain
    /// .mp4 or .m3u8 address). Such pages carry a caption, not an
    /// article, so their spoken soundtrack is the full text. The smallest
    /// MP4 wins: quickest to transcribe and downloadable; HLS is the
    /// fallback.
    static func pageVideoURL(fromPage html: String) -> URL? {
        let unescaped = html.replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
        guard let regex = try? NSRegularExpression(
            pattern: "https?://[^\"'\\s<>\\\\]+?\\.(?:mp4|m3u8)(?:\\?[^\"'\\s<>\\\\]*)?",
            options: .caseInsensitive) else { return nil }
        var seen = Set<String>()
        var mp4: [(height: Int, url: URL)] = []
        var hls: [URL] = []
        for match in regex.matches(in: unescaped, range: NSRange(unescaped.startIndex..., in: unescaped)) {
            guard let range = Range(match.range, in: unescaped) else { continue }
            let address = String(unescaped[range])
            guard seen.insert(address).inserted, let url = URL(string: address) else { continue }
            if url.pathExtension.lowercased() == "mp4" {
                mp4.append((videoHeight(in: address) ?? Int.max, url))
            } else {
                hls.append(url)
            }
        }
        return mp4.min { $0.height < $1.height }?.url ?? hls.first
    }

    /// "640x360" or "_360p" in a stream address, as a frame height.
    private static func videoHeight(in address: String) -> Int? {
        for pattern in ["\\d{3,4}x(\\d{3,4})", "[_\\-/](\\d{3,4})p\\b"] {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)),
               let range = Range(match.range(at: 1), in: address) {
                return Int(address[range])
            }
        }
        return nil
    }

    /// The page's declared language (`<html lang="en-CA">`), for speech
    /// recognition of its video.
    static func pageLanguage(fromPage html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<html[^>]*\\blang\\s*=\\s*[\"']?([A-Za-z]{2,3}(?:-[A-Za-z0-9]+)*)",
                                                   options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    /// Speech recognition phrases joined into reader paragraphs of about
    /// `target` characters, each ending where a sentence does.
    static func paragraphs(fromPhrases phrases: [String], target: Int = 400) -> [ReaderBlock] {
        var result: [ReaderBlock] = []
        var current = ""
        for phrase in phrases {
            let piece = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if piece.isEmpty { continue }
            current = current.isEmpty ? piece : current + " " + piece
            if current.count >= target, let last = current.last, ".!?".contains(last) {
                result.append(ReaderBlock(isHeading: false, text: current))
                current = ""
            }
        }
        if !current.isEmpty { result.append(ReaderBlock(isHeading: false, text: current)) }
        return result
    }

    /// Readability-style extraction of the article in a web page. Scores
    /// containers by real paragraph text, penalizes link-heavy boilerplate,
    /// then emits the winning container plus its qualifying siblings in
    /// order. Stripping every tag of the whole page, as before, read out
    /// menus, footers, and cookie banners.
    static func articleBlocks(fromPage html: String) -> [ReaderBlock] {
        let root = DOMNode.parse(html)
        var candidates: [DOMNode] = []
        root.collect(into: &candidates) { ["article", "main", "div", "section"].contains($0.tag) }
        var best: DOMNode?
        var bestScore = 0.0
        for node in candidates where node.paragraphScore > 0 {
            var score = node.paragraphScore * (1 - Double(node.linkLength) / Double(max(1, node.textLength)))
            if node.attributes.range(of: "article|entry|post|story|content|main|text|body", options: .regularExpression) != nil { score *= 1.5 }
            if node.attributes.range(of: Self.junkPattern, options: .regularExpression) != nil { score *= 0.25 }
            if score > bestScore { bestScore = score; best = node }
        }
        var blocks: [ReaderBlock] = []
        if let winner = best, let parent = winner.parent, parent !== root {
            // Readability appends qualifying siblings of the top candidate:
            // news bodies are routinely split across sibling containers
            // (a standfirst block, body sections in separate wrappers,
            // related boxes in between), so reading only the winning
            // container silently drops the rest of the article.
            for case .node(let sibling) in parent.children {
                if sibling === winner {
                    sibling.emitBlocks(into: &blocks, isRoot: true)
                } else if siblingQualifies(sibling, winnerScore: bestScore) {
                    sibling.emitBlocks(into: &blocks)
                }
            }
            if blocks.isEmpty { winner.emitBlocks(into: &blocks, isRoot: true) }
        } else {
            (best ?? root).emitBlocks(into: &blocks, isRoot: true)
        }
        // The winning container hid the text: fall back to every decent paragraph.
        if blocks.reduce(0, { $0 + $1.text.count }) < 200 {
            var paragraphs: [DOMNode] = []
            root.collect(into: &paragraphs) { $0.tag == "p" }
            blocks = paragraphs.map(\.text).filter { $0.count >= 80 }
                .flatMap { $0.split(separator: "\n") }.map { ReaderBlock(isHeading: false, text: String($0)) }
        }
        return blocks
    }

    /// Whether a sibling of the winning container carries article text
    /// worth appending. Mirrors Readability's sibling rules: a real share
    /// of the winner's paragraph score, or a long low-link stretch of
    /// prose (a standfirst often scores as a single paragraph). A
    /// junk-classed sibling needs a far stronger case, so promo and
    /// related boxes stay out.
    fileprivate static func siblingQualifies(_ node: DOMNode, winnerScore: Double) -> Bool {
        let junkClassed = node.attributes.range(of: Self.junkPattern, options: .regularExpression) != nil
        if node.paragraphScore >= max(40, winnerScore * (junkClassed ? 0.75 : 0.2)) { return true }
        if junkClassed { return false }
        return node.textLength >= 120
            && Double(node.linkLength) / Double(max(1, node.textLength)) < 0.3
    }

    fileprivate static let junkPattern = "nav|menu|sidebar|footer|header|promo|related|comment|share|social|advert|cookie|popup|newsletter|subscribe"
    /// Skipped inside the chosen article. Narrower than junkPattern: a
    /// content wrapper classed "has-sidebar" must still be read.
    fileprivate static let inlineJunkPattern = "related|comment|share|social|advert|promo|cookie|popup|newsletter|subscribe"
}

/// Minimal HTML tree, just enough for article extraction without a
/// third-party parser. Tolerates unclosed tags the way pages need: an end
/// tag closes up to its matching open tag, a stray one is ignored.
private final class DOMNode {
    enum Child { case text(String), node(DOMNode) }

    let tag: String
    /// Lowercased class and id, for the content and boilerplate patterns.
    let attributes: String
    /// Set when attached during parsing; extraction walks it to reach
    /// the winning container's siblings.
    weak var parent: DOMNode?
    var children: [Child] = []
    private(set) var textLength = 0
    private(set) var linkLength = 0
    private(set) var paragraphScore = 0.0
    private(set) var hasBlockDescendant = false

    init(tag: String, attributes: String) {
        self.tag = tag
        self.attributes = attributes
    }

    private static let blockTags: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "pre", "dd", "dt"]
    /// Subtrees that are never article text.
    private static let droppedTags: Set<String> = ["nav", "header", "footer", "aside", "button", "select", "svg",
                                                   "template", "dialog", "menu", "object", "canvas", "video", "audio", "picture"]
    /// Contents are raw text, skipped to the end tag unparsed.
    private static let rawTags: Set<String> = ["script", "style", "textarea", "title", "noscript", "iframe", "xmp"]
    private static let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link",
                                                "meta", "param", "source", "track", "wbr"]
    /// Starting one of these closes an open <p>, as HTML parsers do.
    private static let closesParagraph: Set<String> = blockTags.union(["div", "ul", "ol", "table", "section", "article",
                                                                      "main", "form", "hr", "figure", "dl"])

    static func parse(_ html: String) -> DOMNode {
        let bytes = Array(html.utf8)
        let count = bytes.count
        let root = DOMNode(tag: "#root", attributes: "")
        var stack = [root]
        var textStart = 0
        var i = 0

        func flushText(upTo end: Int) {
            if end > textStart {
                stack[stack.count - 1].children.append(.text(String(decoding: bytes[textStart..<end], as: UTF8.self)))
            }
        }
        func find(_ needle: [UInt8], from start: Int, caseInsensitive: Bool = false) -> Int? {
            guard needle.count <= count else { return nil }
            var j = start
            while j <= count - needle.count {
                var k = 0
                while k < needle.count, (caseInsensitive ? lower(bytes[j + k]) : bytes[j + k]) == needle[k] { k += 1 }
                if k == needle.count { return j }
                j += 1
            }
            return nil
        }

        while i < count {
            guard bytes[i] == UInt8(ascii: "<"), i + 1 < count else { i += 1; continue }
            let next = bytes[i + 1]
            if next == UInt8(ascii: "!") || next == UInt8(ascii: "?") {
                flushText(upTo: i)
                let isComment = i + 3 < count && bytes[i + 2] == UInt8(ascii: "-") && bytes[i + 3] == UInt8(ascii: "-")
                if isComment {
                    i = find(Array("-->".utf8), from: i + 4).map { $0 + 3 } ?? count
                } else {
                    i = find([UInt8(ascii: ">")], from: i).map { $0 + 1 } ?? count
                }
                textStart = i
                continue
            }
            let isEnd = next == UInt8(ascii: "/")
            var j = isEnd ? i + 2 : i + 1
            // A "<" not followed by a tag name is text ("a < b").
            guard j < count, isLetter(bytes[j]) else { i += 1; continue }
            flushText(upTo: i)
            let nameStart = j
            while j < count, isLetter(bytes[j]) || isDigit(bytes[j]) || bytes[j] == UInt8(ascii: "-") { j += 1 }
            let name = String(decoding: bytes[nameStart..<j].map(lower), as: UTF8.self)
            // Find the tag's closing ">", skipping quoted attribute values.
            var quote: UInt8 = 0
            while j < count {
                let b = bytes[j]
                if quote != 0 { if b == quote { quote = 0 } }
                else if b == UInt8(ascii: "\"") || b == UInt8(ascii: "'") { quote = b }
                else if b == UInt8(ascii: ">") { break }
                j += 1
            }
            let tagEnd = min(j, count)
            i = min(tagEnd + 1, count)
            textStart = i

            if isEnd {
                if let index = stack.lastIndex(where: { $0.tag == name }), index > 0 {
                    stack.removeSubrange(index...)
                }
                continue
            }
            if rawTags.contains(name) {
                i = find(Array("</\(name)".utf8), from: i, caseInsensitive: true)
                    .flatMap { find([UInt8(ascii: ">")], from: $0) }.map { $0 + 1 } ?? count
                textStart = i
                continue
            }
            if name == "br" {
                stack[stack.count - 1].children.append(.text(String(lineBreak)))
                continue
            }
            if voidTags.contains(name) { continue }
            let rawAttributes = String(decoding: bytes[(nameStart + name.utf8.count)..<tagEnd], as: UTF8.self)
            if closesParagraph.contains(name), stack.count > 1, stack[stack.count - 1].tag == "p" {
                stack.removeLast()
            }
            if name == "li", let open = stack.lastIndex(where: { ["li", "ul", "ol"].contains($0.tag) }),
               stack[open].tag == "li" {
                stack.removeSubrange(open...)
            }
            let node = DOMNode(tag: name, attributes: classAndID(rawAttributes))
            // Dropped subtrees are still pushed so their end tags match,
            // but never attached, so their text never counts.
            if !droppedTags.contains(name) {
                node.parent = stack[stack.count - 1]
                stack[stack.count - 1].children.append(.node(node))
            }
            let selfClosing = rawAttributes.hasSuffix("/")
            // Depth cap keeps runaway unclosed markup from overflowing the stack.
            if !selfClosing, stack.count < 400 { stack.append(node) }
        }
        flushText(upTo: count)
        root.measure()
        return root
    }

    /// Text with HTML whitespace rules: runs of whitespace become one space,
    /// and each <br> starts a new line.
    var text: String {
        var parts: [String] = []
        appendText(to: &parts)
        return HTMLText.decodeEntities(parts.joined()).split(separator: Self.lineBreak)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Stands in for <br> in parsed text: Unicode LINE SEPARATOR, so it
    /// cannot be confused with newlines in the page source.
    private static let lineBreak: Character = "\u{2028}"

    private func appendText(to parts: inout [String]) {
        for child in children {
            switch child {
            case .text(let string): parts.append(string)
            case .node(let node): node.appendText(to: &parts)
            }
        }
    }

    /// Bottom-up text, link, and paragraph totals, one pass for the tree.
    private func measure() {
        for child in children {
            switch child {
            case .text(let string):
                textLength += string.split(whereSeparator: \.isWhitespace).reduce(0) { $0 + $1.count + 1 }
            case .node(let node):
                node.measure()
                textLength += node.textLength
                linkLength += node.linkLength
                paragraphScore += node.paragraphScore
                hasBlockDescendant = hasBlockDescendant || node.hasBlockDescendant || Self.blockTags.contains(node.tag)
            }
        }
        if tag == "a" { linkLength = textLength }
        // Quoted text counts as paragraphs too: a Ghost post that is mostly
        // one long blockquote lost to the "more posts" excerpts below it.
        if tag == "p" || (["blockquote", "pre"].contains(tag) && !hasBlockDescendant) {
            let text = self.text
            if text.count >= 40 {
                paragraphScore += Double(text.count) + Double(text.filter { $0 == "," }.count) * 10
            }
        }
    }

    func collect(into result: inout [DOMNode], where matches: (DOMNode) -> Bool) {
        for case .node(let node) in children {
            if matches(node) { result.append(node) }
            node.collect(into: &result, where: matches)
        }
    }

    /// Leaf blocks in document order: a block holding other blocks (li > p)
    /// is read through its children instead, so nothing is read twice.
    func emitBlocks(into blocks: inout [ReaderBlock], isRoot: Bool = false) {
        if !isRoot, attributes.range(of: HTMLText.inlineJunkPattern, options: .regularExpression) != nil { return }
        if Self.blockTags.contains(tag), !hasBlockDescendant {
            let text = self.text
            let isHeading = tag.count == 2 && tag.hasPrefix("h")
            guard !text.isEmpty, blocks.last?.text != text else { return }
            // Mostly-link blocks are menus and related-story headlines.
            if linkLength * 2 > textLength { return }
            // Short lines with no sentence ending are labels like
            // "Advertisement" or "Read more"; short sentences are kept.
            if !isHeading, text.count < 25, !(text.last.map { ".!?,\"\u{201D}:".contains($0) } ?? false) { return }
            if isHeading {
                blocks.append(ReaderBlock(isHeading: true, text: text.replacingOccurrences(of: "\n", with: " ")))
            } else {
                var lines = text.split(separator: "\n").map { ReaderBlock(isHeading: false, text: String($0)) }
                if tag == "li", HTMLText.presentationBullets, !lines.isEmpty {
                    lines[0] = ReaderBlock(isHeading: false, text: "• " + lines[0].text)
                }
                if tag == "blockquote", HTMLText.presentationQuotes, !lines.isEmpty {
                    lines[0] = ReaderBlock(isHeading: false, text: "Quote: " + lines[0].text)
                }
                blocks += lines
            }
            return
        }
        for case .node(let node) in children {
            node.emitBlocks(into: &blocks)
        }
    }

    private static func classAndID(_ raw: String) -> String {
        var values: [String] = []
        for name in ["class", "id"] {
            guard let match = raw.range(of: "\\b\(name)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
                                        options: [.regularExpression, .caseInsensitive]) else { continue }
            let value = raw[match].drop(while: { $0 != "=" }).dropFirst()
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            values.append(value.lowercased())
        }
        return values.joined(separator: " ")
    }

    private static func lower(_ b: UInt8) -> UInt8 { (b >= 65 && b <= 90) ? b + 32 : b }
    private static func isLetter(_ b: UInt8) -> Bool { (b | 0x20) >= 97 && (b | 0x20) <= 122 }
    private static func isDigit(_ b: UInt8) -> Bool { b >= 48 && b <= 57 }
}
