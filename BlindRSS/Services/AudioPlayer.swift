// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import AVFoundation
import Foundation
import MediaPlayer

/// Podcast/video playback. The iOS counterpart of the desktop VLC player
/// (gui/player.py): play/pause, seek, speed, chapters, play queue, resume.
/// AVPlayer replaces VLC; AirPlay comes free via AVPlayer. The equalizer
/// and silence skipping run in AudioProcessor, a tap in AVPlayer's audio
/// pipeline, so streams and downloads both get them. Chromecast and DLNA
/// are Phase 2 (see AUDIT.md).
@MainActor
@Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentTitle = ""
    var rate: Float = 1.0 {
        didSet { if isPlaying { applyRate() } }
    }
    /// Desktop equalizer, saved like the desktop config's "equalizer" key.
    var equalizer = EqualizerSettings.load() {
        didSet {
            equalizer.save()
            processor.update(settings: equalizer, skipSilence: skipSilence)
        }
    }
    private(set) var userPresets = EqualizerPreset.loadUser()
    /// Desktop skip_silence, on by default as there.
    var skipSilence = UserDefaults.standard.object(forKey: "skipSilence") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(skipSilence, forKey: "skipSilence")
            processor.update(settings: equalizer, skipSilence: skipSilence)
            if !skipSilence { setInSilence(false) }
        }
    }
    private let processor = AudioProcessor()
    /// True while the processor hears silence: playback runs fast through it.
    @ObservationIgnored private var inSilence = false
    /// SponsorBlock segments for the current item (YouTube stream
    /// playback), set by the reader when a stream starts. The periodic
    /// observer skips playback past a segment it enters.
    var sponsorSegments: [SponsorBlockService.Segment] = []
    @ObservationIgnored private var lastSkippedSegmentEnd: TimeInterval = -1
    /// Desktop SponsorBlock toggle; on by default there.
    var skipSponsorSegments: Bool {
        UserDefaults.standard.object(forKey: "skipSponsorSegments") as? Bool ?? true
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
    /// Items left by Play Next, for Play Previous in Queue (desktop queue.prev).
    private var history: [Article] = []

    /// Speed presets. The desktop range is 0.5x to 4x.
    static let speedSteps: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0]

    init() {
        configureSession()
        configureRemoteCommands()
        processor.update(settings: equalizer, skipSilence: skipSilence)
        processor.onSilenceChange = { [weak self] silent in
            Task { @MainActor in self?.setInSilence(silent) }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                // SponsorBlock: entering a segment seeks past its end.
                if self.isPlaying, self.skipSponsorSegments,
                   let segment = SponsorBlockService.segment(at: self.currentTime, in: self.sponsorSegments),
                   segment.end != self.lastSkippedSegmentEnd {
                    self.lastSkippedSegmentEnd = segment.end
                    self.seek(to: segment.end)
                    Announcer.announce("Skipped \(segment.category) segment.")
                }
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
        // Segments belong to one item; the reader sets the new item's
        // after starting a YouTube stream.
        sponsorSegments = []
        lastSkippedSegmentEnd = -1
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        inSilence = false
        // Equalizer and silence skipping attach once the audio track is known.
        Task { [processor] in
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
            item.audioMix = processor.audioMix(for: track)
        }
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .readyToPlay {
                    self.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                    if resumeAt > 0 {
                        self.seek(to: resumeAt)
                    }
                    self.applyRate()
                    self.isPlaying = true
                } else if item.status == .failed {
                    Announcer.announce("Playback failed. \(item.error?.localizedDescription ?? "")")
                }
            }
        }
        player.play()
        applyRate()
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
            applyRate()
            isPlaying = true
            Announcer.announce("Playing.")
        }
        updateNowPlaying()
    }

    func stop() {
        saveProgress()
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
        rate = min(4.0, max(0.5, (newRate * 100).rounded() / 100))
        Announcer.announce("Speed \(formattedRate).")
    }

    /// Plays at the chosen speed, or fast through silence. The desktop seeks
    /// over silence it scanned ahead; a stream cannot be scanned ahead, so
    /// silence plays at double speed, at least 4x, until sound returns.
    private func applyRate() {
        player.rate = inSilence ? min(max(rate * 2, 4), 8) : rate
    }

    private func setInSilence(_ silent: Bool) {
        guard inSilence != silent else { return }
        inSilence = silent && skipSilence
        if isPlaying { applyRate() }
    }

    // MARK: Equalizer presets (desktop equalizer dialog)

    func applyPreset(_ preset: EqualizerPreset) {
        equalizer = EqualizerSettings(enabled: true, preamp: preset.preamp, bands: preset.bands, preset: preset.name)
        Announcer.announce("\(preset.name) preset applied.")
    }

    /// Saves the current bands under a name, replacing a preset of that name.
    func saveUserPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        userPresets.removeAll { $0.name == trimmed }
        userPresets.append(EqualizerPreset(name: trimmed, preamp: equalizer.preamp, bands: equalizer.bands))
        EqualizerPreset.saveUser(userPresets)
        equalizer.preset = trimmed
        Announcer.announce("Saved preset \(trimmed).")
    }

    func deleteUserPreset(named name: String) {
        userPresets.removeAll { $0.name == name }
        EqualizerPreset.saveUser(userPresets)
        if equalizer.preset == name { equalizer.preset = nil }
        Announcer.announce("Deleted preset \(name).")
    }

    /// Desktop speed.up / speed.down step by 0.1x.
    func changeRate(by delta: Float) { setRate(rate + delta) }

    /// Desktop Ctrl+Up / Ctrl+Down, volume_step 5 percent.
    func adjustVolume(by delta: Float) {
        volume = min(1, max(0, ((volume + delta) * 100).rounded() / 100))
        Announcer.announce("Volume \(Int((volume * 100).rounded())) percent.")
    }

    // MARK: Chapters (desktop Chapters button, Ctrl+Shift+Left/Right/L)

    var chapters: [Chapter] {
        currentArticle?.chapters.sorted { $0.start < $1.start } ?? []
    }

    /// The chapter playing now: the last one that has started.
    func chapterIndex(in chapters: [Chapter]) -> Int? {
        chapters.lastIndex { $0.start <= currentTime + 0.5 }
    }

    func jumpChapter(by offset: Int) {
        let list = chapters
        guard !list.isEmpty else {
            Announcer.announce("No chapters.")
            return
        }
        let target = (chapterIndex(in: list) ?? -1) + offset
        guard list.indices.contains(target) else {
            Announcer.announce(offset > 0 ? "Last chapter." : "First chapter.")
            return
        }
        seek(to: list[target].start)
        Announcer.announce("Chapter \(target + 1), \(list[target].title).")
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
        if let current = currentArticle { history.append(current) }
        play(article: next)
    }

    /// Goes back to the item before Play Next; the current one returns to
    /// the front of the queue.
    func playPreviousInQueue() {
        guard let previous = history.popLast() else {
            Announcer.announce("Start of play queue.")
            return
        }
        if let current = currentArticle {
            queue.insert(current, at: 0)
            persistQueue()
        }
        play(article: previous)
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
