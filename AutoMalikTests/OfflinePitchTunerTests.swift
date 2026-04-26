import XCTest
import AVFoundation
@testable import AutoMalik

final class OfflinePitchTunerTests: XCTestCase {

    // Analysis window skips the first 0.3 s of output to avoid the
    // AVAudioUnitTimePitch startup transient.
    private let analysisSkipSeconds: Double = 0.3
    private let sampleRate: Double = 44100
    private let duration: Double = 2.0

    // MARK: - Tests

    func testSharpToneSnapsToNearestKeyNote() throws {
        // 450 Hz is ~39 cents sharp of A4 (440 Hz). In C major the nearest
        // valid semitone is A, so full-strength correction must snap back to 440.
        let inputURL = try writeSine(freq: 450, to: "sharp_input.wav")
        let outputURL = tempURL("sharp_output.wav")
        let tuner = OfflinePitchTuner()

        try tuner.tune(
            inputURL: inputURL,
            outputURL: outputURL,
            key: MusicalKey(root: .C, scale: .major),
            strength: 1.0,
            pitchDetector: PitchDetector(sampleRate: 44100)
        )

        let detected = try medianDetectedFrequency(of: outputURL)
        XCTAssertEqual(detected, 440, accuracy: 8,
                       "Expected snap to A4 (440 Hz), got \(detected) Hz")
    }

    func testHalfStrengthProducesPartialCorrection() throws {
        // 450 Hz at strength 0.5 in C major should land roughly halfway between
        // 450 and 440 Hz (about 445 Hz — halfway in frequency space is close
        // enough to halfway in cents space for a ~40-cent offset).
        let inputURL = try writeSine(freq: 450, to: "half_input.wav")
        let outputURL = tempURL("half_output.wav")
        let tuner = OfflinePitchTuner()

        try tuner.tune(
            inputURL: inputURL,
            outputURL: outputURL,
            key: MusicalKey(root: .C, scale: .major),
            strength: 0.5,
            pitchDetector: PitchDetector(sampleRate: 44100)
        )

        let detected = try medianDetectedFrequency(of: outputURL)
        XCTAssertEqual(detected, 445, accuracy: 5,
                       "Expected partial correction, got \(detected) Hz")
    }

    func testVibratoToneSnapsToNote() throws {
        // Slow ±8 Hz vibrato around 445 Hz — should still snap to A4 on average.
        let inputURL = try writeVibrato(
            baseFreq: 445,
            depthHz: 8,
            vibratoRate: 5,
            to: "vibrato_input.wav"
        )
        let outputURL = tempURL("vibrato_output.wav")
        let tuner = OfflinePitchTuner()

        try tuner.tune(
            inputURL: inputURL,
            outputURL: outputURL,
            key: MusicalKey(root: .C, scale: .major),
            strength: 1.0,
            pitchDetector: PitchDetector(sampleRate: 44100)
        )

        let detected = try medianDetectedFrequency(of: outputURL)
        XCTAssertEqual(detected, 440, accuracy: 12,
                       "Expected snap to A4 under vibrato, got \(detected) Hz")
    }

    func testOutputIsValidAudio() throws {
        let inputURL = try writeSine(freq: 450, to: "valid_input.wav")
        let outputURL = tempURL("valid_output.wav")

        try OfflinePitchTuner().tune(
            inputURL: inputURL,
            outputURL: outputURL,
            key: MusicalKey(root: .C, scale: .major),
            strength: 1.0,
            pitchDetector: PitchDetector(sampleRate: 44100)
        )

        let samples = try readSamples(from: outputURL)

        // Length should match input to within one render chunk (512 frames).
        let expected = Int(sampleRate * duration)
        XCTAssertLessThanOrEqual(abs(samples.count - expected), 1024,
                                 "Output length \(samples.count) too far from \(expected)")

        // No NaN / infinity, no extreme clipping.
        for s in samples {
            XCTAssertFalse(s.isNaN, "Output contains NaN")
            XCTAssertFalse(s.isInfinite, "Output contains Inf")
            XCTAssertLessThan(abs(s), 2.0, "Output sample \(s) is suspiciously large")
        }

        // Non-trivial energy after the startup transient.
        let skip = Int(sampleRate * analysisSkipSeconds)
        let tail = Array(samples[skip...])
        let rms = sqrt(tail.reduce(0) { $0 + $1 * $1 } / Float(tail.count))
        XCTAssertGreaterThan(rms, 0.05,
                             "Output RMS \(rms) is too low — tuning may have silenced the signal")
    }

