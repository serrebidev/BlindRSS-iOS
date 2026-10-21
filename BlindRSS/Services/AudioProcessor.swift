// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(MediaToolbox)
import AVFoundation
import MediaToolbox
#endif

/// Desktop equalizer (core/equalizer.py): libVLC's 10-band graphic EQ with
/// a preamp, gains clamped to -20...+20 dB, and the last preset's name.
struct EqualizerSettings: Equatable, Codable {
    /// The band centers libVLC filters (desktop BAND_FREQUENCIES).
    static let frequencies: [Float] = [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let gainRange: ClosedRange<Float> = -20...20

    var enabled = false
    var preamp: Float = 0
    var bands: [Float] = Array(repeating: 0, count: 10)
    var preset: String?

    /// "500 Hz" or "16 kHz", as the desktop labels its sliders.
    static func label(for frequency: Float) -> String {
        let value = frequency >= 1000 ? frequency / 1000 : frequency
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return frequency >= 1000 ? "\(number) kHz" : "\(number) Hz"
    }

    private static let defaultsKey = "equalizer"

    static func load() -> EqualizerSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode(EqualizerSettings.self, from: data),
              saved.bands.count == frequencies.count else { return EqualizerSettings() }
        return saved
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

struct EqualizerPreset: Codable, Hashable {
    var name: String
    var preamp: Float
    var bands: [Float]

    /// libVLC's built-in presets (modules/audio_filter/equalizer_presets.h),
    /// the list the desktop shows. VLC's preamps sit on its own +12 dB flat
    /// level; 12 dB is taken off here so Flat is unchanged sound and boosted
    /// presets do not clip.
    static let builtIn: [EqualizerPreset] = ([
        ("Flat", 12, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ("Classical", 12, [0, 0, 0, 0, 0, 0, -7.2, -7.2, -7.2, -9.6]),
        ("Club", 6, [0, 0, 8, 5.6, 5.6, 5.6, 3.2, 0, 0, 0]),
        ("Dance", 5, [9.6, 7.2, 2.4, 0, 0, -5.6, -7.2, -7.2, 0, 0]),
        ("Full Bass", 5, [-8, 9.6, 9.6, 5.6, 1.6, -4, -8, -10.4, -11.2, -11.2]),
        ("Full Bass and Treble", 4, [7.2, 5.6, 0, -7.2, -4.8, 1.6, 8, 11.2, 12, 12]),
        ("Full Treble", 3, [-9.6, -9.6, -9.6, -4, 2.4, 11.2, 16, 16, 16, 16.8]),
        ("Headphones", 4, [4.8, 11.2, 5.6, -3.2, -2.4, 1.6, 4.8, 9.6, 12.8, 14.4]),
        ("Large Hall", 5, [10.4, 10.4, 5.6, 5.6, 0, -4.8, -4.8, -4.8, 0, 0]),
        ("Live", 7, [-4.8, 0, 4, 5.6, 5.6, 5.6, 4, 2.4, 2.4, 2.4]),
        ("Party", 6, [7.2, 7.2, 0, 0, 0, 0, 0, 0, 7.2, 7.2]),
        ("Pop", 6, [-1.6, 4.8, 7.2, 8, 5.6, 0, -2.4, -2.4, -1.6, -1.6]),
        ("Reggae", 8, [0, 0, 0, -5.6, 0, 6.4, 6.4, 0, 0, 0]),
        ("Rock", 5, [8, 4.8, -5.6, -8, -3.2, 4, 8.8, 11.2, 11.2, 11.2]),
        ("Ska", 6, [-2.4, -4.8, -4, 0, 4, 5.6, 8.8, 9.6, 11.2, 9.6]),
        ("Soft", 5, [4.8, 1.6, 0, -2.4, 0, 4, 8, 9.6, 11.2, 12]),
        ("Soft Rock", 7, [4, 4, 2.4, 0, -4, -5.6, -3.2, 0, 2.4, 8.8]),
        ("Techno", 5, [8, 5.6, 0, -5.6, -4.8, 0, 8, 9.6, 9.6, 8.8]),
    ] as [(String, Float, [Float])]).map { EqualizerPreset(name: $0.0, preamp: $0.1 - 12, bands: $0.2) }

    private static let defaultsKey = "equalizer.userPresets"

    /// Presets the listener saved (desktop user presets).
    static func loadUser() -> [EqualizerPreset] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([EqualizerPreset].self, from: data)) ?? []
    }

    static func saveUser(_ presets: [EqualizerPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

/// Preamp plus ten peaking biquads (RBJ Audio EQ Cookbook), state kept per
/// channel so stereo stays stereo.
struct EqualizerFilter {
    private struct Coefficients {
        var b0, b1, b2, a1, a2: Float
    }

    private var coefficients: [Coefficients] = []
    /// [channel][band]: the two delay values of each filter.
    private var state: [[SIMD2<Float>]] = []
    private var gain: Float = 1
    private(set) var isActive = false

    /// Octave-spaced bands: Q of about 1.41 covers one octave each.
    private static let q: Double = 1.41

    mutating func configure(_ settings: EqualizerSettings, sampleRate: Double, channels: Int) {
        isActive = settings.enabled && sampleRate > 0
        gain = Float(pow(10, Double(settings.preamp) / 20))
        coefficients = zip(EqualizerSettings.frequencies, settings.bands).compactMap { frequency, decibels in
            // A flat band is the identity; one at or above Nyquist cannot be filtered.
            guard decibels != 0, Double(frequency) < sampleRate * 0.45 else { return nil }
            let a = pow(10, Double(decibels) / 40)
            let w0 = 2 * Double.pi * Double(frequency) / sampleRate
            let alpha = sin(w0) / (2 * Self.q)
            let a0 = 1 + alpha / a
            return Coefficients(b0: Float((1 + alpha * a) / a0), b1: Float(-2 * cos(w0) / a0),
                                b2: Float((1 - alpha * a) / a0), a1: Float(-2 * cos(w0) / a0),
                                a2: Float((1 - alpha / a) / a0))
        }
        state = Array(repeating: Array(repeating: .zero, count: coefficients.count), count: max(channels, 0))
    }

    /// Filters one channel in place. `stride` is the channel count of an
    /// interleaved buffer (1 when channels are in separate buffers), and
    /// `samples` points at this channel's first sample.
    mutating func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, stride: Int, channel: Int) {
        guard isActive, state.indices.contains(channel) else { return }
        let end = frames * stride
        for band in coefficients.indices {
            let c = coefficients[band]
            var z = state[channel][band]
            var i = 0
            while i < end {
                let x = samples[i]
                let y = c.b0 * x + z.x
                z.x = c.b1 * x - c.a1 * y + z.y
                z.y = c.b2 * x - c.a2 * y
                samples[i] = y
                i += stride
            }
            state[channel][band] = z
        }
        if gain != 1 {
            var i = 0
            while i < end {
                samples[i] *= gain
                i += stride
            }
        }
    }
}

/// Desktop skip_silence: audio under -38 dB for at least 700 ms is silence
/// (silence_skip_threshold_db, silence_skip_min_ms).
struct SilenceDetector {
    static let threshold = Float(pow(10, -38.0 / 20))
    static let minimumSeconds = 0.7

    private var silentSeconds = 0.0
    private(set) var isSilent = false

    /// Feeds one buffer's level. Returns true when silence began or ended.
    mutating func feed(rms: Float, seconds: Double) -> Bool {
        let wasSilent = isSilent
        if rms < Self.threshold {
            silentSeconds += seconds
            isSilent = silentSeconds >= Self.minimumSeconds
        } else {
            silentSeconds = 0
            isSilent = false
        }
        return isSilent != wasSilent
    }

    mutating func reset() {
        silentSeconds = 0
        isSilent = false
    }
}

#if canImport(MediaToolbox)
/// Runs the equalizer and silence detection inside AVPlayer's own audio
/// pipeline (MTAudioProcessingTap), so streamed episodes get them, not only
/// downloads. Taps do not reach HLS streams; podcast enclosures are files.
final class AudioProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingSettings = EqualizerSettings()
    private var pendingSkipSilence = false
    private var version = 0

    // Render-thread state, only touched inside the tap callbacks.
    private var appliedVersion = -1
    private var filter = EqualizerFilter()
    private var detector = SilenceDetector()
    private var skipSilence = false
    private var supported = false
    private var sampleRate = 44_100.0
    private var channels = 2

    /// Called on the main queue when playback enters or leaves silence.
    var onSilenceChange: (@Sendable (Bool) -> Void)?

    func update(settings: EqualizerSettings, skipSilence: Bool) {
        lock.lock()
        pendingSettings = settings
        pendingSkipSilence = skipSilence
        version += 1
        lock.unlock()
    }

    /// An audio mix that routes the track through this processor.
    func audioMix(for track: AVAssetTrack) -> AVAudioMix? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()),
            init: { _, clientInfo, storage in storage.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<AudioProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                AudioProcessor.from(tap).prepare(format.pointee)
            },
            unprepare: nil,
            process: { tap, frameCount, _, bufferList, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frameCount, bufferList, flagsOut, nil, framesOut) == noErr else { return }
                AudioProcessor.from(tap).process(bufferList, frames: Int(framesOut.pointee))
            })
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                         kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr,
              let tap else {
            Unmanaged.passUnretained(self).release()
            return nil
        }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    private static func from(_ tap: MTAudioProcessingTap) -> AudioProcessor {
        Unmanaged<AudioProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    private func prepare(_ format: AudioStreamBasicDescription) {
        supported = format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mBitsPerChannel == 32
        sampleRate = format.mSampleRate
        channels = Int(format.mChannelsPerFrame)
        appliedVersion = -1
        detector.reset()
    }

    private func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard supported, frames > 0 else { return }
        // ponytail: brief lock on the render thread; a lock-free swap if it ever glitches.
        lock.lock()
        if appliedVersion != version {
            appliedVersion = version
            filter.configure(pendingSettings, sampleRate: sampleRate, channels: channels)
            if skipSilence != pendingSkipSilence { detector.reset() }
            skipSilence = pendingSkipSilence
        }
        lock.unlock()

        var sum: Float = 0
        var count = 0
        var channel = 0
        for buffer in UnsafeMutableAudioBufferListPointer(list) {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let stride = max(1, Int(buffer.mNumberChannels))
            let usable = min(frames, Int(buffer.mDataByteSize) / (4 * stride))
            if skipSilence {
                for i in 0..<(usable * stride) { sum += data[i] * data[i] }
                count += usable * stride
            }
            for offset in 0..<stride {
                filter.process(data + offset, frames: usable, stride: stride, channel: channel + offset)
            }
            channel += stride
        }
        if skipSilence, count > 0,
           detector.feed(rms: (sum / Float(count)).squareRoot(), seconds: Double(frames) / sampleRate) {
            let silent = detector.isSilent
            let callback = onSilenceChange
            DispatchQueue.main.async { callback?(silent) }
        }
    }
}
#endif
