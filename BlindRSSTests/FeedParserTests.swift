// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftData
import XCTest


final class FeedParserTests: XCTestCase {
    func testRSS20ParsesChannelItemsAndEnclosure() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
        <title>Example Podcast</title><link>https://example.com</link><language>en-us</language>
        <item><title>Episode One</title><link>https://example.com/1</link>
        <guid>ep-1</guid><pubDate>Mon, 20 Oct 2026 07:00:00 GMT</pubDate>
        <author>host@example.com (Host)</author>
        <description>First episode notes</description>
        <enclosure url="https://example.com/ep1.mp3" type="audio/mpeg" length="123"/>
        </item></channel></rss>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8), sourceURL: URL(string: "https://example.com/feed.xml")!)
        XCTAssertEqual(feed.title, "Example Podcast")
        XCTAssertEqual(feed.language, "en-us")
        XCTAssertEqual(feed.entries.count, 1)
        XCTAssertEqual(feed.entries[0].guid, "ep-1")
        XCTAssertEqual(feed.entries[0].mediaURL, "https://example.com/ep1.mp3")
        XCTAssertEqual(feed.entries[0].mediaType, "audio/mpeg")
        XCTAssertNotNil(feed.entries[0].date)
    }

    func testAtomParsesEntriesAndAlternateLink() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Atom Blog</title><link href="https://blog.example.com"/>
        <entry><title>Hello</title><id>post-1</id>
        <link rel="alternate" href="https://blog.example.com/hello"/>
        <published>2026-10-20T07:00:00Z</published>
        <summary>Summary text</summary></entry></feed>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8), sourceURL: URL(string: "https://blog.example.com/feed")!)
        XCTAssertEqual(feed.title, "Atom Blog")
        XCTAssertEqual(feed.entries.first?.link, "https://blog.example.com/hello")
        XCTAssertEqual(feed.entries.first?.guid, "post-1")
    }

    func testJSONFeedParsesAttachments() throws {
        let json = """
        {"version":"https://jsonfeed.org/version/1.1","title":"JSON Show",
         "items":[{"id":"j1","url":"https://example.com/j1","title":"Json Ep",
                   "content_text":"notes","date_published":"2026-10-20T07:00:00Z",
                   "attachments":[{"url":"https://example.com/j1.mp3","mime_type":"audio/mpeg"}]}]}
        """
        let feed = try FeedParser.parse(data: Data(json.utf8), sourceURL: URL(string: "https://example.com/feed.json")!)
        XCTAssertEqual(feed.title, "JSON Show")
        XCTAssertEqual(feed.entries.first?.mediaURL, "https://example.com/j1.mp3")
    }

    func testNotAFeedThrows() {
        XCTAssertThrowsError(try FeedParser.parse(data: Data("<html><body>no</body></html>".utf8),
                                                  sourceURL: URL(string: "https://example.com")!))
    }
}

final class PodcastServiceTests: XCTestCase {
    func testChaptersJSONParsesAndSorts() throws {
        let json = #"{"version":"1.2.0","chapters":[{"startTime":120,"title":"Second"},{"startTime":0,"title":"First","url":"https://example.com"}]}"#
        let chapters = try PodcastService.parseChaptersJSON(data: Data(json.utf8))
        XCTAssertEqual(chapters.map(\.title), ["First", "Second"])
        XCTAssertEqual(chapters[0].href, "https://example.com")
    }

    func testResumePositionBacksUpTenSeconds() {
        XCTAssertEqual(PodcastService.resumePosition(saved: 600, duration: 3600), 590)
        XCTAssertEqual(PodcastService.resumePosition(saved: 15, duration: 3600), 5)
    }

    func testResumePositionRestartsNearEnd() {
        // Within the last 60 seconds counts as finished (desktop threshold).
        XCTAssertEqual(PodcastService.resumePosition(saved: 3590, duration: 3600), 0)
        XCTAssertEqual(PodcastService.resumePosition(saved: nil, duration: 3600), 0)
    }

    func testSearchJSONFiltersMissingFeedURLs() throws {
        let json = #"{"results":[{"collectionId":1,"collectionName":"Show","feedUrl":"https://example.com/feed"},{"collectionId":2,"collectionName":"NoFeed"}]}"#
        let results = try PodcastService.parseSearchJSON(data: Data(json.utf8))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Show")
    }

