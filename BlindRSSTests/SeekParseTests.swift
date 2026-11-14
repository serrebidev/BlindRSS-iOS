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
