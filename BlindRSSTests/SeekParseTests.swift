// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import XCTest

final class SeekParseTests: XCTestCase {
    func testParsesAllForms() {
        XCTAssertEqual(AudioPlayer.parseJumpTime("90"), 90)
        XCTAssertEqual(AudioPlayer.parseJumpTime(" 90 "), 90)
        XCTAssertEqual(AudioPlayer.parseJumpTime("1:23"), 83)
        XCTAssertEqual(AudioPlayer.parseJumpTime("1:23:45"), 5025)
        XCTAssertEqual(AudioPlayer.parseJumpTime("0"), 0)
    }

    func testRejectsGarbage() {
        XCTAssertNil(AudioPlayer.parseJumpTime(""))
        XCTAssertNil(AudioPlayer.parseJumpTime("   "))
        XCTAssertNil(AudioPlayer.parseJumpTime("abc"))
        XCTAssertNil(AudioPlayer.parseJumpTime("1:2:3:4"))
        XCTAssertNil(AudioPlayer.parseJumpTime("-5"))
        XCTAssertNil(AudioPlayer.parseJumpTime("1::2"))
    }
}

final class ReportIssueTests: XCTestCase {
    func testIssueLinkCarriesTitleBodyAndVersion() {
        let url = ReportIssue.url(title: "Photo & video", details: "Line 1\nПривет", appLine: "BlindRSS for iOS 1.0 on iOS 27").absoluteString
        XCTAssertTrue(url.hasPrefix("https://github.com/serrebidev/BlindRSS-iOS/issues/new?title=Photo%20%26%20video&body=Line%201%0A%D0%9F"), url)
        XCTAssertTrue(url.hasSuffix("%0A---%0ABlindRSS%20for%20iOS%201.0%20on%20iOS%2027"), url)
        XCTAssertFalse(url.contains(" ") || url.contains("#"), url)
    }
}
