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

enum AudioNormalizer {
    struct Analysis {
        let rms: Float
        let peak: Float
    }

    static func normalize(
        inputURL: URL,
        referenceURL: URL,
        outputURL: URL,
        referenceRatio: Float = 0.92,
        maxGainDB: Float = 9,
        peakCeiling: Float = 0.98
    ) throws {
        let inputAnalysis = try analyze(url: inputURL)
        let referenceAnalysis = try analyze(url: referenceURL)

        guard inputAnalysis.rms > 0.00001, referenceAnalysis.rms > 0.00001 else {
            try replaceFile(from: inputURL, to: outputURL)
            return
        }

        let targetRMS = referenceAnalysis.rms * referenceRatio
        let maxGain = pow(10, maxGainDB / 20)
        var gain = min(targetRMS / inputAnalysis.rms, maxGain)

        if inputAnalysis.peak * gain > peakCeiling {
            gain = peakCeiling / max(inputAnalysis.peak, 0.00001)
        }

        if gain.isNaN || gain.isInfinite || gain <= 0 {
            try replaceFile(from: inputURL, to: outputURL)
            return
        }

        try render(inputURL: inputURL, outputURL: outputURL, gain: gain)
    }

    private static func analyze(url: URL) throws -> Analysis {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let bufferSize: AVAudioFrameCount = 8192
        var sumSquares: Double = 0
        var sampleCount: Double = 0
        var peak: Float = 0

        while file.framePosition < file.length {
            let framesToRead = min(bufferSize, AVAudioFrameCount(file.length - file.framePosition))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
                break
            }
            try file.read(into: buffer, frameCount: framesToRead)
            guard let channelData = buffer.floatChannelData else { continue }

            let frames = Int(buffer.frameLength)
            let channels = Int(format.channelCount)
            for channel in 0..<channels {
                let ptr = channelData[channel]
                for frame in 0..<frames {
                    let sample = ptr[frame]
                    sumSquares += Double(sample * sample)
                    peak = max(peak, abs(sample))
                }
            }
            sampleCount += Double(frames * channels)
        }

        let rms = sampleCount > 0 ? Float(sqrt(sumSquares / sampleCount)) : 0
        return Analysis(rms: rms, peak: peak)
    }

    private static func render(inputURL: URL, outputURL: URL, gain: Float) throws {
        let file = try AVAudioFile(forReading: inputURL)
        let format = file.processingFormat

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )

        let bufferSize: AVAudioFrameCount = 8192
        while file.framePosition < file.length {
            let framesToRead = min(bufferSize, AVAudioFrameCount(file.length - file.framePosition))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
                break
            }
            try file.read(into: buffer, frameCount: framesToRead)

            if let channelData = buffer.floatChannelData {
                let frames = Int(buffer.frameLength)
                let channels = Int(format.channelCount)
                for channel in 0..<channels {
                    let ptr = channelData[channel]
                    for frame in 0..<frames {
                        ptr[frame] *= gain
                    }
                }
            }

            try outputFile.write(from: buffer)
        }
    }

    private static func replaceFile(from sourceURL: URL, to destURL: URL) throws {
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
    }
}
