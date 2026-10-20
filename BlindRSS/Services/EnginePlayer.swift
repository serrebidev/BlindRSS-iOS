// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import AVFoundation
import Foundation

/// Engine player for downloaded episodes: five-band equalizer and
/// silence skipping (desktop Equalizer and Skip Silence). Streaming
/// playback stays on AVPlayer; downloads play here so the audio graph
/// (file -> EQ -> time pitch -> output) can shape the sound.
/// Silence skipping watches the output level and jumps forward while
/// the level stays under the threshold.
@MainActor
@Observable
final class EnginePlayer {
    private(set) var isPlaying = false
    private(set) var currentTitle = ""
    /// Five band gains in dB, -12 to +12. Band centers: 60, 230, 910, 3600, 14000 Hz.
    var bandGains: [Float] = [0, 0, 0, 0, 0] {
        didSet { applyEQ() }
    }
    var skipSilence = false
    var rate: Float = 1.0 {
        didSet { pitch.rate = rate }
    }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 5)
    private let pitch = AVAudioUnitTimePitch()
    private var file: AVAudioFile?
    private var startedAt: AVAudioTime?
    private var pausePosition: AVAudioFramePosition = 0
    private var silentDuration: TimeInterval = 0
    private var lastTapDate = Date()

    init() {
        let centers: [Float] = [60, 230, 910, 3600, 14000]
        for (index, band) in eq.bands.enumerated() {
            band.frequency = centers[index]
            band.bandwidth = 1.0
            band.bypass = false
            band.filterType = .parametric
        }
        eq.globalGain = 0
        engine.attach(playerNode)
        engine.attach(eq)
        engine.attach(pitch)
        engine.connect(playerNode, to: eq, format: nil)
        engine.connect(eq, to: pitch, format: nil)
        engine.connect(pitch, to: engine.mainMixerNode, format: nil)
    }

    func play(fileURL: URL, title: String) {
        do {
            file = try AVAudioFile(forReading: fileURL)
            currentTitle = title
            pausePosition = 0
            scheduleFromCurrentPosition()
            try engine.start()
            playerNode.play()
            isPlaying = true
            installLevelTap()
            Announcer.announce("Playing download \(title).")
        } catch {
            Announcer.announce("Download playback failed.")
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pausePosition = currentFrame()
            playerNode.pause()
            engine.pause()
            isPlaying = false
            Announcer.announce("Paused.")
        } else {
            scheduleFromCurrentPosition()
            try? engine.start()
            playerNode.play()
            isPlaying = true
            Announcer.announce("Playing.")
        }
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        isPlaying = false
        file = nil
        currentTitle = ""
    }

    var duration: TimeInterval {
        guard let file, file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    var currentTime: TimeInterval {
        guard duration > 0 else { return 0 }
        return Double(currentFrame()) / (file?.processingFormat.sampleRate ?? 44100)
    }

    private func currentFrame() -> AVAudioFramePosition {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime), isPlaying else {
            return pausePosition
        }
        return pausePosition + playerTime.sampleTime
    }

    private func scheduleFromCurrentPosition() {
        guard let file else { return }
        playerNode.stop()
        let remaining = AVAudioFrameCount(max(0, file.length - pausePosition))
        guard remaining > 0 else { return }
        playerNode.scheduleSegment(file, startingFrame: pausePosition,
                                   frameCount: remaining, at: nil)
    }

    private func applyEQ() {
        for (index, band) in eq.bands.enumerated() where bandGains.indices.contains(index) {
            band.gain = bandGains[index]
        }
    }

    /// Watches output level; while silence skipping is on and the level
    /// stays low, jumps the playhead forward half a second at a time.
    private func installLevelTap() {
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            Task { @MainActor in self.handleLevel(buffer: buffer) }
        }
    }

    private func handleLevel(buffer: AVAudioPCMBuffer) {
        guard skipSilence, isPlaying, let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var sum: Float = 0
        for index in 0..<frames { sum += channel[index] * channel[index] }
        let rms = sqrt(sum / Float(frames))
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTapDate)
        lastTapDate = now
        if rms < 0.01 {
            silentDuration += elapsed
            if silentDuration > 0.7 {
                pausePosition = min(currentFrame() + 22050, (file?.length ?? 0))
                scheduleFromCurrentPosition()
                if !engine.isRunning { try? engine.start() }
                playerNode.play()
                silentDuration = 0
            }
        } else {
            silentDuration = 0
        }
    }
}
