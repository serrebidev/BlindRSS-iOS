// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct BlindRSSApp: App {
    @State private var player = AudioPlayer()

    init() {
        // Google Cast discovery starts with the app (default media
        // receiver; no owner application id — see CastService).
        CastService.setup()
        CastService.player = player
    }
    @Environment(\.scenePhase) private var scenePhase
    /// Shared with background refresh, which runs without the window.
    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: Feed.self, Article.self, Category.self,
                                      Chapter.self, PlaybackState.self, DeletedArticle.self,
                                      SmartFolder.self, FilterRule.self, SavedSearch.self)
        } catch {
            fatalError("The library could not be opened: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(player)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            BackgroundRefresh.schedule()
            await BackgroundRefresh.run(container: container)
        }
    }
}

/// Refresh while the app is closed (iOS Background App Refresh). iOS picks
/// the moment: never sooner than the chosen interval, often later, and not
/// at all when Background App Refresh is off in Settings.
enum BackgroundRefresh {
    static let identifier = "org.serrebidev.BlindRSS.refresh"

    static func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        let interval = UserDefaults.standard.object(forKey: "refreshInterval") as? Double
            ?? LibraryStore.defaultRefreshInterval
        guard interval > 0 else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run(container: ModelContainer) async {
        let context = container.mainContext
        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        guard !feeds.isEmpty else { return }
        // New articles raise a notification when that setting is on.
        await LibraryStore().refreshAll(feeds: feeds, in: context, quiet: true)
    }
}
