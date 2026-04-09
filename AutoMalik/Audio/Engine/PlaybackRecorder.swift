import Foundation
import AVFoundation

@MainActor
class PlaybackRecorder: ObservableObject {
    @Published var isPlaying = false
    @Published var isRecording = false
    @Published var micLevel: Float = 0
    @Published var playbackProgress: Double = 0
    @Published var playbackDuration: TimeInterval = 0

    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var recordingFile: AVAudioFile?
    private var displayTimer: Timer?

    // MARK: - Playback + Recording

    func startPlaybackAndRecording(
        instrumentalURL: URL,
        recordingURL: URL,
        instrumentalVolume: Float,
        micMonitorVolume: Float
    ) throws {
        stop()

        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        // Load instrumental file
        audioFile = try AVAudioFile(forReading: instrumentalURL)
        guard let audioFile else { return }

        let format = audioFile.processingFormat
        playbackDuration = Double(audioFile.length) / format.sampleRate

        // Set up engine
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        playerNode.volume = instrumentalVolume

        // Set up mic recording
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create recording file with matching format
        let recordingSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        recordingFile = try AVAudioFile(
            forWriting: recordingURL,
            settings: recordingSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: true
        )

        // Install tap on mic input
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Write to recording file
            // Convert to mono 44100 if needed
            if let convertedBuffer = self.convertToMono44100(buffer: buffer, from: inputFormat) {
                try? self.recordingFile?.write(from: convertedBuffer)
            } else {
                try? self.recordingFile?.write(from: buffer)
            }

            // Update mic level
            let level = self.calculateLevel(buffer: buffer)
            Task { @MainActor in
                self.micLevel = level
            }
        }

        // Mic monitoring (hear yourself)
        // Route mic to output at low volume for monitoring
        let monitorMixer = AVAudioMixerNode()
        engine.attach(monitorMixer)
        engine.connect(inputNode, to: monitorMixer, format: inputFormat)
        engine.connect(monitorMixer, to: engine.mainMixerNode, format: inputFormat)
        monitorMixer.volume = micMonitorVolume

        // Start engine and schedule playback
        try engine.start()
        playerNode.scheduleFile(audioFile, at: nil)
        playerNode.play()

        isPlaying = true
        isRecording = true

        // Progress timer
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let nodeTime = self.playerNode.lastRenderTime,
                      let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }
                let currentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
                self.playbackProgress = currentTime / self.playbackDuration
                if currentTime >= self.playbackDuration {
                    self.stop()
                }
            }
        }
    }

    func stop() {
        displayTimer?.invalidate()
        displayTimer = nil

        playerNode.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        recordingFile = nil
        audioFile = nil
        isPlaying = false
        isRecording = false
        micLevel = 0
        playbackProgress = 0
    }

    // MARK: - Playback Only

    func playFile(_ url: URL) throws {
        stop()

        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        audioFile = try AVAudioFile(forReading: url)
        guard let audioFile else { return }

        let format = audioFile.processingFormat
        playbackDuration = Double(audioFile.length) / format.sampleRate

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        try engine.start()
        playerNode.scheduleFile(audioFile, at: nil)
        playerNode.play()
        isPlaying = true

        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let nodeTime = self.playerNode.lastRenderTime,
                      let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }
                let currentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
                self.playbackProgress = currentTime / self.playbackDuration
                if currentTime >= self.playbackDuration {
                    self.stop()
                }
            }
        }
    }

    func setInstrumentalVolume(_ volume: Float) {
        playerNode.volume = volume
    }

    // MARK: - Helpers

    private nonisolated func convertToMono44100(buffer: AVAudioPCMBuffer, from format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard format.sampleRate != 44100 || format.channelCount != 1 else { return nil }

        guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: format, to: monoFormat) else { return nil }

        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * 44100.0 / format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameCapacity) else { return nil }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        return status == .haveData ? outputBuffer : nil
    }

    private nonisolated func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelDataValue = channelData.pointee
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var maxVal: Float = 0
        for i in 0..<min(count, 1024) {
            maxVal = max(maxVal, abs(channelDataValue[i]))
        }
        return maxVal
    }
}
