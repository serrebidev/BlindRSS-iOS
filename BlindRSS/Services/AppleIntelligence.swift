// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(Translation)
import NaturalLanguage
import Translation
#endif

/// Apple Intelligence (0.1.17): article summaries, key points, questions
/// about an article, and a spoken briefing of unread articles, all from
/// Apple's on-device model (Foundation Models, iOS 26). Nothing leaves
/// the device and no account or key exists to configure.
///
/// The app still runs on iOS 17: every model call is behind
/// `#available(iOS 26, *)`, and `status` explains why the features are
/// missing on older systems, ineligible devices, or with Apple
/// Intelligence turned off.
///
/// The on-device model has a small context window (about 4,096 tokens
/// for instructions, prompt, and answer together), so long articles run
/// map-reduce: each chunk is condensed first, then the notes are
/// answered. A context overflow shrinks the chunks and retries, so
/// languages that need more tokens per character still finish.
enum AppleIntelligence {
    /// What to ask the model about a text.
    enum Request: Equatable {
        case summary
        case keyPoints
        case question(String)
        /// Headlines of several articles (see `briefingText`).
        case briefing

        var heading: String {
            switch self {
            case .summary: return "Summary"
            case .keyPoints: return "Key Points"
            case .question: return "Answer"
            case .briefing: return "Briefing"
            }
        }
    }

    /// Characters per chunk on the first try; about 1,500 tokens of
    /// English, which leaves room for instructions and the answer.
    static let chunkLength = 5000
    static let minimumChunkLength = 600

    // MARK: Pure helpers (unit-tested)

    /// Model output for VoiceOver: Markdown emphasis, heading marks, and
    /// list bullets removed (VoiceOver reads them as "star star"), blank
    /// lines dropped, one paragraph or point per line.
    static func cleanOutput(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { line -> String in
                var line = line.trimmingCharacters(in: .whitespaces)
                while line.hasPrefix("#") { line.removeFirst() }
                for marker in ["- ", "* ", "• ", "+ "] where line.hasPrefix(marker) {
                    line.removeFirst(marker.count)
                    break
                }
                return line.replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "__", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// The model's way of saying a chunk has nothing for the question.
    static func isEmptyNote(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return trimmed.isEmpty || trimmed.uppercased() == "NONE"
    }

    /// Input for a briefing: one line per article, feed and title then
    /// the start of its text, capped so the briefing stays a handful of
    /// model calls even for a large unread list.
    static func briefingText(for items: [(title: String, feed: String, snippet: String)],
                             limit: Int = 40, snippetLength: Int = 200) -> String {
        items.prefix(limit).map { item in
            var line = item.feed.isEmpty ? item.title : "\(item.feed): \(item.title)"
            let snippet = item.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if !snippet.isEmpty { line += ". " + String(snippet.prefix(snippetLength)) }
            return line
        }
        .joined(separator: "\n")
    }

    /// How well an article title matches what visual intelligence saw
    /// (its labels, such as "dog" or "Golden Gate Bridge"): the number
    /// of label words found in the title. 0 means no match.
    static func relevance(of title: String, to labels: [String]) -> Int {
        let words = Set(title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
        var score = 0
        for label in labels {
            let parts = label.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
            score += parts.filter { words.contains($0) }.count
        }
        return score
    }

    static func instructions(for request: Request) -> String {
        let common = "Write plain text only, no Markdown, no headings, no asterisks. "
            + "Write in the same language as the text you are given. Do not translate."
        switch request {
        case .summary:
            return "You summarize news and blog articles for a reader who listens with a screen reader. "
                + "Give a clear, neutral summary in three to five sentences. " + common
        case .keyPoints:
            return "You list the key points of news and blog articles for a reader who listens with a screen reader. "
                + "Give three to seven key points, one short sentence per line. " + common
        case .question:
            return "You answer questions about an article using only the article. "
                + "If the article does not contain the answer, say so in one sentence. " + common
        case .briefing:
            return "You turn a list of new article headlines into a short spoken news briefing. "
                + "Group related headlines by topic, one line per topic, one or two sentences each, "
                + "and name the feeds where helpful. " + common
        }
    }

    /// Prompt for one chunk of a text longer than one model call.
    static func notesPrompt(for request: Request, chunk: String) -> String {
        switch request {
        case .summary, .briefing:
            return "Summarize this part in a few sentences:\n\n\(chunk)"
        case .keyPoints:
            return "List the key points of this part, one per line:\n\n\(chunk)"
        case .question(let question):
            return "Copy the facts from this part that help answer the question \"\(question)\". "
                + "If nothing helps, reply NONE.\n\n\(chunk)"
        }
    }

    /// Prompt for the final answer, from the whole text or from notes.
    static func finalPrompt(for request: Request, title: String, text: String) -> String {
        let titled = title.isEmpty ? text : "Title: \(title)\n\n\(text)"
        switch request {
        case .summary: return "Summarize this article:\n\n\(titled)"
        case .keyPoints: return "List the key points of this article:\n\n\(titled)"
        case .question(let question): return "Question: \(question)\n\nArticle:\n\(titled)"
        case .briefing: return "Write the briefing for these new articles:\n\n\(text)"
        }
    }

    // MARK: Availability

    /// Whether this system and device can offer the features at all
    /// (iOS 26 on an Apple Intelligence device), even if the model is
    /// still downloading or Apple Intelligence is turned off.
    static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if case .unavailable(.deviceNotEligible) = SystemLanguageModel.default.availability { return false }
            return true
        }
        #endif
        return false
    }

    /// Whether the model can run now, and a sentence for Settings and
    /// for spoken errors saying why not.
    static var status: (isAvailable: Bool, message: String) {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                if !SystemLanguageModel.default.supportsLocale() {
                    return (true, "Apple Intelligence is ready, but it does not support your device language yet. Answers may be in another language.")
                }
                return (true, "Apple Intelligence is ready. Summaries run privately on this device.")
            case .unavailable(.deviceNotEligible):
                return (false, "This device does not support Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return (false, "Apple Intelligence is turned off. Turn it on in the Settings app, under Apple Intelligence and Siri.")
            case .unavailable(.modelNotReady):
                return (false, "Apple Intelligence is still downloading its model. Try again later.")
            case .unavailable:
                return (false, "Apple Intelligence is not available right now.")
            }
        }
        #endif
        return (false, "Apple Intelligence needs iOS 26 or later on a device that supports it.")
    }

