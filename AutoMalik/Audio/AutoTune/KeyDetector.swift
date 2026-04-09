import Foundation
import AVFoundation

/// Detects the most likely musical key of an audio file using
/// the Krumhansl-Schmuckler key-finding algorithm.
class KeyDetector {

    // Krumhansl-Schmuckler key profiles (averaged probe-tone responses)
    private static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    /// Analyze an audio file and return the most likely musical key
    func detectKey(in url: URL) -> MusicalKey? {
        guard let samples = loadMonoSamples(from: url) else { return nil }
        return detectKey(samples: samples)
    }

    func detectKey(samples: [Float]) -> MusicalKey? {
        let detector = PitchDetector()
        let pitches = detector.detectPitches(in: samples, hopSize: 1024)

        // Build a chroma histogram (12 semitones)
        var histogram = [Double](repeating: 0, count: 12)
        for (_, freq) in pitches where freq > 0 {
            let midi = 69.0 + 12.0 * log2(Double(freq) / 440.0)
            let pitchClass = ((Int(round(midi)) % 12) + 12) % 12
            histogram[pitchClass] += 1
        }

        let total = histogram.reduce(0, +)
        guard total > 0 else { return nil }

        // Normalize
        let normalized = histogram.map { $0 / total }

        // Score all 24 keys (12 major + 12 minor)
        var bestScore = -Double.infinity
        var bestRoot = 0
        var bestIsMajor = true

        for root in 0..<12 {
            let majorScore = correlation(histogram: normalized, profile: Self.majorProfile, rotation: root)
            let minorScore = correlation(histogram: normalized, profile: Self.minorProfile, rotation: root)

            if majorScore > bestScore {
                bestScore = majorScore
                bestRoot = root
                bestIsMajor = true
            }
            if minorScore > bestScore {
                bestScore = minorScore
                bestRoot = root
                bestIsMajor = false
            }
        }

        guard let rootNote = NoteName(rawValue: bestRoot) else { return nil }
        return MusicalKey(root: rootNote, scale: bestIsMajor ? .major : .minor)
    }

    /// Pearson correlation between histogram and a rotated key profile
    private func correlation(histogram: [Double], profile: [Double], rotation: Int) -> Double {
        let n = 12
        let rotated = (0..<n).map { profile[($0 - rotation + n) % n] }
        let meanH = histogram.reduce(0, +) / Double(n)
        let meanP = rotated.reduce(0, +) / Double(n)

        var num: Double = 0
        var denH: Double = 0
        var denP: Double = 0
        for i in 0..<n {
            let dh = histogram[i] - meanH
            let dp = rotated[i] - meanP
            num += dh * dp
            denH += dh * dh
            denP += dp * dp
        }
        let denom = sqrt(denH * denP)
        return denom > 0 ? num / denom : 0
    }

    // MARK: - Sample loading

    private func loadMonoSamples(from url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        try? file.read(into: buffer)

        guard let channelData = buffer.floatChannelData else { return nil }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)

        // Mix down to mono
        var samples = [Float](repeating: 0, count: frames)
        for ch in 0..<channels {
            let ptr = channelData[ch]
            for i in 0..<frames {
                samples[i] += ptr[i] / Float(channels)
            }
        }
        return samples
    }
}
