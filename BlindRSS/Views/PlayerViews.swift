// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftUI
import UIKit

/// The podcast player: a mini player bar with every desktop player control
/// (gui/player.py), so playback never takes over the screen. Desktop
/// controls map to: position slider, back and forward, Play/Pause, Stop,
/// Playback Speed, Chapters (with previous, next, and chapter link), Cast
/// (AirPlay), Volume, and the Play Queue commands. Progress, speed, and
/// chapters are VoiceOver-adjustable: swipe up or down changes the value,
/// and the value is spoken in words (techniques: Adjustable Action,
/// Accessibility Value).
struct MiniPlayerView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.openURL) private var openURL
    @AppStorage("seekInterval") private var seekInterval = 30.0
    @State private var showingQueue = false
    /// Slider position while dragging; seeking every drag tick stalls AVPlayer.
    @State private var scrubTime: Double?

    var body: some View {
        let chapters = player.chapters
        let chapterIndex = player.chapterIndex(in: chapters)
        let chapterTitle = chapterIndex.map { chapters[$0].title }
        let seconds = Int(seekInterval)
        VStack(spacing: 2) {
            // Title and position (desktop title label, slider, and time).
            VStack(alignment: .leading, spacing: 0) {
                Text(player.currentTitle)
                    .font(.subheadline)
                    .lineLimit(1)
                Slider(value: Binding(get: { scrubTime ?? min(player.currentTime, max(player.duration, 1)) },
                                      set: { scrubTime = $0 }),
                       in: 0...max(player.duration, 1)) { editing in
                    if !editing, let scrubTime {
                        player.seek(to: scrubTime)
                        self.scrubTime = nil
                    }
                }
                HStack {
                    Text(AudioPlayer.formatTime(player.currentTime))
                    Spacer()
                    if let chapterTitle {
                        Text(chapterTitle).lineLimit(1)
                        Spacer()
                    }
                    Text(AudioPlayer.formatTime(player.duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(player.currentTitle)
            .accessibilityValue(chapterTitle.map { "\(player.formattedPosition), chapter \($0)" } ?? player.formattedPosition)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: player.seek(by: seekInterval)
                case .decrement: player.seek(by: -seekInterval)
                @unknown default: break
                }
            }
            .accessibilityHint("Adjusts playback position by \(seconds) seconds.")

            HStack(spacing: 0) {
                controlButton("Back \(seconds) seconds", systemImage: symbol("gobackward", seconds)) {
                    player.seek(by: -seekInterval)
                }
                controlButton(player.isPlaying ? "Pause" : "Play",
                              systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
                    player.togglePlayPause()
                }
                controlButton("Forward \(seconds) seconds", systemImage: symbol("goforward", seconds)) {
                    player.seek(by: seekInterval)
                }
                controlButton("Stop", systemImage: "stop.fill") {
                    player.stop()
                    Announcer.announce("Stopped.")
                }

                Menu {
                    Button { player.changeRate(by: 0.1) } label: { Label("Faster", systemImage: "hare") }
                    Button { player.changeRate(by: -0.1) } label: { Label("Slower", systemImage: "tortoise") }
                    Button { player.setRate(1) } label: { Label("Normal Speed", systemImage: "arrow.uturn.backward") }
                    Section("Presets") {
                        ForEach(AudioPlayer.speedSteps, id: \.self) { step in
                            Button { player.setRate(step) } label: {
                                let text = step.formatted(.number.precision(.fractionLength(0...2))) + "×"
                                if step == player.rate { Label(text, systemImage: "checkmark") } else { Text(text) }
                            }
                        }
                    }
                } label: {
                    Text(player.formattedRate)
                        .font(.footnote.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel("Playback speed")
                .accessibilityValue(player.formattedRate)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: player.changeRate(by: 0.1)
                    case .decrement: player.changeRate(by: -0.1)
                    @unknown default: break
                    }
                }
                .accessibilityHint("Opens speed choices. Adjusts speed by a tenth.")

                Menu {
                    Button { player.jumpChapter(by: -1) } label: { Label("Previous Chapter", systemImage: "backward.end") }
                    Button { player.jumpChapter(by: 1) } label: { Label("Next Chapter", systemImage: "forward.end") }
                    if let chapterIndex, let href = chapters[chapterIndex].href, let url = URL(string: href) {
                        Button { openURL(url) } label: { Label("Open Chapter Link", systemImage: "link") }
                    }
                    Section("Chapters") {
                        ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                            Button { player.seek(to: chapter.start) } label: {
                                let text = "\(AudioPlayer.formatTime(chapter.start)) \(chapter.title)"
                                if index == chapterIndex { Label(text, systemImage: "checkmark") } else { Text(text) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(chapters.isEmpty)
                .accessibilityLabel("Chapters")
                .accessibilityValue(chapterTitle ?? (chapters.isEmpty ? "None" : "Before the first chapter"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: player.jumpChapter(by: 1)
                    case .decrement: player.jumpChapter(by: -1)
                    @unknown default: break
                    }
                }
                .accessibilityHint("Opens the chapter list. Moves to the next or previous chapter.")

                // Desktop Cast button: AirPlay covers casting on iOS.
                AirPlayRouteView()
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel("AirPlay and output devices")

                Menu {
                    Section("Volume \(Int((player.volume * 100).rounded())) percent") {
                        Button { player.adjustVolume(by: 0.05) } label: { Label("Volume Up", systemImage: "speaker.wave.3") }
                        Button { player.adjustVolume(by: -0.05) } label: { Label("Volume Down", systemImage: "speaker.wave.1") }
                    }
                    Section("Play Queue, \(player.queue.count) items") {
                        Button { player.playNextInQueue() } label: { Label("Play Next in Queue", systemImage: "forward.fill") }
                        Button { player.playPreviousInQueue() } label: { Label("Play Previous in Queue", systemImage: "backward.fill") }
                        Button { showingQueue = true } label: { Label("Open Play Queue", systemImage: "list.number") }
                    }
                    Menu {
                        Button("Off") { player.sleepTimerSeconds = nil }
                        Button("15 minutes") { player.sleepTimerSeconds = 900 }
                        Button("30 minutes") { player.sleepTimerSeconds = 1800 }
                        Button("60 minutes") { player.sleepTimerSeconds = 3600 }
                        Button("End of episode") { player.sleepTimerSeconds = max(1, player.duration - player.currentTime) }
                    } label: {
                        Label("Sleep Timer", systemImage: "moon.zzz")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel("More player controls")
                .accessibilityHint("Volume, play queue, and sleep timer.")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
        .sheet(isPresented: $showingQueue) {
            PlayQueueView()
        }
    }

    private func controlButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(label)
    }

    /// "gobackward.30" when that symbol exists, else the plain arrow.
    private func symbol(_ base: String, _ seconds: Int) -> String {
        let named = "\(base).\(seconds)"
        return UIImage(systemName: named) != nil ? named : base
    }
}

/// Play Queue (desktop Open Play Queue, Ctrl+Shift+C). Each row's actions
/// are offered as touch swipes and as VoiceOver actions alike.
struct PlayQueueView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if player.queue.isEmpty {
                    ContentUnavailableView("Play Queue Is Empty", systemImage: "list.number",
                                           description: Text("Add episodes with the Add to Play Queue action."))
                } else {
                    List(player.queue) { queued in
                        Text(queued.title)
                            .frame(minHeight: 44, alignment: .leading)
                            .swipeActions(edge: .leading) {
                                Button { player.play(article: queued); player.dequeue(queued) } label: {
                                    Label("Play Now", systemImage: "play.fill")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { player.dequeue(queued) } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                            .accessibilityHint("Shows queue actions.")
                            .accessibilityAction { player.play(article: queued); player.dequeue(queued) } label: {
                                Label("Play Now", systemImage: "play.fill")
                            }
                            .accessibilityAction { player.dequeue(queued) } label: {
                                Label("Remove from Queue", systemImage: "minus.circle")
                            }
                            .accessibilityAction { player.moveInQueue(queued, up: true) } label: {
                                Label("Move Up", systemImage: "arrow.up")
                            }
                            .accessibilityAction { player.moveInQueue(queued, up: false) } label: {
                                Label("Move Down", systemImage: "arrow.down")
                            }
                    }
                }
            }
            .navigationTitle("Play Queue")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !player.queue.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear Queue", role: .destructive) { player.clearQueue() }
                            .accessibilityHint("Removes every item from the play queue.")
                    }
                }
            }
        }
    }
}
