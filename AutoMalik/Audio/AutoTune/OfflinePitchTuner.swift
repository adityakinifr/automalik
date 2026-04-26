import Foundation
import AVFoundation

/// Offline auto-tune that renders the source file through AVAudioUnitTimePitch,
/// updating the pitch parameter per detected-pitch hop. Uses Apple's production
/// pitch shifter to avoid the artifacts of a hand-rolled phase vocoder.
final class OfflinePitchTuner {

    enum TunerError: Error {
        case readFailure
        case bufferFailure
        case renderFailure
    }

    func tune(
        inputURL: URL,
        outputURL: URL,
        key: MusicalKey,
        strength: Float,
        pitchDetector: PitchDetector
    ) throws {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let inputFormat = inputFile.processingFormat
        let totalFrames = AVAudioFramePosition(inputFile.length)
        guard totalFrames > 0 else { return }

        guard let readBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(totalFrames)
        ) else { throw TunerError.bufferFailure }
        try inputFile.read(into: readBuffer)
        guard let channelData = readBuffer.floatChannelData else {
            throw TunerError.readFailure
        }
        let frameLength = Int(readBuffer.frameLength)
        let channelCount = Int(inputFormat.channelCount)
        var samples = [Float](repeating: 0, count: frameLength)
        if channelCount <= 1 {
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        } else {
            for channel in 0..<channelCount {
                let ptr = channelData[channel]
                for frame in 0..<frameLength {
                    samples[frame] += ptr[frame] / Float(channelCount)
                }
            }
        }

        let analysisDetector = PitchDetector(
            sampleRate: Float(inputFormat.sampleRate),
            frameSize: 4096,
            threshold: 0.18
        )
        let hopSize = 2048
        let rawPitches = analysisDetector.detectPitches(in: samples, hopSize: hopSize)
        let centsTimeline = buildCentsTimeline(
            pitches: rawPitches,
            hopSize: hopSize,
            key: key,
            strength: strength
        )

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: inputFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: inputFormat)

        let maxFrames: AVAudioFrameCount = 1024
        try engine.enableManualRenderingMode(
            .offline,
            format: inputFormat,
            maximumFrameCount: maxFrames
        )
        try engine.start()
        player.scheduleFile(inputFile, at: nil)
        player.play()

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputSettings,
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )

        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: maxFrames
        ) else { throw TunerError.bufferFailure }

        var rendered: AVAudioFramePosition = 0
        while rendered < totalFrames {
            let sampleOffset = Int(rendered)
            timePitch.pitch = centsForOffset(sampleOffset, timeline: centsTimeline)

            let framesToRender = AVAudioFrameCount(min(
                Int64(maxFrames),
                totalFrames - rendered
            ))

            let status = try engine.renderOffline(framesToRender, to: renderBuffer)
            switch status {
            case .success:
                if renderBuffer.frameLength > 0 {
                    try outputFile.write(from: renderBuffer)
                }
                rendered += AVAudioFramePosition(renderBuffer.frameLength)
            case .insufficientDataFromInputNode:
                rendered += AVAudioFramePosition(renderBuffer.frameLength)
            case .cannotDoInCurrentContext:
                continue
            case .error:
                throw TunerError.renderFailure
            @unknown default:
                throw TunerError.renderFailure
            }
        }

        player.stop()
        engine.stop()
    }

    private struct CentsPoint {
        var sampleOffset: Int
        var cents: Float
    }

    private func buildCentsTimeline(
        pitches: [(Int, Float)],
        hopSize: Int,
        key: MusicalKey,
        strength: Float
    ) -> [CentsPoint] {
        let effectiveStrength = min(max(strength, 0), 0.75)
        var smoothed: Float = 0
        var points: [CentsPoint] = []
        points.reserveCapacity(pitches.count)

        for (frameIdx, freq) in pitches {
            var target = smoothed * 0.985
            if freq > 60 && freq < 1200 {
                let snapped = key.nearestValidFrequency(freq)
                let centsOff = 1200 * log2(snapped / freq)
                if abs(centsOff) < 700 {
                    target = effectiveStrength * centsOff
                }
            }
            let smoothing: Float = abs(target - smoothed) > 90 ? 0.10 : 0.055
            smoothed += (target - smoothed) * smoothing
            let clamped = max(-900, min(900, smoothed))
            points.append(CentsPoint(
                sampleOffset: frameIdx * hopSize,
                cents: clamped
            ))
        }
        return points
    }

    private func centsForOffset(_ offset: Int, timeline: [CentsPoint]) -> Float {
        guard !timeline.isEmpty else { return 0 }
        if offset <= timeline[0].sampleOffset {
            return timeline[0].cents
        }
        var lo = 0
        var hi = timeline.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if timeline[mid].sampleOffset <= offset {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        let next = min(lo + 1, timeline.count - 1)
        guard next != lo else { return timeline[lo].cents }
        let start = timeline[lo]
        let end = timeline[next]
        let span = max(1, end.sampleOffset - start.sampleOffset)
        let t = Float(offset - start.sampleOffset) / Float(span)
        return start.cents + (end.cents - start.cents) * t
    }
}
