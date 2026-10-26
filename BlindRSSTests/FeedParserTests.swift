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

// MARK: - 0.1.12 desktop-parity features

import Compression

final class ParityFeatureTests: XCTestCase {

    // MARK: Feed description

    func testChannelDescriptionBecomesFeedDescription() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
        <title>Described Pod</title><link>https://example.com</link>
        <description>All about examples</description>
        <item><title>Ep</title><link>https://example.com/1</link><guid>g1</guid>
        <description>Episode notes</description></item>
        </channel></rss>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8), sourceURL: URL(string: "https://example.com/feed.xml")!)
        XCTAssertEqual(feed.feedDescription, "All about examples")
        XCTAssertEqual(feed.entries.first?.summaryHTML, "Episode notes")
    }

    // MARK: Takeout

    func testTakeoutCSVParsing() {
        let csv = "Channel ID,Channel URL,Channel title\r\nUCabc123,https://www.youtube.com/channel/UCabc123,\"Chan, nel\"\r\nUCdef456,https://www.youtube.com/channel/UCdef456,Plain\n"
        let entries = TakeoutService.csvEntries(text: csv, idHeader: "channel id", titleHeader: "channel title",
                                                template: "https://www.youtube.com/feeds/videos.xml?channel_id={id}")
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.title, "Chan, nel")
        XCTAssertEqual(entries.first?.feedURL, "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc123")
    }

    func testTakeoutZIPRoundTrip() {
        let subscriptions = "Channel ID,Channel URL,Channel title\nUCabc123,https://www.youtube.com/channel/UCabc123,Chan\n"
        let playlists = "Playlist ID,Playlist title (original)\nPLxyz789,My List\n"
        let history = "<html><a href=\"https://www.youtube.com/channel/UChist999\">Watched</a></html>"
        let zip = Self.makeZIP(entries: [
            (name: "Takeout/YouTube and YouTube Music/subscriptions/subscriptions.csv", data: Data(subscriptions.utf8), deflate: false),
            (name: "Takeout/YouTube and YouTube Music/playlists/playlists.csv", data: Data(playlists.utf8), deflate: true),
            (name: "Takeout/YouTube and YouTube Music/history/watch-history.html", data: Data(history.utf8), deflate: false),
        ])
        let entries = TakeoutService.feedEntries(fromTakeout: zip)
        let urls = Set(entries.map(\.feedURL))
        XCTAssertTrue(urls.contains("https://www.youtube.com/feeds/videos.xml?channel_id=UCabc123"))
        XCTAssertTrue(urls.contains("https://www.youtube.com/feeds/videos.xml?playlist_id=PLxyz789"))
        XCTAssertTrue(urls.contains("https://www.youtube.com/feeds/videos.xml?channel_id=UChist999"))
    }

    // MARK: Directories

    func testDirectoryExtractors() {
        let fyyd = DirectorySearch.parseFyyd(Data(#"{"data":[{"title":"Pod A","author":"Ann","xmlURL":"https://a.example/feed.xml"}]}"#.utf8))
        XCTAssertEqual(fyyd.first?.url, "https://a.example/feed.xml")
        XCTAssertEqual(fyyd.first?.source, "fyyd")

        let podverse = DirectorySearch.parsePodverse(Data(#"[[{"title":"Pod B","feedUrls":[{"url":"https://b.example/feed.xml"}]}],1]"#.utf8))
        XCTAssertEqual(podverse.first?.url, "https://b.example/feed.xml")

        let feedly = DirectorySearch.parseFeedly(Data(#"{"results":[{"feedId":"feed/https://c.example/rss","title":"Blog C"}]}"#.utf8))
        XCTAssertEqual(feedly.first?.url, "https://c.example/rss")

        let newsblur = DirectorySearch.parseNewsBlur(Data(#"{"feeds":[{"value":"https://d.example/feed","label":"Blog D","tagline":"","num_subscribers":3}]}"#.utf8))
        XCTAssertEqual(newsblur.first?.url, "https://d.example/feed")

        let reddit = DirectorySearch.parseReddit(Data(#"{"data":{"children":[{"data":{"display_name":"swift","public_description":""}}]}}"#.utf8))
        XCTAssertEqual(reddit.first?.url, "https://www.reddit.com/r/swift/.rss")

        let lemmy = DirectorySearch.parseCommunities(
            Data(#"{"communities":[{"community":{"title":"Swift","name":"swift","actor_id":"https://lemmy.world/c/swift"}}]}"#.utf8), source: "Lemmy")
        XCTAssertEqual(lemmy.first?.url, "https://lemmy.world/feeds/c/swift.xml")

        let kbin = DirectorySearch.communityFeedURL(actorID: "https://kbin.example/m/swift")
        XCTAssertEqual(kbin, "https://kbin.example/m/swift/rss")

        let mastodon = DirectorySearch.parseMastodon(
            Data(#"{"accounts":[{"display_name":"Ann","url":"https://mastodon.social/@ann"}],"hashtags":[{"name":"swift"}]}"#.utf8),
            instance: "https://mastodon.social")
        XCTAssertEqual(Set(mastodon.map(\.url)),
                       Set(["https://mastodon.social/@ann.rss", "https://mastodon.social/tags/swift.rss"]))

        let bluesky = DirectorySearch.parseBluesky(Data(#"{"actors":[{"handle":"ann.bsky.social","displayName":"Ann"}]}"#.utf8))
        XCTAssertEqual(bluesky.first?.url, "https://bsky.app/profile/ann.bsky.social/rss")

        let news = DirectorySearch.constructedNewsResults(term: "space flight")
        XCTAssertEqual(news.count, 2)
        XCTAssertTrue(news[0].url.hasPrefix("https://news.google.com/rss/search?q=space"))
        XCTAssertTrue(news[1].url.contains("bing.com/news/search"))
    }

    func testGroupsIOAndFeedspotExtraction() {
        let groups = DirectorySearch.parseGroupsIO("<a href=\"/g/podcasts\">Podcast Group</a> <a href=\"https://groups.io/g/radio\">Radio</a>")
        XCTAssertEqual(Set(groups.map(\.url)),
                       Set(["https://groups.io/g/podcasts/rss", "https://groups.io/g/radio/rss"]))

        let html = "<h3 class=\"feed_heading\"><a href=\"https://rss.feedspot.com/x\">Cool Blog</a></h3><a class=\"ext\" href=\"https://cool.example/feed.xml\">Feed</a>"
        let feedspot = DirectorySearch.parseFeedspot(html)
        XCTAssertEqual(feedspot.first?.url, "https://cool.example/feed.xml")
        XCTAssertEqual(feedspot.first?.title, "Cool Blog")
    }

    // MARK: Social resolution

    func testSocialResolver() {
        XCTAssertEqual(SocialResolver.feedURL(forPageURL: "https://www.reddit.com/r/swift"),
                       "https://www.reddit.com/r/swift/.rss")
        XCTAssertEqual(SocialResolver.feedURL(forPageURL: "https://mastodon.social/@ann"),
                       "https://mastodon.social/@ann.rss")
        XCTAssertEqual(SocialResolver.feedURL(forPageURL: "https://bsky.app/profile/ann.bsky.social"),
                       "https://bsky.app/profile/ann.bsky.social/rss")
        XCTAssertEqual(SocialResolver.feedURL(forPageURL: "https://lemmy.world/c/swift"),
                       "https://lemmy.world/feeds/c/swift.xml")
        XCTAssertEqual(SocialResolver.feedURL(forPageURL: "https://groups.io/g/podcasts"),
                       "https://groups.io/g/podcasts/rss")
        XCTAssertEqual(SocialResolver.feedURL(forPageURL: "https://github.com/serrebidev/BlindRSS"),
                       "https://github.com/serrebidev/BlindRSS/releases.atom")
        XCTAssertEqual(SocialResolver.feedURL(forPageURL: "https://www.youtube.com/playlist?list=PLxyz"),
                       "https://www.youtube.com/feeds/videos.xml?playlist_id=PLxyz")
        XCTAssertEqual(SocialResolver.feedURL(forPageURL: "https://www.youtube.com/channel/UCabc1234567"),
                       "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc1234567")
        XCTAssertNil(SocialResolver.feedURL(forPageURL: "https://example.com/blog/post"))
        XCTAssertNil(SocialResolver.feedURL(forPageURL: "https://www.youtube.com/watch?v=abc"))
        XCTAssertTrue(SocialResolver.isYouTubeChannelPage("https://www.youtube.com/@SomeHandle"))
        XCTAssertFalse(SocialResolver.isYouTubeChannelPage("https://www.youtube.com/watch?v=abc"))
    }

    func testYouTubeChannelPageExtraction() {
        let html = "<script>var x = {\"channelId\":\"UCabcdefghij1234567890\",\"other\":1};</script>"
        XCTAssertEqual(SocialResolver.channelFeedURL(fromChannelPageHTML: html),
                       "https://www.youtube.com/feeds/videos.xml?channel_id=UCabcdefghij1234567890")
    }

    // MARK: YouTube transcript

    func testTranscriptJSON3() {
        let json = #"{"events":[{"segs":[{"utf8":"Hello "},{"utf8":"world."}]},{"segs":[{"utf8":"[Music]"}]},{"segs":[{"utf8":"Second line here."}]}]}"#
        let paragraphs = YouTubeService.parseTranscriptJSON3(Data(json.utf8))
        XCTAssertEqual(paragraphs, ["Hello world. Second line here."])
    }

    func testCaptionTrackPreference() {
        let manual = #"{"captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[{"baseUrl":"https://example.com/asr","kind":"asr"},{"baseUrl":"https://example.com/manual"}]}}}"#
        XCTAssertEqual(YouTubeService.captionTrackURL(fromPlayerResponse: Data(manual.utf8))?.absoluteString,
                       "https://example.com/manual&fmt=json3")
        let asrOnly = #"{"captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[{"baseUrl":"https://example.com/asr","kind":"asr"}]}}}"#
        XCTAssertEqual(YouTubeService.captionTrackURL(fromPlayerResponse: Data(asrOnly.utf8))?.absoluteString,
                       "https://example.com/asr&fmt=json3")
        XCTAssertNil(YouTubeService.captionTrackURL(fromPlayerResponse: Data("{}".utf8)))
    }

    // MARK: Filter pipeline

    func testFilterPipelineCombinesAndStops() {
        let article = Article(id: "a1", title: "Swift news", url: "https://example.com/1", content: "")
        let read = FilterRule(name: "r1", field: "title", contains: "swift", action: "markRead", position: 0)
        let favorite = FilterRule(name: "r2", field: "title", contains: "swift", action: "favorite", position: 1)
        let effects = FilterRule.pipeline(rules: [read, favorite], article: article)
        XCTAssertTrue(effects.markRead)
        XCTAssertTrue(effects.favorite)

        let stopper = FilterRule(name: "s", field: "title", contains: "swift", action: "markRead", position: 0)
        stopper.stop = true
        let afterStop = FilterRule.pipeline(rules: [stopper, favorite], article: article)
        XCTAssertTrue(afterStop.markRead)
        XCTAssertFalse(afterStop.favorite)

        // A move/label-only rule as the 0.1.12 form creates it: no legacy
        // action, so the fallback adds nothing.
        let mover = FilterRule(name: "m", field: "title", contains: "swift", action: "", position: 0)
        mover.moveCategory = "Tech"
        mover.labelCategory = "Swift"
        mover.skipNotification = true
        let moved = FilterRule.pipeline(rules: [mover], article: article)
        XCTAssertEqual(moved.moveCategory, "Tech")
        XCTAssertEqual(moved.labels, ["Swift"])
        XCTAssertTrue(moved.skipNotification)
        XCTAssertFalse(moved.markRead)

        // Rules stored before the multi-action fields fall back to the
        // legacy single action.
        let legacyDelete = FilterRule(name: "d", field: "title", contains: "swift", action: "delete", position: 0)
        XCTAssertTrue(FilterRule.pipeline(rules: [legacyDelete], article: article).delete)
    }

    func testSavedSearchMatching() {
        let search = SavedSearch(name: "Swift", term: "swift", position: 0)
        let byTitle = Article(id: "1", title: "Swift Weekly", url: "", content: "")
        let byAuthor = Article(id: "2", title: "Other", url: "", content: "", author: "Swift Fan")
        XCTAssertTrue(search.matches(byTitle, titlesOnly: true))
        XCTAssertFalse(search.matches(byAuthor, titlesOnly: true))
        XCTAssertTrue(search.matches(byAuthor, titlesOnly: false))
    }

    // MARK: Retention and reader presentation (UserDefaults-backed)

    @MainActor
    func testRetentionCutoff() {
        let defaults = UserDefaults.standard
        defaults.set(30, forKey: "retentionDays")
        let cutoff = LibraryStore.retentionCutoff
        XCTAssertNotNil(cutoff)
        if let cutoff {
            let age = Date().timeIntervalSince(cutoff)
            XCTAssertTrue(age > 29 * 86_400 && age < 31 * 86_400)
        }
        defaults.set(0, forKey: "retentionDays")
        XCTAssertNil(LibraryStore.retentionCutoff)
        defaults.removeObject(forKey: "retentionDays")
    }

    func testReaderPresentationToggles() {
        let defaults = UserDefaults.standard
        defer {
            for key in ["reader.bullets", "reader.quotes", "reader.links", "reader.altText"] {
                defaults.removeObject(forKey: key)
            }
        }
        let plain = HTMLText.plainText(from: "<ul><li>One</li></ul>")
        XCTAssertFalse(plain.contains("•"))

        defaults.set(true, forKey: "reader.bullets")
        XCTAssertTrue(HTMLText.plainText(from: "<ul><li>One</li></ul>").contains("• One"))

        defaults.set(true, forKey: "reader.quotes")
        XCTAssertTrue(HTMLText.plainText(from: "<blockquote>Wise words</blockquote>").contains("Quote: Wise words"))

        defaults.set(true, forKey: "reader.links")
        XCTAssertTrue(HTMLText.plainText(from: "<p>See <a href=\"https://example.com/x\">this page</a> now</p>")
            .contains("this page (https://example.com/x)"))

        defaults.set(true, forKey: "reader.altText")
        XCTAssertTrue(HTMLText.plainText(from: "<p><img src=\"x.png\" alt=\"A cat\"> After</p>").contains("[Image: A cat]"))
    }

    // MARK: ZIP construction for the Takeout round trip

    private static func makeZIP(entries: [(name: String, data: Data, deflate: Bool)]) -> Data {
        func u16(_ value: UInt16, _ data: inout Data) {
            data.append(UInt8(value & 0xFF)); data.append(UInt8(value >> 8))
        }
        func u32(_ value: UInt32, _ data: inout Data) {
            data.append(UInt8(value & 0xFF)); data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF)); data.append(UInt8(value >> 24))
        }
        var out = Data()
        var central = Data()
        for entry in entries {
            let nameBytes = [UInt8](entry.name.utf8)
            var payload = entry.data
            var method: UInt16 = 0
            if entry.deflate {
                let capacity = entry.data.count + 128
                var buffer = [UInt8](repeating: 0, count: capacity)
                let written = entry.data.withUnsafeBytes { raw in
                    buffer.withUnsafeMutableBufferPointer { destination in
                        compression_encode_buffer(destination.baseAddress!, capacity,
                                                  raw.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                                  entry.data.count, nil, COMPRESSION_ZLIB)
                    }
                }
                XCTAssertGreaterThan(written, 0)
                payload = Data(buffer[..<written])
                method = 8
            }
            let offset = out.count
            var local = Data()
            u32(0x0403_4B50, &local); u16(20, &local); u16(0, &local); u16(method, &local)
            u16(0, &local); u16(0, &local); u32(0, &local)
            u32(UInt32(payload.count), &local); u32(UInt32(entry.data.count), &local)
            u16(UInt16(nameBytes.count), &local); u16(0, &local)
            out.append(local); out.append(contentsOf: nameBytes); out.append(payload)
            var record = Data()
            u32(0x0201_4B50, &record); u16(20, &record); u16(20, &record); u16(0, &record); u16(method, &record)
            u16(0, &record); u16(0, &record); u32(0, &record)
            u32(UInt32(payload.count), &record); u32(UInt32(entry.data.count), &record)
            u16(UInt16(nameBytes.count), &record); u16(0, &record); u16(0, &record)
            u16(0, &record); u16(0, &record); u32(0, &record); u32(UInt32(offset), &record)
            central.append(record); central.append(contentsOf: nameBytes)
        }
        let centralOffset = out.count
        out.append(central)
        var end = Data()
        u32(0x0605_4B50, &end); u16(0, &end); u16(0, &end)
        u16(UInt16(entries.count), &end); u16(UInt16(entries.count), &end)
        u32(UInt32(central.count), &end); u32(UInt32(centralOffset), &end); u16(0, &end)
        out.append(end)
        return out
    }
}
