import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

@MainActor
class SystemAudioCapturer: NSObject, ObservableObject {
    @Published var isCapturing = false
    @Published var audioLevel: Float = 0
    @Published var duration: TimeInterval = 0

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var startTime: CMTime?
    private var outputURL: URL?
    private var timer: Timer?

    private let sampleRate: Double = 44100
    private let channelCount: Int = 2

    func startCapture(to url: URL) async throws {
        outputURL = url

        // Get shareable content for system audio
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        // Configure for audio-only capture
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.channelCount = channelCount
        config.sampleRate = Int(sampleRate)
        // Minimal video config (required on macOS 13)
        config.width = 2
        config.height = 2

        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Set up AVAssetWriter
        let writer = try AVAssetWriter(outputURL: url, fileType: .wav)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)

        self.assetWriter = writer
        self.audioInput = input
        self.startTime = nil

        writer.startWriting()

        // Create and start stream
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let outputHandler = StreamOutputHandler(capturer: self)
        try stream.addStreamOutput(outputHandler, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        self.streamOutputHandler = outputHandler

        try await stream.startCapture()
        self.stream = stream
        self.isCapturing = true
        self.duration = 0

        // Duration timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.duration += 0.1
            }
        }
    }

    func stopCapture() async throws -> URL {
        timer?.invalidate()
        timer = nil

        if let stream = stream {
            try await stream.stopCapture()
            self.stream = nil
        }

        if let writer = assetWriter {
            audioInput?.markAsFinished()
            await writer.finishWriting()
            self.assetWriter = nil
            self.audioInput = nil
        }

        isCapturing = false
        audioLevel = 0

        guard let url = outputURL else {
            throw CaptureError.noOutput
        }
        return url
    }

    // Handle incoming audio buffers (called from StreamOutputHandler)
    nonisolated func handleAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        Task { @MainActor in
            guard let writer = assetWriter, writer.status == .writing,
                  let input = audioInput, input.isReadyForMoreMediaData else { return }

            if startTime == nil {
                startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                writer.startSession(atSourceTime: startTime!)
            }

            input.append(sampleBuffer)

            // Update level meter
            if let channelData = extractLevel(from: sampleBuffer) {
                self.audioLevel = channelData
            }
        }
    }

    private nonisolated func extractLevel(from sampleBuffer: CMSampleBuffer) -> Float? {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let data = dataPointer else { return nil }
        let floatCount = length / MemoryLayout<Float>.size
        guard floatCount > 0 else { return nil }

        return data.withMemoryRebound(to: Float.self, capacity: floatCount) { floats in
            var maxVal: Float = 0
            for i in 0..<min(floatCount, 1024) {
                maxVal = max(maxVal, abs(floats[i]))
            }
            return maxVal
        }
    }

    private var streamOutputHandler: StreamOutputHandler?

    enum CaptureError: LocalizedError {
        case noDisplay
        case noOutput

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No display found for audio capture."
            case .noOutput: return "No output file was created."
            }
        }
    }
}

// Separate class for SCStreamOutput conformance (non-Sendable isolation)
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