    // MARK: Generation

    /// Runs a request over a text of any length and returns cleaned
    /// plain text. Throws `AppleIntelligenceError` with a spoken-ready
    /// message on every failure.
    static func run(_ request: Request, title: String = "", text: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let state = status
            guard state.isAvailable else { throw AppleIntelligenceError(message: state.message) }
            let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty || !title.isEmpty else {
                throw AppleIntelligenceError(message: "There is no text to work with.")
            }
            var length = chunkLength
            while true {
                do {
                    return try await generate(request, title: title, text: source, chunkLength: length)
                } catch let error as LanguageModelSession.GenerationError {
                    if case .exceededContextWindowSize = error, length > minimumChunkLength {
                        length /= 2
                        continue
                    }
                    throw AppleIntelligenceError(message: message(for: error))
                }
            }
        }
        #endif
        throw AppleIntelligenceError(message: status.message)
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private static func generate(_ request: Request, title: String, text: String, chunkLength: Int) async throws -> String {
        var material = text
        // Condense until the text fits one call. Notes are shorter than
        // their chunk, so this ends; the round cap guards a model that
        // answers at length, after which the notes are cut to fit.
        for _ in 0..<4 {
            let pieces = TranslateService.chunks(of: material, maxLength: chunkLength)
            guard pieces.count > 1 else { break }
            var notes: [String] = []
            for piece in pieces {
                try Task.checkCancellation()
                let note = try await respond(notesPrompt(for: request, chunk: piece), request: request)
                if !isEmptyNote(note) { notes.append(note) }
            }
            if notes.isEmpty, case .question = request {
                return "The article does not answer that question."
            }
            material = notes.joined(separator: "\n")
        }
        if material.count > chunkLength { material = String(material.prefix(chunkLength)) }
        let answer = try await respond(finalPrompt(for: request, title: title, text: material), request: request)
        let cleaned = cleanOutput(answer)
        guard !cleaned.isEmpty else { throw AppleIntelligenceError(message: "Apple Intelligence returned an empty answer.") }
        return cleaned
    }

    /// One model call in a fresh session: a session keeps its whole
    /// transcript, which would overflow the context across chunks.
    /// Permissive content transformations let it summarize news about
    /// violence, crime, or politics, which default guardrails refuse.
    @available(iOS 26, *)
    private static func respond(_ prompt: String, request: Request) async throws -> String {
        let session = LanguageModelSession(model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
                                           instructions: instructions(for: request))
        return try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.3)).content
    }

    @available(iOS 26, *)
    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            return "This article is too long for Apple Intelligence."
        case .guardrailViolation, .refusal:
            return "Apple Intelligence declined to work with this article's content."
        case .unsupportedLanguageOrLocale:
            return "Apple Intelligence does not support this article's language yet."
        case .assetsUnavailable:
            return "Apple Intelligence's model is not ready. Try again later."
        case .rateLimited, .concurrentRequests:
            return "Apple Intelligence is busy. Try again in a moment."
        default:
            return error.localizedDescription
        }
    }
    #endif

    // MARK: On-device translation

    /// Translates paragraphs with Apple's on-device translation
    /// (Translation framework) when the article's language and the
    /// device language are both downloaded. Returns nil when it cannot,
    /// and the reader falls back to the public translation services.
    static func translateOnDevice(_ paragraphs: [String], to target: Locale.Language) async -> [String]? {
        #if canImport(Translation)
        if #available(iOS 26, *) {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(String(paragraphs.joined(separator: " ").prefix(2000)))
            guard let detected = recognizer.dominantLanguage?.rawValue else { return nil }
            let source = Locale.Language(identifier: detected)
            guard source.languageCode != target.languageCode,
                  await LanguageAvailability().status(from: source, to: target) == .installed else { return nil }
            let session = TranslationSession(installedSource: source, target: target)
            var result: [String] = []
            for paragraph in paragraphs {
                guard let response = try? await session.translate(paragraph) else { return nil }
                result.append(response.targetText)
            }
            return result
        }
        #endif
        return nil
    }
}

/// A failure with a message ready to show and speak.
struct AppleIntelligenceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
