import Foundation
import AVFoundation
import Accelerate

/// Real-time auto-tune: mic input → pitch detect → pitch shift → output.
/// Uses AVAudioUnitTimePitch for the actual shifting (hardware-accelerated)
/// and updates its pitch parameter ~50x/sec based on detected pitch.
@MainActor
class LiveAutoTuner: ObservableObject {
    @Published var isRunning = false
    @Published var detectedFreq: Float = 0
    @Published var targetFreq: Float = 0
    @Published var micLevel: Float = 0

    private var engine = AVAudioEngine()
    private var timePitch = AVAudioUnitTimePitch()
    private var instrumentalPlayer = AVAudioPlayerNode()
    private var instrumentalFile: AVAudioFile?
    private var recordingFile: AVAudioFile?

    private var pitchDetector = PitchDetector(sampleRate: 44100, frameSize: 2048, threshold: 0.15)
    private let detectionQueue = DispatchQueue(label: "live.autotune.detect", qos: .userInteractive)

    private var key: MusicalKey = MusicalKey(root: .C, scale: .major)
    private var strength: Float = 0.8
    private var smoothedCents: Float = 0  // smoothing for pitch changes

    // Sample buffer for accumulating frames before pitch detection
    private var sampleBuffer: [Float] = []
    private let detectionFrameSize = 2048

    // MARK: - Configuration

    func setKey(_ key: MusicalKey) {
        self.key = key
    }

    func setStrength(_ strength: Float) {
        self.strength = strength
    }

    // MARK: - Lifecycle

    func start(
        instrumentalURL: URL? = nil,
        recordingURL: URL? = nil,
        instrumentalVolume: Float = 0.7
    ) throws {
        stop()

        engine = AVAudioEngine()
        timePitch = AVAudioUnitTimePitch()
        instrumentalPlayer = AVAudioPlayerNode()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        pitchDetector = PitchDetector(
            sampleRate: Float(inputFormat.sampleRate),
            frameSize: detectionFrameSize,
            threshold: 0.18
        )

        // Build chain: inputNode -> timePitch -> mainMixerNode -> outputNode
        engine.attach(timePitch)
        engine.connect(inputNode, to: timePitch, format: inputFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: inputFormat)

        // Optional: instrumental backing track
        if let instrumentalURL {
            do {
                instrumentalFile = try AVAudioFile(forReading: instrumentalURL)
                if let file = instrumentalFile {
                    let fmt = file.processingFormat
                    engine.attach(instrumentalPlayer)
                    engine.connect(instrumentalPlayer, to: engine.mainMixerNode, format: fmt)
                    instrumentalPlayer.volume = instrumentalVolume
                }
            } catch {
                NSLog("[LiveAutoTuner] failed to load instrumental: \(error)")
                instrumentalFile = nil
            }
        }

        // Optional: record the auto-tuned mic output
        if let recordingURL {
            let recordingSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false
            ]
            recordingFile = try AVAudioFile(
                forWriting: recordingURL,
                settings: recordingSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: true
            )
        }

        // Tap the timePitch output (post-tuning) for both pitch detection and recording
        timePitch.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        // Also tap the input (pre-tuning) for accurate pitch detection
        // (the timePitch tap is post-correction, which would interfere with detection)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.detectPitchFromInputBuffer(buffer)
        }

        try engine.start()

        if let file = instrumentalFile {
            instrumentalPlayer.scheduleFile(file, at: nil)
            instrumentalPlayer.play()
        }

        isRunning = true
        sampleBuffer.removeAll()
        smoothedCents = 0
    }

    func stop() {
        if engine.isRunning {
            timePitch.removeTap(onBus: 0)
            engine.inputNode.removeTap(onBus: 0)
            instrumentalPlayer.stop()
            engine.stop()
        }
        recordingFile = nil
        instrumentalFile = nil
        isRunning = false
        detectedFreq = 0
        targetFreq = 0
        micLevel = 0
        timePitch.pitch = 0
    }

    // MARK: - Real-time processing

    private nonisolated func processBuffer(_ buffer: AVAudioPCMBuffer) {
        let level = peakLevel(in: buffer)

        Task { @MainActor in
            // Write the post-tuned audio to the recording file (if recording)
            if let file = self.recordingFile {
                if buffer.format.channelCount == 1 {
                    try? file.write(from: buffer)
                } else if let monoBuffer = LiveAutoTuner.downmix(buffer) {
                    try? file.write(from: monoBuffer)
                }
            }
            self.micLevel = level
        }
    }

    private nonisolated func detectPitchFromInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var samples = [Float](repeating: 0, count: frameCount)
        for channel in 0..<channels {
            let ptr = channelData[channel]
            for frame in 0..<frameCount {
                samples[frame] += ptr[frame] / Float(channels)
            }
        }

        // Run detection on a background queue (not the audio thread)
        detectionQueue.async { [weak self] in
            guard let self else { return }
            self.runDetection(samples: samples)
        }
    }

    private nonisolated func runDetection(samples: [Float]) {
        Task { @MainActor in
            self.sampleBuffer.append(contentsOf: samples)

            // Process whenever we have enough samples
            while self.sampleBuffer.count >= self.detectionFrameSize {
                let frame = Array(self.sampleBuffer.prefix(self.detectionFrameSize))
                self.sampleBuffer.removeFirst(self.detectionFrameSize / 2)  // 50% overlap

                let freq = self.pitchDetector.detectPitch(frame: frame)
                guard freq > 60 && freq < 1200 else { continue }

                let target = self.key.nearestValidFrequency(freq)
                let centsOff = 1200 * log2(target / freq)
                guard abs(centsOff) < 700 else { continue }
                let correctedCents = min(max(self.strength, 0), 0.75) * centsOff

                // Smooth to avoid jumpy pitch changes (one-pole low-pass)
                self.smoothedCents = self.smoothedCents * 0.88 + correctedCents * 0.12

                // Apply to timePitch unit
                self.timePitch.pitch = self.smoothedCents

                self.detectedFreq = freq
                self.targetFreq = target
            }
        }
    }

    // MARK: - Helpers

    private nonisolated func peakLevel(in buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var maxVal: Float = 0
        let ptr = channelData[0]
        for i in 0..<min(frames, 1024) {
            maxVal = max(maxVal, abs(ptr[i]))
        }
        return maxVal
    }

    private nonisolated static func downmix(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)

        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: 1,
            interleaved: true
        ) else { return nil }
        guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        monoBuffer.frameLength = AVAudioFrameCount(frames)

        let dst = monoBuffer.floatChannelData![0]
        for i in 0..<frames {
            var sum: Float = 0
            for ch in 0..<channels {
                sum += channelData[ch][i]
            }
            dst[i] = sum / Float(channels)
        }
        return monoBuffer
    }
}
