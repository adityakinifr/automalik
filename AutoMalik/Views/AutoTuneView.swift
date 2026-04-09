import SwiftUI
import AVFoundation

struct AutoTuneView: View {
    @EnvironmentObject var appState: AppState

    @State private var errorMessage: String?
    @State private var isPreviewingBefore = false
    @State private var isPreviewingAfter = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "tuningfork")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("Auto-Tune")
                    .font(.largeTitle.bold())

                Text("Apply pitch correction to your recorded vocals. Choose a key and adjust the strength.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            .padding(.top, 20)

            Spacer()

            // Auto-tune controls
            VStack(spacing: 20) {
                // Enable toggle
                Toggle("Enable Auto-Tune", isOn: $appState.autoTuneEnabled)
                    .toggleStyle(.switch)
                    .frame(maxWidth: 300)

                if appState.autoTuneEnabled {
                    // Key selection
                    KeyScalePicker(
                        selectedRoot: $appState.selectedKey.root,
                        selectedScale: $appState.selectedKey.scale
                    )

                    // Strength slider
                    VStack(spacing: 4) {
                        HStack {
                            Text("Correction Strength")
                                .font(.headline)
                            Spacer()
                            Text("\(Int(appState.autoTuneStrength * 100))%")
                                .font(.system(.body, design: .monospaced))
                        }

                        Slider(value: $appState.autoTuneStrength, in: 0...1)

                        HStack {
                            Text("Natural")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Full Snap")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 400)
                }
            }

            Spacer()

            // Processing status
            if appState.isProcessingAutoTune {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Applying auto-tune...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if appState.hasAutoTunedRecording {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)

                    Text("Auto-tune applied!")
                        .font(.headline)

                    // Before/After comparison
                    HStack(spacing: 16) {
                        Button("Play Original") {
                            playPreview(appState.project.rawRecordingURL)
                        }
                        .buttonStyle(.bordered)

                        Button("Play Auto-Tuned") {
                            playPreview(appState.project.tunedRecordingURL)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            // Controls
            VStack(spacing: 12) {
                if !appState.isProcessingAutoTune {
                    Button(action: processAutoTune) {
                        Label(
                            appState.autoTuneEnabled ? "Apply Auto-Tune" : "Skip Auto-Tune",
                            systemImage: appState.autoTuneEnabled ? "tuningfork" : "arrow.right"
                        )
                        .font(.headline)
                        .frame(width: 220, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if appState.hasAutoTunedRecording || !appState.autoTuneEnabled {
                    Button("Continue to Mix & Export") {
                        appState.markStageComplete(.autoTune)
                        appState.currentStage = .mixExport
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func processAutoTune() {
        errorMessage = nil

        if !appState.autoTuneEnabled {
            // Skip auto-tune - just copy raw recording
            let fm = FileManager.default
            do {
                if fm.fileExists(atPath: appState.project.tunedRecordingURL.path) {
                    try fm.removeItem(at: appState.project.tunedRecordingURL)
                }
                try fm.copyItem(at: appState.project.rawRecordingURL, to: appState.project.tunedRecordingURL)
                appState.hasAutoTunedRecording = true
                appState.markStageComplete(.autoTune)
                appState.currentStage = .mixExport
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        appState.isProcessingAutoTune = true

        Task.detached {
            do {
                // Read the raw recording
                let audioFile = try AVAudioFile(forReading: await MainActor.run { self.appState.project.rawRecordingURL })
                let format = audioFile.processingFormat
                let frameCount = AVAudioFrameCount(audioFile.length)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    throw AutoTuneError.bufferError
                }
                try audioFile.read(into: buffer)

                // Extract samples
                guard let channelData = buffer.floatChannelData else {
                    throw AutoTuneError.noData
                }
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))

                // Get settings from main actor
                let key = await MainActor.run { self.appState.selectedKey }
                let strength = await MainActor.run { self.appState.autoTuneStrength }
                let pitchDetector = await MainActor.run { self.appState.pitchDetector }
                let pitchCorrector = await MainActor.run { self.appState.pitchCorrector }
                let phaseVocoder = await MainActor.run { self.appState.phaseVocoder }

                // Process
                let processed = pitchCorrector.autoTune(
                    samples: samples,
                    sampleRate: Float(format.sampleRate),
                    key: key,
                    strength: strength,
                    pitchDetector: pitchDetector,
                    phaseVocoder: phaseVocoder
                )

                // Write output
                let outputURL = await MainActor.run { self.appState.project.tunedRecordingURL }
                let outputFile = try AVAudioFile(
                    forWriting: outputURL,
                    settings: format.settings,
                    commonFormat: format.commonFormat,
                    interleaved: format.isInterleaved
                )

                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(processed.count)) else {
                    throw AutoTuneError.bufferError
                }
                outputBuffer.frameLength = AVAudioFrameCount(processed.count)
                let outPtr = outputBuffer.floatChannelData![0]
                for i in 0..<processed.count {
                    outPtr[i] = processed[i]
                }
                try outputFile.write(from: outputBuffer)

                await MainActor.run {
                    self.appState.isProcessingAutoTune = false
                    self.appState.hasAutoTunedRecording = true
                }
            } catch {
                await MainActor.run {
                    self.appState.isProcessingAutoTune = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func playPreview(_ url: URL) {
        do {
            try appState.playbackRecorder.playFile(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    enum AutoTuneError: LocalizedError {
        case bufferError
        case noData

        var errorDescription: String? {
            switch self {
            case .bufferError: return "Could not create audio buffer."
            case .noData: return "No audio data found in recording."
            }
        }
    }
}
