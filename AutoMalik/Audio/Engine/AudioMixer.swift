import Foundation
import AVFoundation

class AudioMixer {

    func mixTracks(
        instrumentalURL: URL,
        vocalURL: URL,
        instrumentalVolume: Float,
        vocalVolume: Float,
        outputURL: URL
    ) throws {
        let instrumentalFile = try AVAudioFile(forReading: instrumentalURL)
        let vocalFile = try AVAudioFile(forReading: vocalURL)

        let sampleRate = instrumentalFile.processingFormat.sampleRate
        let instrumentalLength = instrumentalFile.length
        let vocalLength = vocalFile.length
        let outputLength = max(instrumentalLength, vocalLength)

        // Output format: stereo 44100 float32
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false) else {
            throw MixError.formatError
        }

        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings, commonFormat: .pcmFormatFloat32, interleaved: false)

        let bufferSize: AVAudioFrameCount = 8192
        var framesRemaining = AVAudioFrameCount(outputLength)

        while framesRemaining > 0 {
            let framesToRead = min(bufferSize, framesRemaining)

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesToRead) else {
                throw MixError.bufferError
            }
            outputBuffer.frameLength = framesToRead

            // Zero the output buffer
            for ch in 0..<Int(outputFormat.channelCount) {
                let ptr = outputBuffer.floatChannelData![ch]
                for i in 0..<Int(framesToRead) {
                    ptr[i] = 0
                }
            }

            // Read and mix instrumental
            if instrumentalFile.framePosition < instrumentalLength {
                let instFrames = min(framesToRead, AVAudioFrameCount(instrumentalLength - instrumentalFile.framePosition))
                if let instBuffer = AVAudioPCMBuffer(pcmFormat: instrumentalFile.processingFormat, frameCapacity: instFrames) {
                    try instrumentalFile.read(into: instBuffer, frameCount: instFrames)
                    mixBuffer(instBuffer, into: outputBuffer, volume: instrumentalVolume, targetChannels: Int(outputFormat.channelCount))
                }
            }

            // Read and mix vocal
            if vocalFile.framePosition < vocalLength {
                let vocFrames = min(framesToRead, AVAudioFrameCount(vocalLength - vocalFile.framePosition))
                if let vocBuffer = AVAudioPCMBuffer(pcmFormat: vocalFile.processingFormat, frameCapacity: vocFrames) {
                    try vocalFile.read(into: vocBuffer, frameCount: vocFrames)
                    mixBuffer(vocBuffer, into: outputBuffer, volume: vocalVolume, targetChannels: Int(outputFormat.channelCount))
                }
            }

            try outputFile.write(from: outputBuffer)
            framesRemaining -= framesToRead
        }
    }

    private func mixBuffer(_ source: AVAudioPCMBuffer, into dest: AVAudioPCMBuffer, volume: Float, targetChannels: Int) {
        guard let srcData = source.floatChannelData, let dstData = dest.floatChannelData else { return }
        let srcChannels = Int(source.format.channelCount)
        let frameCount = Int(min(source.frameLength, dest.frameLength))

        for ch in 0..<targetChannels {
            let srcCh = min(ch, srcChannels - 1)
            let src = srcData[srcCh]
            let dst = dstData[ch]
            for i in 0..<frameCount {
                dst[i] += src[i] * volume
            }
        }
    }

    enum MixError: LocalizedError {
        case formatError
        case bufferError

        var errorDescription: String? {
            switch self {
            case .formatError: return "Could not create output audio format."
            case .bufferError: return "Could not create audio buffer."
            }
        }
    }
}
