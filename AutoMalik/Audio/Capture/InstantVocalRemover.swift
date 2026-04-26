import Foundation
import AVFoundation
import Accelerate

/// Fast vocal removal using stereo center-channel cancellation.
/// Subtracts dead-centered content (typically vocals) by computing
/// the side channel (L - R) and outputting it as mono. Real-time,
/// zero-ML, much lower quality than Demucs but instant.
class InstantVocalRemover {

    /// Process a stereo audio file and write a vocal-removed version
    /// - Returns: URL of the created instrumental file
    static func removeVocals(from sourceURL: URL, to destURL: URL) throws -> URL {
        let inputFile = try AVAudioFile(forReading: sourceURL)
        let format = inputFile.processingFormat
        let frameCount = AVAudioFrameCount(inputFile.length)

        guard format.channelCount >= 2 else {
            // Mono - can't do center cancellation. Just copy.
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destURL
        }

        // Read all samples
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "VocalRemover", code: 1)
        }
        try inputFile.read(into: inputBuffer)

        guard let channelData = inputBuffer.floatChannelData else {
            throw NSError(domain: "VocalRemover", code: 2)
        }

        let frames = Int(inputBuffer.frameLength)
        let leftPtr = channelData[0]
        let rightPtr = channelData[1]

        // Create stereo output (so it matches the original format and the
        // playback chain doesn't need conversion). Both channels get (L-R)/2
        // which removes center-panned content.
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw NSError(domain: "VocalRemover", code: 3)
        }

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(frames)) else {
            throw NSError(domain: "VocalRemover", code: 4)
        }
        outputBuffer.frameLength = AVAudioFrameCount(frames)

        let outLeft = outputBuffer.floatChannelData![0]
        let outRight = outputBuffer.floatChannelData![1]

        // Compute (L - R) / 2 for both output channels using vDSP for speed
        // Using vDSP_vsub to compute L - R, then scale by 0.5
        var diff = [Float](repeating: 0, count: frames)
        vDSP_vsub(rightPtr, 1, leftPtr, 1, &diff, 1, vDSP_Length(frames))
        var half: Float = 0.5
        vDSP_vsmul(diff, 1, &half, &diff, 1, vDSP_Length(frames))

        // Boost slightly since center cancellation tends to lose level
        var boost: Float = 1.4
        vDSP_vsmul(diff, 1, &boost, &diff, 1, vDSP_Length(frames))

        // Copy to both output channels
        memcpy(outLeft, diff, frames * MemoryLayout<Float>.size)
        memcpy(outRight, diff, frames * MemoryLayout<Float>.size)

        // Write
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        let outputFile = try AVAudioFile(
            forWriting: destURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try outputFile.write(from: outputBuffer)

        return destURL
    }
}