    func testNearestValidFrequencyUsesClosestOctaveAcrossBoundary() {
        let cMajor = MusicalKey(root: .C, scale: .major)

        // B is not in C major; the closest valid note to B4 is C5, not C4.
        let b4: Float = 493.8833
        let snappedUp = cMajor.nearestValidFrequency(b4)
        XCTAssertEqual(snappedUp, 523.2511, accuracy: 1.0)

        // C is not in B minor; the closest valid note to C4 is B3, not B4.
        let bMinor = MusicalKey(root: .B, scale: .minor)
        let c4: Float = 261.6256
        let snappedDown = bMinor.nearestValidFrequency(c4)
        XCTAssertEqual(snappedDown, 246.9417, accuracy: 1.0)
    }

    // MARK: - Signal synthesis

    private func writeSine(freq: Float, to name: String) throws -> URL {
        let total = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: total)
        // Accumulate phase rather than computing i * freq * 2π / sr directly —
        // the product overflows Float32's 24-bit integer precision for long
        // signals, which drifts the apparent frequency by several Hz.
        let delta = 2 * Float.pi * freq / Float(sampleRate)
        var phase: Float = 0
        for i in 0..<total {
            samples[i] = 0.5 * sin(phase)
            phase += delta
            if phase > 2 * .pi { phase -= 2 * .pi }
        }
        return try writeMono(samples: samples, name: name)
    }

    private func writeVibrato(
        baseFreq: Float,
        depthHz: Float,
        vibratoRate: Float,
        to name: String
    ) throws -> URL {
        let total = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: total)
        var phase: Float = 0
        let sr = Float(sampleRate)
        for i in 0..<total {
            let t = Float(i) / sr
            let instFreq = baseFreq + depthHz * sin(2 * .pi * vibratoRate * t)
            phase += 2 * .pi * instFreq / sr
            samples[i] = 0.5 * sin(phase)
        }
        return try writeMono(samples: samples, name: name)
    }

    private func writeMono(samples: [Float], name: String) throws -> URL {
        let url = tempURL(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: true
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw NSError(domain: "Test", code: 1)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let dst = buffer.floatChannelData![0]
        for i in 0..<samples.count { dst[i] = samples[i] }
        try file.write(from: buffer)
        return url
    }

    // MARK: - Analysis

    private func readSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw NSError(domain: "Test", code: 2)
        }
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(
            start: buffer.floatChannelData![0],
            count: Int(buffer.frameLength)
        ))
    }

    private func medianDetectedFrequency(of url: URL) throws -> Float {
        let samples = try readSamples(from: url)
        let skip = Int(sampleRate * analysisSkipSeconds)
        guard samples.count > skip + 2048 else { return 0 }
        let tail = Array(samples[skip...])

        let detector = PitchDetector(sampleRate: 44100, frameSize: 2048, threshold: 0.15)
        let detected = detector.detectPitches(in: tail, hopSize: 512)
            .map { $0.1 }
            .filter { $0 > 50 && $0 < 2000 }
        XCTAssertFalse(detected.isEmpty, "No voiced frames detected in output")
        return median(detected)
    }

    private func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        if sorted.isEmpty { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 1
            ? sorted[mid]
            : (sorted[mid - 1] + sorted[mid]) / 2
    }

    // MARK: - File helpers

    private func tempURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoMalikTests", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        let url = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        return url
    }
}
