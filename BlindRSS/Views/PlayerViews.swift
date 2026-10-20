// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftUI

/// Persistent mini player (desktop player bar). Progress and speed are
/// VoiceOver-adjustable: swipe up or down changes the value, and the value
/// is spoken in words (techniques: Adjustable Action, Accessibility Value).
struct MiniPlayerView: View {
    @Environment(AudioPlayer.self) private var player
    @State private var showingPlayer = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .accessibilityHint(player.isPlaying ? "Pauses playback." : "Resumes playback.")

            Button {
                showingPlayer = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTitle)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(player.formattedPosition)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(player.currentTitle)
            .accessibilityValue(player.formattedPosition)
            .accessibilityHint("Opens the full player.")

            Spacer()

            Button {
                player.seek(by: 30)
            } label: {
                Image(systemName: "goforward.30")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Forward 30 seconds")
        }
        .padding(.horizontal)
        .background(.bar)
        .sheet(isPresented: $showingPlayer) {
            PlayerView()
        }
    }
}

/// Full player sheet: seek, speed, chapters, queue.
/// Return of VoiceOver focus to the mini player is handled by the sheet's
/// onDismiss in MiniPlayerView's caller (technique: Focus Management).
struct PlayerView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("seekInterval") private var seekInterval = 30.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text(player.currentTitle)
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)

                    // Adjustable progress: VoiceOver swipe up/down seeks.
                    VStack {
                        ProgressView(value: player.currentTime,
                                     total: max(player.duration, 1))
                            .accessibilityHidden(true)
                        HStack {
                            Text(AudioPlayer.formatTime(player.currentTime))
                            Spacer()
                            Text(AudioPlayer.formatTime(player.duration))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Progress")
                    .accessibilityValue(player.formattedPosition)
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: player.seek(by: seekInterval)
                        case .decrement: player.seek(by: -seekInterval)
                        @unknown default: break
                        }
                    }
                    .accessibilityHint("Adjusts playback position by \(Int(seekInterval)) seconds.")

                    HStack(spacing: 24) {
                        Button { player.seek(by: -seekInterval) } label: {
                            Image(systemName: "gobackward.30").frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Back \(Int(seekInterval)) seconds")

                        Button { player.togglePlayPause() } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.largeTitle)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                        Button { player.seek(by: seekInterval) } label: {
                            Image(systemName: "goforward.30").frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Forward \(Int(seekInterval)) seconds")
                    }

                    // Volume (desktop volume slider, Ctrl+Up / Ctrl+Down).
                    VStack(alignment: .leading) {
                        Text("Volume \(Int(player.volume * 100)) percent")
                        Slider(value: Binding(get: { player.volume }, set: { player.volume = $0 }), in: 0...1)
                            .accessibilityLabel("Volume")
                            .accessibilityValue("\(Int(player.volume * 100)) percent")
                    }
                    .accessibilityElement(children: .combine)

                    // Speed presets (desktop Playback Speed submenu steps).
                    Menu {
                        ForEach(AudioPlayer.speedSteps, id: \.self) { step in
                            Button("\(step.formatted(.number.precision(.fractionLength(0...2))))×") {
                                player.setRate(step)
                            }
                        }
                    } label: {
                        Label("Speed Presets", systemImage: "speedometer")
                    }
                    .accessibilityHint("Sets playback speed directly.")

                    // Sleep timer.
                    Menu {
                        Button("Off") { player.sleepTimerSeconds = nil }
                        Button("15 minutes") { player.sleepTimerSeconds = 900 }
                        Button("30 minutes") { player.sleepTimerSeconds = 1800 }
                        Button("60 minutes") { player.sleepTimerSeconds = 3600 }
                        Button("End of episode") { player.sleepTimerSeconds = max(1, player.duration - player.currentTime) }
                    } label: {
                        Label("Sleep Timer", systemImage: "moon.zzz")
                    }
                    .accessibilityHint("Stops playback after the chosen time.")

                    AirPlayRouteView().frame(width: 44, height: 44)
                        .accessibilityLabel("AirPlay and output devices")

                    // Adjustable speed: VoiceOver swipe up/down changes rate.
                    Text("Speed \(player.formattedRate)")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Playback speed")
                        .accessibilityValue(player.formattedRate)
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: player.setRate(player.rate + 0.25)
                            case .decrement: player.setRate(player.rate - 0.25)
                            @unknown default: break
                            }
                        }
                        .accessibilityHint("Adjusts playback speed.")

                    if let article = player.currentArticle, !article.chapters.isEmpty {
                        Text("Chapters")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(article.chapters.sorted(by: { $0.start < $1.start })) { chapter in
                            Button { player.seek(to: chapter.start) } label: {
                                Label("\(AudioPlayer.formatTime(chapter.start)) \(chapter.title)", systemImage: "list.bullet")
                            }
                            .accessibilityHint("Moves playback to this chapter.")
                        }
                    }

                    if !player.queue.isEmpty {
                        Text("Play Queue")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(player.queue) { queued in
                            HStack {
                                Text(queued.title)
                                Spacer()
                                Button { player.dequeue(queued) } label: {
                                    Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44)
                                }
                                .accessibilityLabel("Remove \(queued.title) from queue")
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(queued.title)
                            .accessibilityHint("Shows queue actions.")
                            .accessibilityAction { player.dequeue(queued) } label: {
                                Label("Remove from Queue", systemImage: "minus.circle")
                            }
                            .accessibilityAction { player.play(article: queued) } label: {
                                Label("Play Now", systemImage: "play.fill")
                            }
                            .accessibilityAction { player.moveInQueue(queued, up: true) } label: {
                                Label("Move Up", systemImage: "arrow.up")
                            }
                            .accessibilityAction { player.moveInQueue(queued, up: false) } label: {
                                Label("Move Down", systemImage: "arrow.down")
                            }
                        }
                        Button { player.playNextInQueue() } label: {
                            Label("Play Next in Queue", systemImage: "forward.fill")
                        }
                        .accessibilityHint("Stops the current item and plays the next queued item.")
                        Button(role: .destructive) { player.clearQueue() } label: {
                            Label("Clear Queue", systemImage: "trash")
                        }
                        .accessibilityHint("Removes every item from the play queue.")
                    }
                }
                .padding()
            }
            .navigationTitle("Player")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
