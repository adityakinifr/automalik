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
    private var guideNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var guideFile: AVAudioFile?
    private var recordingFile: AVAudioFile?
    private var displayTimer: Timer?
    private var onPlaybackComplete: (() -> Void)?
    private var seekOffsetSeconds: Double = 0

    // MARK: - Playback + Recording

    func startPlaybackAndRecording(
        instrumentalURL: URL,
        guideVocalURL: URL?,
        recordingURL: URL,
        instrumentalVolume: Float,
        guideVocalVolume: Float,
        micMonitorVolume: Float,
        onComplete: (() -> Void)? = nil
    ) throws {
        stop()

        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        guideNode = AVAudioPlayerNode()

        // Load instrumental file
        audioFile = try AVAudioFile(forReading: instrumentalURL)
        guard let audioFile else { return }

        let format = audioFile.processingFormat
        playbackDuration = Double(audioFile.length) / format.sampleRate

        // Set up instrumental player
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        playerNode.volume = instrumentalVolume

        // Set up guide vocal player (optional)
        if let guideURL = guideVocalURL, guideVocalVolume > 0 {
            do {
                guideFile = try AVAudioFile(forReading: guideURL)
                if let guideFile {
                    let guideFormat = guideFile.processingFormat
                    engine.attach(guideNode)
                    engine.connect(guideNode, to: engine.mainMixerNode, format: guideFormat)
                    guideNode.volume = guideVocalVolume
                }
            } catch {
                NSLog("[PlaybackRecorder] couldn't load guide vocal: \(error)")
                guideFile = nil
            }
        } else {
            guideFile = nil
        }

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
        if let guideFile {
            guideNode.scheduleFile(guideFile, at: nil)
        }

        // Start both nodes simultaneously for sync
        let now = AVAudioTime(hostTime: mach_absolute_time())
        playerNode.play(at: now)
        if guideFile != nil {
            guideNode.play(at: now)
        }

        isPlaying = true
        isRecording = true
        onPlaybackComplete = onComplete

        // Progress timer
        seekOffsetSeconds = 0
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let nodeTime = self.playerNode.lastRenderTime,
                      let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }
                let currentTime = self.seekOffsetSeconds + Double(playerTime.sampleTime) / playerTime.sampleRate
                self.playbackProgress = currentTime / self.playbackDuration
                if currentTime >= self.playbackDuration {
                    let completion = self.onPlaybackComplete
                    self.stop()
                    completion?()
                }
            }
        }
    }

    func stop() {
        displayTimer?.invalidate()
        displayTimer = nil

        playerNode.stop()
        guideNode.stop()
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        recordingFile = nil
        audioFile = nil
        guideFile = nil
        onPlaybackComplete = nil
        seekOffsetSeconds = 0
        isPlaying = false
        isRecording = false
        micLevel = 0
        playbackProgress = 0
    }

    func setGuideVolume(_ volume: Float) {
        guideNode.volume = volume
    }

    /// Seek the current playback to the given time. No-op if nothing is loaded
    /// or while recording (seeking mid-record would corrupt the take).
    func seek(to seconds: TimeInterval) {
        guard let audioFile, !isRecording, playbackDuration > 0 else { return }

        let format = audioFile.processingFormat
        let totalFrames = AVAudioFramePosition(audioFile.length)
        let target = max(0, min(totalFrames - 1, AVAudioFramePosition(seconds * format.sampleRate)))
        let remaining = AVAudioFrameCount(totalFrames - target)
        guard remaining > 0 else { return }

        let wasPlaying = isPlaying
        playerNode.stop()
        guideNode.stop()

        playerNode.scheduleSegment(audioFile, startingFrame: target, frameCount: remaining, at: nil)
        if let guideFile {
            let gFormat = guideFile.processingFormat
            let gTotal = AVAudioFramePosition(guideFile.length)
            let gTarget = max(0, min(gTotal - 1, AVAudioFramePosition(seconds * gFormat.sampleRate)))
            let gRemaining = AVAudioFrameCount(gTotal - gTarget)
            if gRemaining > 0 {
                guideNode.scheduleSegment(guideFile, startingFrame: gTarget, frameCount: gRemaining, at: nil)
            }
        }

        seekOffsetSeconds = seconds
        playbackProgress = seconds / playbackDuration

        if wasPlaying {
            let now = AVAudioTime(hostTime: mach_absolute_time())
            playerNode.play(at: now)
            if guideFile != nil { guideNode.play(at: now) }
        }
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
        seekOffsetSeconds = 0

        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let nodeTime = self.playerNode.lastRenderTime,
                      let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }
                let currentTime = self.seekOffsetSeconds + Double(playerTime.sampleTime) / playerTime.sampleRate
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

    /// Play an instrumental track and a vocal track in sync, for previewing
    /// the tuned (or raw) vocals blended with the backing music.
    func playFilesTogether(
        instrumentalURL: URL,
        vocalURL: URL,
        instrumentalVolume: Float = 0.7,
        vocalVolume: Float = 1.0
    ) throws {
        stop()

        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        guideNode = AVAudioPlayerNode()

        audioFile = try AVAudioFile(forReading: instrumentalURL)
        guideFile = try AVAudioFile(forReading: vocalURL)
        guard let audioFile, let guideFile else { return }

        let instFormat = audioFile.processingFormat
        let vocFormat = guideFile.processingFormat

        let instSeconds = Double(audioFile.length) / instFormat.sampleRate
        let vocSeconds = Double(guideFile.length) / vocFormat.sampleRate
        playbackDuration = max(instSeconds, vocSeconds)

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: instFormat)
        playerNode.volume = instrumentalVolume

        engine.attach(guideNode)
        engine.connect(guideNode, to: engine.mainMixerNode, format: vocFormat)
        guideNode.volume = vocalVolume

        try engine.start()
        playerNode.scheduleFile(audioFile, at: nil)
        guideNode.scheduleFile(guideFile, at: nil)

        let startTime = AVAudioTime(hostTime: mach_absolute_time())
        playerNode.play(at: startTime)
        guideNode.play(at: startTime)

        isPlaying = true
        seekOffsetSeconds = 0

        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let nodeTime = self.playerNode.lastRenderTime,
                      let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }
                let currentTime = self.seekOffsetSeconds + Double(playerTime.sampleTime) / playerTime.sampleRate
                self.playbackProgress = currentTime / self.playbackDuration
                if currentTime >= self.playbackDuration {
                    self.stop()
                }
            }
        }
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
