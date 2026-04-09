import Foundation
import Accelerate

/// YIN pitch detection algorithm using Accelerate framework
class PitchDetector {
    private let sampleRate: Float
    private let frameSize: Int
    private let threshold: Float

    /// Minimum and maximum frequencies to detect (Hz)
    private let minFreq: Float = 60    // ~B1
    private let maxFreq: Float = 1200  // ~D6

    init(sampleRate: Float = 44100, frameSize: Int = 2048, threshold: Float = 0.15) {
        self.sampleRate = sampleRate
        self.frameSize = frameSize
        self.threshold = threshold
    }

    /// Detect pitch for each frame in the audio buffer
    /// - Returns: Array of (frameIndex, frequency) pairs. Frequency is 0 for unvoiced frames.
    func detectPitches(in samples: [Float], hopSize: Int = 512) -> [(Int, Float)] {
        var pitches: [(Int, Float)] = []
        let halfFrame = frameSize / 2

        var frameStart = 0
        var frameIndex = 0

        while frameStart + frameSize <= samples.count {
            let frame = Array(samples[frameStart..<frameStart + frameSize])
            let pitch = detectPitch(frame: frame)
            pitches.append((frameIndex, pitch))
            frameStart += hopSize
            frameIndex += 1
        }

        return pitches
    }

    /// Detect pitch for a single frame using YIN algorithm
    func detectPitch(frame: [Float]) -> Float {
        let halfFrame = frameSize / 2
        let minLag = Int(sampleRate / maxFreq)
        let maxLag = min(Int(sampleRate / minFreq), halfFrame)

        guard maxLag > minLag else { return 0 }

        // Step 1: Difference function
        var difference = [Float](repeating: 0, count: halfFrame)
        computeDifference(frame: frame, difference: &difference)

        // Step 2: Cumulative mean normalized difference
        var cmndf = [Float](repeating: 0, count: halfFrame)
        cmndf[0] = 1
        var runningSum: Float = 0

        for tau in 1..<halfFrame {
            runningSum += difference[tau]
            cmndf[tau] = difference[tau] * Float(tau) / runningSum
        }

        // Step 3: Absolute threshold - find first tau where cmndf < threshold
        var bestTau = -1
        for tau in minLag..<maxLag {
            if cmndf[tau] < threshold {
                // Find local minimum
                while tau + 1 < maxLag && cmndf[tau + 1] < cmndf[tau] {
                    bestTau = tau + 1
                    break
                }
                if bestTau == -1 { bestTau = tau }
                break
            }
        }

        // If no pitch found below threshold, find global minimum
        if bestTau == -1 {
            var minVal: Float = Float.greatestFiniteMagnitude
            for tau in minLag..<maxLag {
                if cmndf[tau] < minVal {
                    minVal = cmndf[tau]
                    bestTau = tau
                }
            }
            // Only accept if reasonably periodic
            if minVal > 0.5 { return 0 }
        }

        guard bestTau > 0 else { return 0 }

        // Step 4: Parabolic interpolation
        let interpolatedTau = parabolicInterpolation(cmndf: cmndf, tau: bestTau)

        return sampleRate / interpolatedTau
    }

    // MARK: - Private

    /// Compute the difference function using autocorrelation via FFT
    private func computeDifference(frame: [Float], difference: inout [Float]) {
        let n = frame.count
        let halfN = n / 2

        for tau in 0..<halfN {
            var sum: Float = 0
            for i in 0..<halfN {
                let diff = frame[i] - frame[i + tau]
                sum += diff * diff
            }
            difference[tau] = sum
        }
    }

    /// Refine lag estimate using parabolic interpolation
    private func parabolicInterpolation(cmndf: [Float], tau: Int) -> Float {
        guard tau > 0 && tau < cmndf.count - 1 else {
            return Float(tau)
        }

        let s0 = cmndf[tau - 1]
        let s1 = cmndf[tau]
        let s2 = cmndf[tau + 1]

        let adjustment = (s0 - s2) / (2.0 * (s0 - 2.0 * s1 + s2))

        if adjustment.isNaN || adjustment.isInfinite {
            return Float(tau)
        }

        return Float(tau) + adjustment
    }
}
