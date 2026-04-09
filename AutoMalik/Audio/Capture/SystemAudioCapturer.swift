import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreGraphics
import AppKit

@MainActor
class SystemAudioCapturer: NSObject, ObservableObject {
    @Published var isCapturing = false
    @Published var audioLevel: Float = 0
    @Published var duration: TimeInterval = 0

    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private var timer: Timer?
    private var streamOutputHandler: StreamOutputHandler?
    private var startedAt: Date?

    private let sampleRate: Double = 48000  // ScreenCaptureKit's native rate
    private let channelCount: Int = 2

    // MARK: - Permission helpers

    static func hasScreenRecordingPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecordingPermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Capture lifecycle

    func startCapture(to url: URL) async throws {
        NSLog("[Capturer] startCapture entered")
        outputURL = url

        if !CGPreflightScreenCaptureAccess() {
            let granted = CGRequestScreenCaptureAccess()
            if !granted {
                throw CaptureError.permissionDenied
            }
        }
        NSLog("[Capturer] permission OK")

        // Get shareable content
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            NSLog("[Capturer] SCShareableContent error: \(error)")
            throw CaptureError.permissionDenied
        }
        NSLog("[Capturer] got shareable content")

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        // Configure audio-only capture
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.channelCount = channelCount
        config.sampleRate = Int(sampleRate)
        config.width = 2
        config.height = 2

        let filter = SCContentFilter(display: display, excludingWindows: [])
        NSLog("[Capturer] created filter")

        // Prepare output file path - we'll create the AVAudioFile lazily on first sample
        // since we need to know the actual format from the incoming buffer
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        self.audioFile = nil

        // Create and start the stream
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let outputHandler = StreamOutputHandler(capturer: self)
        try stream.addStreamOutput(outputHandler, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        self.streamOutputHandler = outputHandler
        NSLog("[Capturer] starting stream...")

        try await stream.startCapture()
        NSLog("[Capturer] stream started successfully")

        self.stream = stream
        self.isCapturing = true
        self.duration = 0
        self.startedAt = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let started = self.startedAt else { return }
                self.duration = Date().timeIntervalSince(started)
            }
        }
    }

    func stopCapture() async throws -> URL {
        NSLog("[Capturer] stopCapture")
        timer?.invalidate()
        timer = nil

        if let stream = stream {
            try? await stream.stopCapture()
            self.stream = nil
        }

        // Close the audio file by releasing it
        self.audioFile = nil
        self.streamOutputHandler = nil
        self.isCapturing = false
        self.audioLevel = 0

        guard let url = outputURL else {
            throw CaptureError.noOutput
        }
        NSLog("[Capturer] capture stopped, file at \(url.path)")
        return url
    }

    // MARK: - Buffer handling

    nonisolated func handleAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pcmBuffer = Self.pcmBuffer(from: sampleBuffer) else { return }
        let level = Self.peakLevel(in: pcmBuffer)

        Task { @MainActor in
            do {
                if self.audioFile == nil, let url = self.outputURL {
                    // Create the audio file with the format from the first buffer
                    let format = pcmBuffer.format
                    NSLog("[Capturer] creating AVAudioFile with format: \(format)")
                    self.audioFile = try AVAudioFile(
                        forWriting: url,
                        settings: format.settings,
                        commonFormat: format.commonFormat,
                        interleaved: format.isInterleaved
                    )
                    NSLog("[Capturer] AVAudioFile created successfully")
                }

                if let file = self.audioFile {
                    try file.write(from: pcmBuffer)
                }
                self.audioLevel = level
            } catch {
                NSLog("[Capturer] write error: \(error)")
            }
        }
    }

    // MARK: - Conversion helpers

    private nonisolated static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }

        var asbdCopy = asbd.pointee
        guard let avFormat = AVAudioFormat(streamDescription: &asbdCopy) else { return nil }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        // Copy bytes
        let audioBufferList = buffer.mutableAudioBufferList
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: audioBufferList
        )

        return status == noErr ? buffer : nil
    }

    private nonisolated static func peakLevel(in buffer: AVAudioPCMBuffer) -> Float {
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

    enum CaptureError: LocalizedError {
        case noDisplay
        case noOutput
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No display found for audio capture."
            case .noOutput: return "No output file was created."
            case .permissionDenied:
                return "Screen Recording permission is required to capture system audio. Open System Settings → Privacy & Security → Screen Recording, enable AutoMalik, then quit and relaunch the app."
            }
        }
    }
}

// Separate class for SCStreamOutput conformance
private class StreamOutputHandler: NSObject, SCStreamOutput {
    private let capturer: SystemAudioCapturer

    init(capturer: SystemAudioCapturer) {
        self.capturer = capturer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        capturer.handleAudioBuffer(sampleBuffer)
    }
}
