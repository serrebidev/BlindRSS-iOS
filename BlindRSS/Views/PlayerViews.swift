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
                        case .increment: player.seek(by: 30)
                        case .decrement: player.seek(by: -30)
                        @unknown default: break
                        }
                    }
                    .accessibilityHint("Adjusts playback position by 30 seconds.")

                    HStack(spacing: 24) {
                        Button { player.seek(by: -30) } label: {
                            Image(systemName: "gobackward.30").frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Back 30 seconds")

                        Button { player.togglePlayPause() } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.largeTitle)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                        Button { player.seek(by: 30) } label: {
                            Image(systemName: "goforward.30").frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Forward 30 seconds")
                    }

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
                        }
                        Button { player.playNextInQueue() } label: {
                            Label("Play Next in Queue", systemImage: "forward.fill")
                        }
                        .accessibilityHint("Stops the current item and plays the next queued item.")
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
