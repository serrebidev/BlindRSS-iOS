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
    /// Called with the finished episode so the app can mark it read.
    var onArticleFinished: ((Article) -> Void)?
    /// Resume support, wired to SwiftData PlaybackState by the app:
    /// provider returns (saved position, duration); saver persists progress.
    var resumeProvider: ((String) -> (position: TimeInterval, duration: TimeInterval?)?)?
    var positionSaver: ((String, TimeInterval, TimeInterval?, Bool, String?) -> Void)?
    /// Sleep timer: stops playback after this many seconds, if set.
    var sleepTimerSeconds: TimeInterval? {
        didSet { scheduleSleepTimer() }
    }
    var volume: Float = 0.85 {
        didSet { player.volume = volume }
    }
    private var sleepTask: Task<Void, Never>?
    private var lastSavedPosition: TimeInterval = 0

    /// Desktop speed steps (Playback Speed submenu).
    static let speedSteps: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    init() {
        configureSession()
        configureRemoteCommands()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                // Desktop resume_save_interval_s is 15: persist progress.
                if let article = self.currentArticle,
                   abs(self.currentTime - self.lastSavedPosition) >= 15 {
                    self.lastSavedPosition = self.currentTime
                    self.positionSaver?(article.id, self.currentTime,
                                        self.duration > 0 ? self.duration : nil, false, article.title)
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = false
                self.saveProgress(completed: true)
                if let finished = self.currentArticle {
                    self.onArticleFinished?(finished)
                }
                // Auto-advance: play the next queued episode, if any.
                if !self.queue.isEmpty {
                    self.playNextInQueue()
                } else {
                    self.onPlaybackEnded?()
                }
            }
        }
    }

    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.volume = volume
    }

    /// Lock screen, headphones, and CarPlay controls (desktop media keys).
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.togglePlayPause() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.togglePlayPause() } }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNextInQueue() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seek(to: 0) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seek(by: 30) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [30]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seek(by: -30) }
            return .success
        }
    }

    private func scheduleSleepTimer() {
        sleepTask?.cancel()
        guard let seconds = sleepTimerSeconds, seconds > 0 else { return }
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.stop()
                Announcer.announce("Sleep timer finished. Playback stopped.")
            }
        }
        Announcer.announce("Sleep timer set for \(Int(seconds / 60)) minutes.")
    }

    /// Saves progress and marks completion inside the last minute as done.
    func saveProgress(completed: Bool = false) {
        guard let article = currentArticle else { return }
        let finished = completed || (duration > 0 && duration - currentTime < 60)
        positionSaver?(article.id, finished ? 0 : currentTime,
                       duration > 0 ? duration : nil, finished, article.title)
    }

    func play(article: Article, resumeAt: TimeInterval = 0) {
        saveProgress()
        // Resume where the listener left off (desktop resume_playback),
        // unless the caller asked for an explicit position.
        var start = resumeAt
        if start == 0, let saved = resumeProvider?(article.id), saved.position > 0 {
            start = PodcastService.resumePosition(saved: saved.position, duration: saved.duration)
            if start > 0 { Announcer.announce("Resuming at \(Self.formatTime(start)).") }
        }
        lastSavedPosition = start
        // Downloaded episodes play from disk (offline, no network).
        if let local = DownloadService.localURL(for: article) {
            playURL(local, article: article, resumeAt: start)
            return
        }
        guard let media = article.mediaURL, let url = URL(string: media) else { return }
        playURL(url, article: article, resumeAt: start)
    }

    private func playURL(_ url: URL, article: Article, resumeAt: TimeInterval = 0) {
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
            saveProgress()
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
        persistQueue()
        Announcer.announce("Added to play queue. \(queue.count) in queue.")
    }

    func dequeue(_ article: Article) {
        queue.removeAll { $0.id == article.id }
        persistQueue()
    }

    func moveInQueue(_ article: Article, up: Bool) {
        guard let index = queue.firstIndex(where: { $0.id == article.id }) else { return }
        let target = up ? index - 1 : index + 1
        guard queue.indices.contains(target) else { return }
        queue.swapAt(index, target)
        persistQueue()
    }

    func clearQueue() {
        queue.removeAll()
        persistQueue()
        Announcer.announce("Play queue cleared.")
    }

    /// The queue survives restarts (desktop Play Queue): ids are persisted
    /// and resolved back to articles by the app on launch.
    private func persistQueue() {
        UserDefaults.standard.set(queue.map(\.id), forKey: "playQueue.ids")
    }

    func restoreQueue(articles: [Article]) {
        let ids = UserDefaults.standard.stringArray(forKey: "playQueue.ids") ?? []
        let byID = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
        queue = ids.compactMap { byID[$0] }
    }

    static var persistedQueueIDs: [String] {
        UserDefaults.standard.stringArray(forKey: "playQueue.ids") ?? []
    }

    func playNextInQueue() {
        guard !queue.isEmpty else {
            Announcer.announce("Play queue is empty.")
            return
        }
        let next = queue.removeFirst()
        persistQueue()
        play(article: next)
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
