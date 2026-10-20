// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import AVFoundation
import Foundation
import MediaPlayer

/// Podcast/video playback. The iOS counterpart of the desktop VLC player
/// (gui/player.py): play/pause, seek, speed, chapters, play queue, resume.
/// AVPlayer replaces VLC; AirPlay comes free via AVPlayer. Chromecast,
/// DLNA, equalizer, and silence skipping are Phase 2 (see AUDIT.md).
@MainActor
@Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentTitle = ""
    var rate: Float = 1.0 {
        didSet { if isPlaying { player.rate = rate } }
    }
    private(set) var queue: [Article] = []
    private(set) var currentArticle: Article?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?

    /// Called on natural end so the app can auto-advance the queue.
    var onPlaybackEnded: (() -> Void)?

    init() {
        configureSession()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in self?.currentTime = time.seconds.isFinite ? time.seconds : 0 }
        }
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.onPlaybackEnded?()
            }
        }
    }

    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(article: Article, resumeAt: TimeInterval = 0) {
        guard let media = article.mediaURL, let url = URL(string: media) else { return }
        currentArticle = article
        currentTitle = article.title
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .readyToPlay {
                    self.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                    if resumeAt > 0 {
                        self.seek(to: resumeAt)
                    }
                    self.player.rate = self.rate
                    self.isPlaying = true
                } else if item.status == .failed {
                    Announcer.announce("Playback failed. \(item.error?.localizedDescription ?? "")")
                }
            }
        }
        player.play()
        player.rate = rate
        isPlaying = true
        updateNowPlaying()
        Announcer.announce("Playing \(article.title).")
    }

    func togglePlayPause() {
        guard player.currentItem != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            Announcer.announce("Paused.")
        } else {
            player.play()
            player.rate = rate
            isPlaying = true
            Announcer.announce("Playing.")
        }
        updateNowPlaying()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        currentArticle = nil
        currentTitle = ""
        currentTime = 0
        duration = 0
    }

    func seek(to seconds: TimeInterval) {
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in self?.currentTime = clamped }
        }
    }

    func seek(by delta: TimeInterval) { seek(to: currentTime + delta) }

    func setRate(_ newRate: Float) {
        rate = min(3.0, max(0.5, newRate))
        Announcer.announce("Speed \(formattedRate).")
    }

    var formattedRate: String {
        let value = Double(rate)
        return value.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    var formattedPosition: String {
        "\(Self.formatTime(currentTime)) of \(Self.formatTime(duration))"
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: Queue (desktop Play Queue, core/shortcuts.py queue.*)

    func enqueue(_ article: Article) {
        guard !queue.contains(where: { $0.id == article.id }) else { return }
        queue.append(article)
        Announcer.announce("Added to play queue. \(queue.count) in queue.")
    }

    func dequeue(_ article: Article) {
        queue.removeAll { $0.id == article.id }
    }

    func playNextInQueue() {
        guard !queue.isEmpty else {
            Announcer.announce("Play queue is empty.")
            return
        }
        play(article: queue.removeFirst())
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = currentTitle
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