    func testInlinePodcastChaptersFromFeed() throws {
        let xml = """
        <rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel>
        <title>Show</title>
        <item><title>Ep</title><guid>e1</guid>
        <enclosure url="https://example.com/e.mp3" type="audio/mpeg"/>
        <podcast:chapters url="https://example.com/chapters.json" type="application/json+chapters"/>
        <podcast:chapter start="0" title="Intro"/><podcast:chapter start="1:30" title="Main"/>
        </item></channel></rss>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8), sourceURL: URL(string: "https://example.com/feed")!)
        XCTAssertEqual(feed.entries[0].chapterURL, "https://example.com/chapters.json")
        XCTAssertEqual(feed.entries[0].inlineChapters.count, 2)
        XCTAssertEqual(feed.entries[0].inlineChapters[1].start, 90)
    }

    func testGPodderJSONParses() throws {
        let json = #"[{"title":"Show","url":"https://example.com/feed","website":"https://example.com"}]"#
        let results = try PodcastService.parseGPodderJSON(data: Data(json.utf8))
        XCTAssertEqual(results.first?.title, "Show")
        XCTAssertEqual(results.first?.id, "https://example.com/feed")
    }

    func testLooksLikeURL() {
        XCTAssertTrue(PodcastService.looksLikeURL("https://example.com/blog"))
        XCTAssertTrue(PodcastService.looksLikeURL("example.com"))
        XCTAssertFalse(PodcastService.looksLikeURL("daily tech podcast"))
        XCTAssertFalse(PodcastService.looksLikeURL("news"))
    }

    func testTimestampParsing() {
        XCTAssertEqual(FeedParser.parseTimestamp("90"), 90)
        XCTAssertEqual(FeedParser.parseTimestamp("1:30"), 90)
        XCTAssertEqual(FeedParser.parseTimestamp("1:02:30"), 3750)
        XCTAssertNil(FeedParser.parseTimestamp("soon"))
    }

    /// Shared formatters must keep every supported format working.
    func testDateParsingFormats() {
        let expected = Date(timeIntervalSince1970: 1_792_479_600) // 2026-10-20 07:00:00 UTC
        XCTAssertEqual(FeedParser.parseDate("Tue, 20 Oct 2026 07:00:00 +0000"), expected)
        XCTAssertEqual(FeedParser.parseDate("Tue, 20 Oct 2026 07:00:00 GMT"), expected)
        XCTAssertEqual(FeedParser.parseDate("2026-10-20T07:00:00Z"), expected)
        XCTAssertEqual(FeedParser.parseDate("2026-10-20T00:00:00-07:00"), expected)
        XCTAssertEqual(FeedParser.parseDate("2026-10-20T07:00:00.000Z"), expected)
        XCTAssertNil(FeedParser.parseDate("not a date"))
        XCTAssertNil(FeedParser.parseDate(" "))
    }
}

final class HostedSyncTests: XCTestCase {
    func testNormalizedBaseURLAddsScheme() {
        XCTAssertEqual(HostedSync.normalizedBaseURL("rss.example.com"), "https://rss.example.com")
        XCTAssertEqual(HostedSync.normalizedBaseURL("https://rss.example.com/"), "https://rss.example.com")
        XCTAssertEqual(HostedSync.normalizedBaseURL(" http://rss.example.com "), "http://rss.example.com")
    }

    /// Hosted feeds refresh through the account, never by feed URL.
    func testHostedFeedDetection() throws {
        // SwiftData models need a live container for their type.
        let container = try ModelContainer(for: Feed.self, Article.self, Chapter.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defer { _ = container }
        XCTAssertTrue(Feed(id: "miniflux:12", url: "https://a.example/feed", title: "A").isHosted)
        XCTAssertTrue(Feed(id: "greader:inoreader:feed/x", url: "", title: "B").isHosted)
        XCTAssertFalse(Feed(id: "https://c.example/feed", url: "https://c.example/feed", title: "C").isHosted)
    }
}

final class YouTubeServiceTests: XCTestCase {
    func testVideoIDFromWatchURL() {
        XCTAssertEqual(YouTubeService.videoID(from: "https://www.youtube.com/watch?v=abc123XYZ"), "abc123XYZ")
        XCTAssertEqual(YouTubeService.videoID(from: "https://youtu.be/abc123XYZ"), "abc123XYZ")
        XCTAssertNil(YouTubeService.videoID(from: "https://example.com/video"))
    }

    func testChaptersFromDescription() {
        let chapters = YouTubeService.chapters(fromDescription: "Intro line\n0:00 Start\n2:30 Middle\n1:02:00 End")
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[1].start, 150)
        XCTAssertEqual(chapters[2].start, 3720)
    }
}

final class HTMLTextTests: XCTestCase {
    func testStripsTagsAndBreaksParagraphs() {
        let text = HTMLText.plainText(from: "<p>One</p><p>Two &amp; three</p><script>junk</script>")
        XCTAssertEqual(text, "One\nTwo & three")
    }

    func testPreviewTruncates() {
        let long = String(repeating: "word ", count: 100)
        XCTAssertTrue(HTMLText.preview(from: long, maxChars: 20).hasSuffix("…"))
    }

    func testDecodesNumericAndNamedEntitiesOnce() {
        XCTAssertEqual(HTMLText.decodeEntities("It&#8217;s &#x2014; &rsquo;x&hellip; &amp;lt; &bogus; a & b"),
                       "It\u{2019}s \u{2014} \u{2019}x\u{2026} &lt; &bogus; a & b")
    }

    func testArticleBlocksKeepArticleAndDropPageChrome() {
        let page = """
        <html><head><title>T</title><script>var x = "<p>nope</p>";</script></head><body>
        <nav><ul><li><a href=/>Home</a></li><li><a href=/news>News, sport, and weather today</a></li></ul></nav>
        <header>Site name and a long tagline that is not article text at all</header>
        <div class="layout"><div class="article-body">
        <h2>Section heading</h2>
        <p>First paragraph of the article, long enough to count as real text, with commas, too.
        <p>Second paragraph, it&#8217;s also long enough to be read as real article text here.</p>
        <p>Yes.</p>
        <p>Advertisement</p>
        <div class="share-tools"><p>Share this article on every social network you can think of today</p></div>
        <ul><li><p>A list item with a nested paragraph inside it for the reader.</p></li></ul>
        <blockquote>Hey Jeff,<br><br>Quoted line two.</blockquote>
        </div>
        <aside><p>Sidebar paragraph that should never be read out as part of the article body text.</p></aside>
        </div>
        <footer><p>Copyright and a very long footer paragraph that should not be included in the text.</p></footer>
        </body></html>
        """
        let blocks = HTMLText.articleBlocks(fromPage: page)
        XCTAssertEqual(blocks.map(\.text), [
            "Section heading",
            "First paragraph of the article, long enough to count as real text, with commas, too.",
            "Second paragraph, it\u{2019}s also long enough to be read as real article text here.",
            "Yes.",
            "A list item with a nested paragraph inside it for the reader.",
            "Hey Jeff,",
            "Quoted line two.",
        ])
        XCTAssertEqual(blocks.map(\.isHeading), [true, false, false, false, false, false, false])
    }

    func testArticleBlocksKeepsSiblingContentDivs() {
        // Ars Technica splits one article across sibling content divs.
        func half(_ range: ClosedRange<Int>) -> String {
            range.map { "<p>Paragraph \($0) of real article text, long enough to be scored as text.</p>" }.joined()
        }
        let page = "<article><div class=\"post-content\">\(half(1...4))</div><div class=\"post-content\">\(half(5...8))</div></article>"
        let blocks = HTMLText.articleBlocks(fromPage: page)
        XCTAssertEqual(blocks.count, 8)
    }

    func testPlainTextBlocksSplitByLine() {
        XCTAssertEqual(HTMLText.blocks(fromPlainText: "One\n\nTwo").map(\.text), ["One", "Two"])
    }
}

final class OPMLServiceTests: XCTestCase {
    func testParsesNestedCategories() {
        let opml = """
        <opml version="1.0"><body>
        <outline text="Tech"><outline type="rss" text="Swift Blog" xmlUrl="https://swift.example.com/feed"/></outline>
        <outline type="rss" text="Loose" xmlUrl="https://loose.example.com/feed"/>
        </body></opml>
        """
        let feeds = OPMLService.parse(data: Data(opml.utf8))
        XCTAssertEqual(feeds.count, 2)
        XCTAssertEqual(feeds.first { $0.title == "Swift Blog" }?.category, "Tech")
        XCTAssertEqual(feeds.first { $0.title == "Loose" }?.category, "Uncategorized")
    }
}
