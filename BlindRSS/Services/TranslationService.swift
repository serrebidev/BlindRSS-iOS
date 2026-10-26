// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation

/// Keyless article translation (research round 0.1.13). The desktop
/// translates through a bring-your-own AI API key; the research found
/// two public, keyless translation backends other apps ship with:
/// Lingva Translate (open-source Google Translate frontend, REST API
/// GET /api/v1/<source>/<target>/<text> -> {"translation": ...}) and
/// keyless public LibreTranslate mirrors (POST /translate ->
/// {"translatedText": ...}). Several instances of each are tried in
/// order, so one dead instance does not break translation. No account
/// or key exists to configure.
enum TranslateService {
    static let lingvaInstances = [
        "https://lingva.ml",
        "https://translate.igna.wtf",
        "https://lingva.lunar.icu",
        "https://translate.plausibility.cloud",
        "https://translate.projectsegfau.lt",
        "https://lingva.garudalinux.org",
    ]

    static let libreTranslateInstances = [
        "https://translate.argosopentech.com",
        "https://libretranslate.eownerdead.dedyn.io",
        "https://lt.vern.cc",
        "https://trans.zillyhuhn.com",
    ]

    // MARK: Response parsing (pure, unit-tested)

    static func parseLingva(_ data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["translation"] as? String, !text.isEmpty else { return nil }
        return text
    }

    static func parseLibreTranslate(_ data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["translatedText"] as? String, !text.isEmpty else { return nil }
        return text
    }

    /// Splits long text into request-sized chunks at paragraph, then
    /// sentence, boundaries. GET-based Lingva URLs cannot carry a whole
    /// article, so translation runs chunk by chunk.
    static func chunks(of text: String, maxLength: Int = 1200) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed.isEmpty ? [] : [trimmed] }
        var result: [String] = []
        var current = ""
        for paragraph in trimmed.components(separatedBy: "\n") {
            let piece = paragraph.trimmingCharacters(in: .whitespaces)
            if piece.isEmpty { continue }
            if current.count + piece.count + 1 <= maxLength {
                current = current.isEmpty ? piece : current + "\n" + piece
            } else if piece.count <= maxLength {
                if !current.isEmpty { result.append(current) }
                current = piece
            } else {
                if !current.isEmpty { result.append(current); current = "" }
                // One oversized paragraph: split on sentence ends.
                var rest = piece
                while rest.count > maxLength {
                    let cut = rest.prefix(maxLength)
                    if let boundary = cut.lastIndex(where: { ".!?".contains($0) }) {
                        result.append(String(rest[...boundary]).trimmingCharacters(in: .whitespaces))
                        rest = String(rest[rest.index(after: boundary)...]).trimmingCharacters(in: .whitespaces)
                    } else {
                        result.append(String(cut))
                        rest = String(rest.dropFirst(maxLength)).trimmingCharacters(in: .whitespaces)
                    }
                }
                current = rest
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: Translation

    /// Translates text into the target language code (e.g. "es"),
    /// auto-detecting the source. Returns nil when every public
    /// instance failed.
    static func translate(_ text: String, to target: String, from source: String = "auto") async -> String? {
        let pieces = chunks(of: text)
        guard !pieces.isEmpty else { return nil }
        var translated: [String] = []
        for piece in pieces {
            guard let done = await translateChunk(piece, to: target, from: source) else { return nil }
            translated.append(done)
        }
        return translated.joined(separator: "\n")
    }

    private static func translateChunk(_ text: String, to target: String, from source: String) async -> String? {
        for instance in lingvaInstances {
            if let result = await lingva(instance: instance, text: text, to: target, from: source) { return result }
        }
        for instance in libreTranslateInstances {
            if let result = await libreTranslate(instance: instance, text: text, to: target, from: source) { return result }
        }
        return nil
    }

    private static func lingva(instance: String, text: String, to target: String, from source: String) async -> String? {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text
        guard let url = URL(string: "\(instance)/api/v1/\(source)/\(target)/\(encoded)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parseLingva(data)
    }

    private static func libreTranslate(instance: String, text: String, to target: String, from source: String) async -> String? {
        guard let url = URL(string: "\(instance)/translate") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "q": text, "source": source, "target": target, "format": "text",
        ])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parseLibreTranslate(data)
    }
}
