// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftData
import SwiftUI

@main
struct BlindRSSApp: App {
    @State private var player = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(player)
        }
        .modelContainer(for: [Feed.self, Article.self, Category.self,
                              Chapter.self, PlaybackState.self, DeletedArticle.self,
                              SmartFolder.self, FilterRule.self])
    }
}
