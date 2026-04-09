import Foundation

/// Maps detected pitches to target notes in a musical key with adjustable correction strength
class PitchCorrector {

    /// Compute pitch correction ratios for each frame
    /// - Parameters:
    ///   - pitches: Array of (frameIndex, detectedFrequency) from PitchDetector
    ///   - key: Target musical key
    ///   - strength: Correction strength 0.0 (none) to 1.0 (full snap)
    /// - Returns: Array of (frameIndex, pitchRatio) where pitchRatio = targetFreq / detectedFreq
    func computeCorrections(
        pitches: [(Int, Float)],
        key: MusicalKey,
        strength: Float
    ) -> [(Int, Float)] {
        return pitches.map { (frameIndex, detectedFreq) in
            guard detectedFreq > 0 else {
                return (frameIndex, 1.0) // No pitch detected, no correction
            }

            let targetFreq = key.nearestValidFrequency(detectedFreq)
            let correctedFreq = detectedFreq + strength * (targetFreq - detectedFreq)
            let ratio = correctedFreq / detectedFreq

            return (frameIndex, ratio)
        }
    }

    /// Apply auto-tune to audio samples
    /// - Returns: Processed audio samples
    func autoTune(
        samples: [Float],
        sampleRate: Float = 44100,
        key: MusicalKey,
        strength: Float,
        pitchDetector: PitchDetector,
        phaseVocoder: PhaseVocoder
    ) -> [Float] {
        let hopSize = 512

        // Detect pitches
        let pitches = pitchDetector.detectPitches(in: samples, hopSize: hopSize)

        // Compute correction ratios
        let corrections = computeCorrections(pitches: pitches, key: key, strength: strength)

        // Apply pitch shifting via phase vocoder
        return phaseVocoder.processWithVariablePitch(
            samples: samples,
            pitchRatios: corrections,
            hopSize: hopSize
        )
    }
}
