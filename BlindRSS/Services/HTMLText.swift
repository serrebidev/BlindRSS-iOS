// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation

/// Plain-text rendering of feed HTML, the iOS counterpart of desktop
/// core.utils.html_to_text. VoiceOver reads the reader as text, so block
/// elements become line breaks and markup never reaches the user.
enum HTMLText {
    static func plainText(from html: String?) -> String {
        guard var text = html, !text.isEmpty else { return "" }
        // Drop script/style bodies entirely.
        for tag in ["script", "style"] {
            while let open = text.range(of: "<\(tag)", options: .caseInsensitive),
                  let close = text.range(of: "</\(tag)>", options: .caseInsensitive, range: open.upperBound..<text.endIndex) {
                text.removeSubrange(open.lowerBound..<close.upperBound)
            }
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

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        let map: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
        ]
        for (entity, replacement) in map {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Numeric entities: &#123; and &#x1F600;
        return result
    }
}
