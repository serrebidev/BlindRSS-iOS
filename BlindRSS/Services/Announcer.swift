// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import UIKit

/// VoiceOver announcements for state changes a blind user cannot see.
/// Technique: Accessibility Notifications (ios-swiftui-accessibility-techniques).
/// Desktop equivalent: core/screen_reader_announce.py.
enum Announcer {
    /// Spoken update that does not move focus (refresh counts, deletions).
    static func announce(_ message: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// Whole-screen change: focus moves to the new screen's first element.
    static func screenChanged(to element: Any? = nil) {
        UIAccessibility.post(notification: .screenChanged, argument: element)
    }

    /// Partial change: focus moves within the current screen.
    static func layoutChanged(to element: Any? = nil) {
        UIAccessibility.post(notification: .layoutChanged, argument: element)
    }
}
