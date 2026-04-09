import Foundation
import Accelerate

/// Phase vocoder for pitch shifting using STFT and Accelerate framework
class PhaseVocoder {
    private let frameSize: Int
    private let hopSize: Int
    private var window: [Float]

    init(frameSize: Int = 2048, hopSize: Int = 512) {
        self.frameSize = frameSize
        self.hopSize = hopSize

        // Create Hann window
        self.window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&self.window, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))
    }

    /// Process audio with a constant pitch ratio
    func process(samples: [Float], pitchRatio: Float) -> [Float] {
        let ratios = [(0, pitchRatio)] // Single constant ratio
        return processWithVariablePitch(samples: samples, pitchRatios: ratios, hopSize: hopSize)
    }

    /// Process audio with per-frame variable pitch ratios
    func processWithVariablePitch(
        samples: [Float],
        pitchRatios: [(Int, Float)],
        hopSize: Int
    ) -> [Float] {
        let n = samples.count
        guard n > frameSize else { return samples }

        let halfFrame = frameSize / 2 + 1
        let log2n = vDSP_Length(log2(Float(frameSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return samples
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Phase accumulators
        var lastInputPhase = [Float](repeating: 0, count: halfFrame)
        var lastOutputPhase = [Float](repeating: 0, count: halfFrame)

        // Output buffer (may be slightly different length due to time stretching)
        var output = [Float](repeating: 0, count: n + frameSize)
        var windowSum = [Float](repeating: 0, count: n + frameSize)

        let freqPerBin = Float(44100) / Float(frameSize)
        let expectedPhaseDiff = 2.0 * Float.pi * Float(hopSize) / Float(frameSize)

        var ratioIndex = 0
        var frameIndex = 0
        var outputPos = 0

        var inputPos = 0
        while inputPos + frameSize <= n {
            // Get current pitch ratio
            while ratioIndex < pitchRatios.count - 1 && pitchRatios[ratioIndex + 1].0 <= frameIndex {
                ratioIndex += 1
            }
            let pitchRatio = pitchRatios[ratioIndex].1

            // Window the input frame
            var windowed = [Float](repeating: 0, count: frameSize)
            vDSP_vmul(Array(samples[inputPos..<inputPos + frameSize]), 1, window, 1, &windowed, 1, vDSP_Length(frameSize))

            // Forward FFT
            var realPart = [Float](repeating: 0, count: halfFrame)
            var imagPart = [Float](repeating: 0, count: halfFrame)
            windowed.withUnsafeMutableBufferPointer { ptr in
                var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
                ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfFrame) { complexPtr in
                    vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfFrame))
                }
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }

            // Convert to magnitude and phase
            var magnitudes = [Float](repeating: 0, count: halfFrame)
            var phases = [Float](repeating: 0, count: halfFrame)

            for i in 0..<halfFrame {
                magnitudes[i] = sqrt(realPart[i] * realPart[i] + imagPart[i] * imagPart[i])
                phases[i] = atan2(imagPart[i], realPart[i])
            }

            // Phase vocoder: compute true frequency and shift
            var newMagnitudes = [Float](repeating: 0, count: halfFrame)
            var newPhases = [Float](repeating: 0, count: halfFrame)

            for i in 0..<halfFrame {
                // Phase difference
                var phaseDiff = phases[i] - lastInputPhase[i]
                lastInputPhase[i] = phases[i]

                // Remove expected phase advance
                phaseDiff -= Float(i) * expectedPhaseDiff

                // Wrap to [-pi, pi]
                phaseDiff = phaseDiff - 2.0 * Float.pi * round(phaseDiff / (2.0 * Float.pi))

                // True frequency of this bin
                let trueFreq = Float(i) * freqPerBin + phaseDiff * Float(44100) / (2.0 * Float.pi * Float(hopSize))

                // Shift frequency
                let shiftedFreq = trueFreq * pitchRatio
                let targetBin = Int(round(shiftedFreq / freqPerBin))

                if targetBin >= 0 && targetBin < halfFrame {
                    newMagnitudes[targetBin] += magnitudes[i]

                    // Accumulate phase
                    let phaseAdvance = shiftedFreq * 2.0 * Float.pi * Float(hopSize) / Float(44100)
                    newPhases[targetBin] = lastOutputPhase[targetBin] + phaseAdvance
                }
            }

            // Update output phases
            lastOutputPhase = newPhases

            // Convert back to complex
            var newReal = [Float](repeating: 0, count: halfFrame)
            var newImag = [Float](repeating: 0, count: halfFrame)
            for i in 0..<halfFrame {
                newReal[i] = newMagnitudes[i] * cos(newPhases[i])
                newImag[i] = newMagnitudes[i] * sin(newPhases[i])
            }

            // Inverse FFT
            var outputFrame = [Float](repeating: 0, count: frameSize)
            var splitOutput = DSPSplitComplex(realp: &newReal, imagp: &newImag)
            vDSP_fft_zrip(fftSetup, &splitOutput, 1, log2n, FFTDirection(kFFTDirection_Inverse))

            // Convert from split complex to interleaved
            newReal.withUnsafeMutableBufferPointer { realPtr in
                newImag.withUnsafeMutableBufferPointer { imagPtr in
                    var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    outputFrame.withUnsafeMutableBufferPointer { outPtr in
                        outPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfFrame) { complexPtr in
                            vDSP_ztoc(&split, 1, complexPtr, 2, vDSP_Length(halfFrame))
                        }
                    }
                }
            }

            // Scale by 1/N (FFT normalization)
            var scale = 1.0 / Float(frameSize)
            vDSP_vsmul(outputFrame, 1, &scale, &outputFrame, 1, vDSP_Length(frameSize))

            // Apply window
            vDSP_vmul(outputFrame, 1, window, 1, &outputFrame, 1, vDSP_Length(frameSize))

            // Overlap-add to output
            let outStart = inputPos // Keep time-aligned (no time stretch for pitch shift)
            if outStart + frameSize <= output.count {
                for i in 0..<frameSize {
                    output[outStart + i] += outputFrame[i]
                    windowSum[outStart + i] += window[i] * window[i]
                }
            }

            inputPos += hopSize
            frameIndex += 1
        }

        // Normalize by window sum
        for i in 0..<min(n, output.count) {
            if windowSum[i] > 1e-6 {
                output[i] /= windowSum[i]
            }
        }

        return Array(output.prefix(n))
    }
}
