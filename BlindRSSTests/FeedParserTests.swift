// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import XCTest
@testable import BlindRSS

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
