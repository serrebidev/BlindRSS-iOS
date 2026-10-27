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

// MARK: - Research round 0.1.13

final class ResearchRoundTests: XCTestCase {
    // SponsorBlock

    func testSponsorBlockParsesSegments() {
        let json = """
        [{"segment":[10.5,25.0],"category":"sponsor","UUID":"a","videoDuration":600},
         {"segment":[0,4.25],"category":"intro","UUID":"b","videoDuration":600},
         {"segment":[9,9],"category":"broken","UUID":"c","videoDuration":600}]
        """
        let segments = SponsorBlockService.parseSegments(Data(json.utf8))
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].category, "intro")
        XCTAssertEqual(segments[1].start, 10.5)
        XCTAssertEqual(SponsorBlockService.segment(at: 12, in: segments)?.category, "sponsor")
        XCTAssertNil(SponsorBlockService.segment(at: 24.9, in: segments))
        XCTAssertNil(SponsorBlockService.segment(at: 30, in: segments))
    }

    func testSponsorBlockNotFoundParsesEmpty() {
        XCTAssertTrue(SponsorBlockService.parseSegments(Data("Not Found".utf8)).isEmpty)
    }

    // Translation

    func testTranslateParsesLingvaAndLibreTranslate() {
        XCTAssertEqual(TranslateService.parseLingva(Data(#"{"translation":"Hola mundo","info":{"detectedSource":"en"}}"#.utf8)), "Hola mundo")
        XCTAssertEqual(TranslateService.parseLibreTranslate(Data(#"{"translatedText":"Bonjour"}"#.utf8)), "Bonjour")
        XCTAssertNil(TranslateService.parseLingva(Data(#"{"error":"nope"}"#.utf8)))
        XCTAssertNil(TranslateService.parseLibreTranslate(Data(#"{"error":"nope"}"#.utf8)))
    }

    func testTranslateChunksSplitLongText() {
        let paragraph = String(repeating: "Sentence one is here. ", count: 40)
        let text = (0..<5).map { _ in paragraph }.joined(separator: "\n")
        let chunks = TranslateService.chunks(of: text, maxLength: 300)
        XCTAssertGreaterThan(chunks.count, 3)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 300 })
        XCTAssertEqual(TranslateService.chunks(of: "short"), ["short"])
        XCTAssertEqual(TranslateService.chunks(of: "  "), [])
    }

    // Lemmy threads

    func testLemmyPostURLDetection() {
        let post = ForumService.lemmyPost(from: "https://lemmy.world/post/12345")
        XCTAssertEqual(post?.base, "https://lemmy.world")
        XCTAssertEqual(post?.id, "12345")
        XCTAssertNil(ForumService.lemmyPost(from: "https://lemmy.world/c/technology"))
        XCTAssertNil(ForumService.lemmyPost(from: "https://example.com/post/abc"))
    }

    func testLemmyParsesPostAndComments() {
        let postJSON = """
        {"post_view":{"post":{"id":7,"name":"A post","body":"Post body text",
        "url":"https://example.com/story"},"creator":{"name":"op"},"community":{"name":"tech"}}}
        """
        let parsed = ForumService.parsePost(Data(postJSON.utf8))
        XCTAssertEqual(parsed?.title, "A post")
        XCTAssertEqual(parsed?.body, "Post body text")

        let commentsJSON = """
        {"comments":[
          {"comment":{"id":1,"content":"Top level","path":"0.1"},"creator":{"name":"amy"}},
          {"comment":{"id":2,"content":"A reply","path":"0.1.2"},"creator":{"name":"bob"}},
          {"comment":{"id":3,"content":"Deep reply","path":"0.1.2.3"},"creator":{"name":"cy"}},
          {"comment":{"id":4,"content":"gone","path":"0.4","deleted":true},"creator":{"name":"dan"}}
        ]}
        """
        let comments = ForumService.parseComments(Data(commentsJSON.utf8))
        XCTAssertEqual(comments.count, 4)
        XCTAssertEqual(comments.map(\.depth), [0, 1, 2, 0])
        XCTAssertEqual(comments[3].text, "[deleted]")
        let thread = ForumService.Thread(title: "A post", body: "Post body text", comments: comments)
        let lines = ForumService.lines(for: thread)
        XCTAssertEqual(lines[0], "Post body text")
        XCTAssertEqual(lines[1], "Comment, amy: Top level")
        XCTAssertTrue(lines[2].contains("Reply, level 1, bob: A reply"))
    }

    // Awesome RSS catalogue

    func testAwesomeRSSMapsOPMLToResults() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="1.0"><body>
        <outline text="News" title="News">
          <outline type="rss" text="CBC Top Stories" title="CBC Top Stories" xmlUrl="https://example.com/cbc.xml"/>
        </outline>
        <outline type="rss" text="Solo Feed" title="Solo Feed" xmlUrl="https://example.com/solo.xml"/>
        </body></opml>
        """
        let entry = AwesomeRSSService.Entry(name: "Canada", path: "countries/with_category/Canada.opml", group: "Countries")
        let results = AwesomeRSSService.results(fromOPML: Data(opml.utf8), entry: entry)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "CBC Top Stories")
        XCTAssertEqual(results[0].website, "News")
        XCTAssertNil(results[1].website)
        XCTAssertEqual(results[0].source, "Awesome RSS: Canada")
        XCTAssertEqual(AwesomeRSSService.catalogue.count,
                       AwesomeRSSService.countries.count + AwesomeRSSService.topics.count)
        XCTAssertEqual(AwesomeRSSService.fileURL(for: entry)?.absoluteString.contains("Canada.opml"), true)
    }

    // YouTube video search (Innertube)

    func testYouTubeSearchParsesVideoRenderers() {
        let json = """
        {"contents":{"twoColumnSearchResultsRenderer":{"primaryContents":
        {"sectionListRenderer":{"contents":[{"itemSectionRenderer":{"contents":[
          {"videoRenderer":{"videoId":"abc123XYZ_-","title":{"runs":[{"text":"A Video"}]},
            "longBylineText":{"runs":[{"text":"A Channel"}]},
            "lengthText":{"simpleText":"12:34"},"publishedTimeText":{"simpleText":"3 days ago"}}},
          {"shelfRenderer":{"title":{"runs":[{"text":"Shelf"}]}}}
        ]}}]}}}}}
        """
        let results = YouTubeService.parseSearchResults(Data(json.utf8))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].videoID, "abc123XYZ_-")
        XCTAssertEqual(results[0].title, "A Video")
        XCTAssertEqual(results[0].channel, "A Channel")
        XCTAssertEqual(results[0].durationText, "12:34")
        XCTAssertEqual(results[0].watchURL, "https://www.youtube.com/watch?v=abc123XYZ_-")
    }

    // SoundCloud and Mixcloud subscription conversion

    func testSoundCloudProfileScrapesUserRSS() {
        XCTAssertTrue(SocialResolver.isSoundCloudProfile("https://soundcloud.com/someartist"))
        XCTAssertFalse(SocialResolver.isSoundCloudProfile("https://soundcloud.com/someartist/a-track"))
        let html = #"<html><meta content="soundcloud://sounds:1"><link href="https://soundcloud.com/x">urn soundcloud:users:9876543 end</html>"#
        XCTAssertEqual(SocialResolver.soundCloudFeedURL(fromProfileHTML: html),
                       "https://feeds.soundcloud.com/users/soundcloud:users:9876543/sounds.rss")
        XCTAssertNil(SocialResolver.soundCloudFeedURL(fromProfileHTML: "<html>no id</html>"))
    }

    func testMixcloudProfileConvertsToAPIList() {
        XCTAssertEqual(SocialResolver.feedURL(forPageURL: "https://www.mixcloud.com/someuser/"),
                       "https://api.mixcloud.com/someuser/cloudcasts/?limit=100")
    }

    func testMixcloudAPIParsesAsFeed() throws {
        let json = """
        {"data":[
          {"key":"/someuser/mix-one/","name":"Mix One","url":"https://www.mixcloud.com/someuser/mix-one/",
           "created_time":"2026-10-01T10:00:00Z","user":{"username":"someuser","name":"Some User"}},
          {"key":"/someuser/mix-two/","name":"Mix Two","url":"https://www.mixcloud.com/someuser/mix-two/",
           "created_time":"2026-10-20T10:00:00Z","user":{"username":"someuser","name":"Some User"}}
        ]}
        """
        let feed = try FeedParser.parse(data: Data(json.utf8),
                                        sourceURL: URL(string: "https://api.mixcloud.com/someuser/cloudcasts/?limit=100")!)
        XCTAssertEqual(feed.title, "Some User on Mixcloud")
        XCTAssertEqual(feed.entries.count, 2)
        XCTAssertEqual(feed.entries[0].guid, "/someuser/mix-one/")
        XCTAssertEqual(feed.entries[0].link, "https://www.mixcloud.com/someuser/mix-one/")
        XCTAssertNotNil(feed.entries[0].date)
        XCTAssertNil(feed.entries[0].mediaURL)
    }
}

// MARK: - YouTube account sign-in (0.1.14, SmartTube audit)

final class YouTubeAuthTests: XCTestCase {
    func testBaseJSURLFromTVPage() {
        let html = #"<script id="base-js" src="/s/_/kabuki/_/js/k=kabuki.base.en_US.X.O/am=AA/d=1/rs=ANjR/m=base"></script>"#
        XCTAssertEqual(YouTubeTVAuth.baseJSURL(fromTVPageHTML: html)?.absoluteString,
                       "https://www.youtube.com/s/_/kabuki/_/js/k=kabuki.base.en_US.X.O/am=AA/d=1/rs=ANjR/m=base")
        XCTAssertNil(YouTubeTVAuth.baseJSURL(fromTVPageHTML: "<html>no script</html>"))
    }

    func testClientCredentialsExtractionTakesFirstPair() {
        let js = """
        var a={clientId:"111111111111-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.apps.googleusercontent.com",clientSecret:"FIRSTSECRET1234567890"};
        var b={clientId:"222222222222-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.apps.googleusercontent.com",clientSecret:"SECONDSECRET"};
        """
        let credentials = YouTubeTVAuth.clientCredentials(fromBaseJS: js)
        XCTAssertEqual(credentials?.id, "111111111111-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.apps.googleusercontent.com")
        XCTAssertEqual(credentials?.secret, "FIRSTSECRET1234567890")
        XCTAssertNil(YouTubeTVAuth.clientCredentials(fromBaseJS: "no constants here"))
    }

    func testParseUserCode() {
        let json = """
        {"device_code":"long-device-code","user_code":"KSS-MXW-SVSG",
         "verification_url":"https://www.google.com/device","expires_in":1800,"interval":5}
        """
        let code = YouTubeTVAuth.parseUserCode(Data(json.utf8))
        XCTAssertEqual(code?.userCode, "KSS-MXW-SVSG")
        XCTAssertEqual(code?.deviceCode, "long-device-code")
        XCTAssertEqual(code?.interval, 5)
        XCTAssertNil(YouTubeTVAuth.parseUserCode(Data("{}".utf8)))
    }

    func testParseTokenOutcomes() {
        let success = #"{"access_token":"ya29.example","expires_in":3600,"refresh_token":"1//refresh","scope":"s","token_type":"Bearer"}"#
        XCTAssertEqual(YouTubeTVAuth.parseToken(Data(success.utf8)),
                       .success(accessToken: "ya29.example", refreshToken: "1//refresh", expiresIn: 3600))
        let refreshed = #"{"access_token":"ya29.new","expires_in":3599,"token_type":"Bearer"}"#
        XCTAssertEqual(YouTubeTVAuth.parseToken(Data(refreshed.utf8)),
                       .success(accessToken: "ya29.new", refreshToken: nil, expiresIn: 3599))
        XCTAssertEqual(YouTubeTVAuth.parseToken(Data(#"{"error":"authorization_pending"}"#.utf8)), .pending)
        XCTAssertEqual(YouTubeTVAuth.parseToken(Data(#"{"error":"slow_down"}"#.utf8)), .pending)
        XCTAssertEqual(YouTubeTVAuth.parseToken(Data(#"{"error":"access_denied"}"#.utf8)), .failed("access_denied"))
        XCTAssertEqual(YouTubeTVAuth.parseToken(Data(#"{"error":"expired_token"}"#.utf8)), .failed("expired_token"))
    }

    func testBrowseParsesGridVideoRenderers() {
        // TV browse shape: grid items with overlay durations.
        let json = """
        {
          "contents": {
            "tvBrowseRenderer": {
              "content": {
                "tvSurfaceContentRenderer": {
                  "content": {
                    "gridRenderer": {
                      "items": [
                        {
                          "gridVideoRenderer": {
                            "videoId": "grid1234567",
                            "title": {
                              "runs": [
                                {
                                  "text": "Grid Video"
                                }
                              ]
                            },
                            "shortBylineText": {
                              "runs": [
                                {
                                  "text": "Grid Channel"
                                }
                              ]
                            },
                            "publishedTimeText": {
                              "simpleText": "2 days ago"
                            },
                            "thumbnailOverlays": [
                              {
                                "thumbnailOverlayTimeStatusRenderer": {
                                  "text": {
                                    "simpleText": "8:12"
                                  }
                                }
                              }
                            ]
                          }
                        }
                      ]
                    }
                  }
                }
              }
            }
          }
        }
        """
        let results = YouTubeService.parseSearchResults(Data(json.utf8))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].videoID, "grid1234567")
        XCTAssertEqual(results[0].title, "Grid Video")
        XCTAssertEqual(results[0].channel, "Grid Channel")
        XCTAssertEqual(results[0].durationText, "8:12")
        XCTAssertEqual(results[0].publishedText, "2 days ago")
    }
}


/// Full-screen guard: iOS only runs an app at the device's native
/// resolution when the app declares a launch screen. Without one the
/// app is scaled into a legacy canvas and never fills the screen —
/// the iPhone 17 Pro letterboxing fixed in 0.1.15. If this test fails,
/// the launch screen declaration was lost; do not ship.
final class LaunchConfigurationTests: XCTestCase {
    func testAppDeclaresLaunchScreenForNativeFullScreen() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertTrue(info["UILaunchScreen"] != nil || info["UILaunchStoryboardName"] != nil,
                      "No launch screen declared: iOS will letterbox the app instead of using the full screen.")
    }
}


/// Full-text extraction across split containers (0.1.16). News bodies
/// routinely live in sibling containers — a standfirst block, body
/// sections in separate wrappers, promo boxes in between — and reading
/// only the single winning container silently dropped the rest, which
/// is how Al Jazeera articles arrived incomplete. These fixtures pin
/// the Readability-style sibling append and its junk gates.
final class FullTextExtractionTests: XCTestCase {
    private func extractedText(_ html: String) -> String {
        HTMLText.articleBlocks(fromPage: html).map(\.text).joined(separator: "\n")
    }

    func testSplitBodyAcrossSiblingContainersIsFullyRecovered() {
        let html = """
        <html><body>
        <div class="page-wrap">
          <div class="top-nav"><ul>
            <li><a href="https://example.com/1">World news section home page link</a></li>
            <li><a href="https://example.com/2">Politics coverage and analysis link</a></li>
            <li><a href="https://example.com/3">Business markets data and reports link</a></li>
            <li><a href="https://example.com/4">Culture arts books and film link text</a></li>
            <li><a href="https://example.com/5">Sport results fixtures and tables link</a></li>
            <li><a href="https://example.com/6">Weather forecast for your region link</a></li>
            <li><a href="https://example.com/7">Video reports and documentaries link</a></li>
            <li><a href="https://example.com/8">Live blogs and breaking news link text</a></li>
          </ul></div>
          <div class="standfirst"><p>Standfirst marker sentence: the council decision, announced late on Monday evening, ends months of speculation about the harbour project, its funding, and the people who depend on the water.</p></div>
          <div class="article-body-text">
            <p>Body paragraph one marker, which explains what the council actually decided on Monday, and why the vote mattered so much to the residents of the harbour district.</p>
            <p>Body paragraph two marker, with reaction from the harbour authority, local fishers, business owners along the quay, and the provincial government minister.</p>
            <p>Body paragraph three marker, covering the full cost of the project, the timeline for construction work, the detours planned for ferries, and the next public meeting.</p>
            <p>Body paragraph four marker, noting the opposition response in the chamber, the legal challenge that may follow the vote, and what the mayor promised happens now.</p>
            <p>Body paragraph five marker, returning to the crews who work on the water every morning, and what the decision means for their boats, their buyers, and their season.</p>
          </div>
          <div class="promo-box"><p>Promo marker sentence: subscribe today for unlimited access to every story, every podcast, and the complete searchable archive of the paper, forever.</p></div>
          <div class="article-body-text">
            <p>Body paragraph six marker, closing the story with the date of the final vote, the margin recorded in the chamber, and the reaction from the public gallery.</p>
            <p>Body paragraph seven marker, an editor note explaining how the reporting was done, who was interviewed for the story, and how readers can respond to it.</p>
          </div>
        </div>
        </body></html>
        """
        let text = extractedText(html)
        XCTAssertTrue(text.contains("Standfirst marker sentence"), "standfirst sibling was dropped")
        XCTAssertTrue(text.contains("Body paragraph one marker"))
        XCTAssertTrue(text.contains("Body paragraph five marker"))
        XCTAssertTrue(text.contains("Body paragraph six marker"), "second body container was dropped")
        XCTAssertTrue(text.contains("Body paragraph seven marker"))
        XCTAssertFalse(text.contains("Promo marker sentence"), "promo sibling leaked into the article")
        XCTAssertFalse(text.contains("World news section home page link"), "navigation leaked into the article")
        let standfirst = text.range(of: "Standfirst marker sentence")!.lowerBound
        let firstBody = text.range(of: "Body paragraph one marker")!.lowerBound
        let lastBody = text.range(of: "Body paragraph seven marker")!.lowerBound
        XCTAssertTrue(standfirst < firstBody && firstBody < lastBody, "blocks out of document order")
    }

    func testSingleContainerArticleStillExtracts() {
        let html = """
        <html><body>
        <div class="site-header"><ul><li><a href="https://example.com/nav">Header navigation link label</a></li></ul></div>
        <main id="main-content-area"><div class="container container--article">
        <div class="wysiwyg wysiwyg--all-content">
        <p>Wysiwyg paragraph one marker, the opening of a wire story about the court ruling, with the judge quoted directly in the second sentence of the report.</p>
        <p>Wysiwyg paragraph two marker, adding the background of the case, the earlier hearings held in the spring, and the arguments made by both legal teams.</p>
        <p>Wysiwyg paragraph three marker, ending the story with the reaction from the family, the statement from the department, and the date of the appeal.</p>
        </div>
        </div></main>
        <div class="footer-block"><p>Footer marker sentence with the copyright line, the company registration details, and a long list of office addresses around the world.</p></div>
        </body></html>
        """
        let text = extractedText(html)
        XCTAssertTrue(text.contains("Wysiwyg paragraph one marker"))
        XCTAssertTrue(text.contains("Wysiwyg paragraph two marker"))
        XCTAssertTrue(text.contains("Wysiwyg paragraph three marker"))
        XCTAssertFalse(text.contains("Footer marker sentence"))
        XCTAssertGreaterThan(text.count, 300)
    }

    func testParagraphOutsideInnerWrapperIsNotCut() {
        // The old tightest-inner step replaced the winner with an inner
        // wrapper holding 75 percent of the text and lost the rest.
        let html = """
        <html><body>
        <div class="article-body">
          <div class="inner-wrap">
            <p>Inner paragraph one marker, setting out the announcement from the ministry, the figures released with it, and the immediate market reaction.</p>
            <p>Inner paragraph two marker, with the detail of the programme, the regions included in the first phase, and the eligibility rules for applicants.</p>
            <p>Inner paragraph three marker, quoting the critics of the scheme, the unions representing the workers, and the audit office that reviewed it.</p>
          </div>
          <p>Closing paragraph marker, the part of the story that used to vanish, summing up what changes on the first of the month and who to contact.</p>
        </div>
        </body></html>
        """
        let text = extractedText(html)
        XCTAssertTrue(text.contains("Inner paragraph one marker"))
        XCTAssertTrue(text.contains("Inner paragraph three marker"))
        XCTAssertTrue(text.contains("Closing paragraph marker"), "text outside the inner wrapper was cut")
    }
}

/// Video pages (0.1.18): a news video page has only a caption, so the
/// video is found for transcription and playback.
final class VideoPageTests: XCTestCase {
    func testPicksSmallestMP4FromEscapedArcStreams() {
        // Arc XP (The Globe and Mail) escapes slashes in its JSON.
        let html = "<script>Fusion.globalContent={\"streams\":["
            + "{\"stream_type\":\"ts\",\"url\":\"https:\\/\\/cdn.x\\/v\\/master.m3u8\"},"
            + "{\"stream_type\":\"mp4\",\"url\":\"https:\\/\\/cdn.x\\/v\\/file_1920x1080-5400.mp4\"},"
            + "{\"stream_type\":\"mp4\",\"url\":\"https:\\/\\/cdn.x\\/v\\/file_320x180-160.mp4\"}]}</script>"
        XCTAssertEqual(HTMLText.pageVideoURL(fromPage: html)?.absoluteString, "https://cdn.x/v/file_320x180-160.mp4")
    }

    func testFallsBackToHLSAndFindsNothingOnTextPages() {
        XCTAssertEqual(HTMLText.pageVideoURL(fromPage: "<video src=\"https://x.com/a/master.m3u8\"></video>")?.absoluteString,
                       "https://x.com/a/master.m3u8")
        XCTAssertNil(HTMLText.pageVideoURL(fromPage: "<article><p>Only words here.</p></article>"))
    }

    func testPageLanguageAndTranscriptParagraphs() {
        XCTAssertEqual(HTMLText.pageLanguage(fromPage: "<!doctype html><html class=\"x\" lang=\"en-CA\">"), "en-CA")
        let paragraphs = HTMLText.paragraphs(fromPhrases: Array(repeating: "Trade talks moved forward today.", count: 30), target: 200)
        XCTAssertGreaterThan(paragraphs.count, 1)
        XCTAssertTrue(paragraphs.allSatisfy { $0.text.hasSuffix(".") && !$0.isHeading })
    }
}

/// Apple Intelligence (0.1.17): the pure parts around the model calls.
final class AppleIntelligenceTests: XCTestCase {
    func testCleanOutputDropsMarkdownForVoiceOver() {
        let raw = "## Summary\n- **First** point\n\n* Second __point__\n• Third\n1. Numbered stays"
        XCTAssertEqual(AppleIntelligence.cleanOutput(raw),
                       "Summary\nFirst point\nSecond point\nThird\n1. Numbered stays")
    }

    func testEmptyNoteDetection() {
        XCTAssertTrue(AppleIntelligence.isEmptyNote("NONE"))
        XCTAssertTrue(AppleIntelligence.isEmptyNote(" none. "))
        XCTAssertTrue(AppleIntelligence.isEmptyNote(""))
        XCTAssertFalse(AppleIntelligence.isEmptyNote("The bridge closed on Monday."))
    }

    func testBriefingTextCapsArticlesAndSnippets() {
        let items = (1...5).map { (title: "Title \($0)", feed: $0 == 1 ? "" : "Feed", snippet: String(repeating: "x", count: 300)) }
        let text = AppleIntelligence.briefingText(for: items, limit: 3, snippetLength: 10)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "Title 1. xxxxxxxxxx")
        XCTAssertEqual(lines[1], "Feed: Title 2. xxxxxxxxxx")
    }

    func testVisualSearchRelevanceCountsSharedWords() {
        XCTAssertEqual(AppleIntelligence.relevance(of: "Golden Gate Bridge closes for repairs", to: ["Golden Gate Bridge"]), 3)
        XCTAssertEqual(AppleIntelligence.relevance(of: "A cat naps", to: ["dog"]), 0)
        // Short words ("a", "of") never count as a match.
        XCTAssertEqual(AppleIntelligence.relevance(of: "A day of rain", to: ["a", "of"]), 0)
    }

    func testPromptsCarryTheQuestionAndTitle() {
        XCTAssertTrue(AppleIntelligence.notesPrompt(for: .question("Who won?"), chunk: "text").contains("Who won?"))
        XCTAssertTrue(AppleIntelligence.finalPrompt(for: .summary, title: "Headline", text: "Body").contains("Title: Headline"))
        XCTAssertEqual(AppleIntelligence.Request.keyPoints.heading, "Key Points")
    }

    func testImageReferencesResolveSkipTrackersAndDuplicates() {
        let html = "<p><img src='/a.jpg' alt='A &amp; B'>"
            + "<img data-src=\"https://cdn.x/b.png\" src=\"data:image/gif;base64,AAA\">"
            + "<img src=\"https://t.x/p.gif\" width=\"1\" height=\"1\"><IMG SRC=\"/a.jpg\">"
            + "<img src=\"//cdn.x/c.webp\"></p>"
        let refs = AppleIntelligence.imageReferences(inHTML: html, baseURL: URL(string: "https://site.com/news/story"))
        XCTAssertEqual(refs.map(\.url.absoluteString), ["https://site.com/a.jpg", "https://cdn.x/b.png", "https://cdn.x/c.webp"])
        XCTAssertEqual(refs.first?.alt, "A & B")
        // Without the page address, relative sources are skipped and
        // absolute ones still count toward the limit.
        XCTAssertEqual(AppleIntelligence.imageReferences(inHTML: html, baseURL: nil, limit: 1).map(\.url.absoluteString),
                       ["https://cdn.x/b.png"])
    }

    /// iOS 27 features fail with a spoken message, never a crash, when
    /// the model cannot run (the test simulator has none).
    func testLibraryQuestionsAndImageDescriptionsFailCleanly() async {
        guard !AppleIntelligence.status.isAvailable else { return }
        do {
            _ = try await AppleIntelligence.askLibrary("What is new?")
            XCTFail("askLibrary should throw without a model")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        do {
            _ = try await AppleIntelligence.describeImages(html: "<img src=\"https://x.com/a.jpg\">", pageURL: "https://x.com/")
            XCTFail("describeImages should throw without a model")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    /// The test simulator has no Apple Intelligence model: every request
    /// must fail with the spoken status message, never crash or hang.
    func testUnavailableModelFailsWithStatusMessage() async {
        let status = AppleIntelligence.status
        XCTAssertFalse(status.message.isEmpty)
        guard !status.isAvailable else { return }
        do {
            _ = try await AppleIntelligence.run(.summary, title: "T", text: "Some text.")
            XCTFail("run should throw when the model is unavailable")
        } catch {
            XCTAssertEqual(error.localizedDescription, status.message)
        }
    }
}


/// Private Cloud Compute entitlement probe (0.1.19): the PCC model is
/// never attempted on a build whose provisioning profile lacks the
/// entitlement — without it, requests error, hang, or rate-limit in
/// ways indistinguishable from a dead feature.
final class PrivateCloudEntitlementTests: XCTestCase {
    func testProfileWithEntitlementGrants() {
        let profile = """
        <key>Entitlements</key><dict>
        <key>application-identifier</key><string>TEAM.org.serrebidev.BlindRSS</string>
        <key>com.apple.developer.private-cloud-compute</key><true/>
        </dict>
        """
        XCTAssertTrue(AppleIntelligence.profileGrantsPrivateCloud(profile))
    }

    func testDevelopmentProfileDoesNotGrant() {
        let profile = """
        <key>Entitlements</key><dict>
        <key>application-identifier</key><string>TEAM.org.serrebidev.BlindRSS</string>
        <key>get-task-allow</key><true/>
        </dict>
        """
        XCTAssertFalse(AppleIntelligence.profileGrantsPrivateCloud(profile))
        XCTAssertFalse(AppleIntelligence.profileGrantsPrivateCloud(""))
    }
}
