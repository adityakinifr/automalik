import SwiftUI
import AVFoundation

struct AutoTuneCard: View {
    @EnvironmentObject var appState: AppState
    @Binding var nowPlayingURL: URL?
    @Binding var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                cardIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text("AUTO-TUNE")
                        .font(.system(size: 11, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Pitch Correct")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                statusDot
            }

            Divider().background(Theme.border)

            // Pitch wheel
            PitchWheel(key: appState.selectedKey)
                .frame(height: 180)

            // Key picker
            HStack(spacing: 8) {
                Picker("", selection: $appState.selectedKey.root) {
                    ForEach(NoteName.allCases) { note in
                        Text(note.displayName).tag(note)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .frame(maxWidth: 80)

                Picker("", selection: $appState.selectedKey.scale) {
                    ForEach(ScaleType.allCases) { scale in
                        Text(scale.rawValue).tag(scale)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
            }

            // Strength slider
            VStack(spacing: 4) {
                HStack {
                    Text("STRENGTH")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(Int(appState.autoTuneStrength * 100))%")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(Theme.cyan)
                }
                Slider(value: $appState.autoTuneStrength, in: 0...1)
                    .tint(Theme.purple)
            }

            Spacer(minLength: 0)

            GlowButton(
                appState.isProcessingAutoTune ? "Processing..." : "Apply Auto-Tune",
                systemImage: "tuningfork",
                gradient: Theme.coolGradient,
                isLoading: appState.isProcessingAutoTune
            ) {
                processAutoTune()
            }

            if appState.hasAutoTunedRecording {
                Button {
                    nowPlayingURL = appState.project.tunedRecordingURL
                    try? appState.playbackRecorder.playFile(appState.project.tunedRecordingURL)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                        Text("Play Tuned Vocals")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.lime)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
        .glassCard()
    }

    private var cardIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.coolGradient)
                .frame(width: 40, height: 40)
                .glow(color: Theme.cyan, radius: 10)
            Image(systemName: "tuningfork")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(appState.hasAutoTunedRecording ? Theme.lime : Theme.textTertiary)
            .frame(width: 8, height: 8)
            .glow(color: Theme.lime, radius: 4)
    }

    // MARK: - Actions

    private func processAutoTune() {
        // Allow auto-tuning either user recording OR isolated vocals from any track
        let inputURL: URL
        if appState.hasRecording {
            inputURL = appState.project.rawRecordingURL
        } else if appState.hasSeparatedAudio {
            inputURL = appState.project.vocalsURL
        } else {
            errorMessage = "Record vocals or isolate them from a track first."
            return
        }

        appState.isProcessingAutoTune = true

        Task.detached {
            do {
                let audioFile = try AVAudioFile(forReading: inputURL)
                let format = audioFile.processingFormat
                let frameCount = AVAudioFrameCount(audioFile.length)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    throw NSError(domain: "AutoTune", code: 1)
                }
                try audioFile.read(into: buffer)
                guard let channelData = buffer.floatChannelData else {
                    throw NSError(domain: "AutoTune", code: 2)
                }
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))

                let key = await MainActor.run { self.appState.selectedKey }
                let strength = await MainActor.run { self.appState.autoTuneStrength }
                let pd = await MainActor.run { self.appState.pitchDetector }
                let pc = await MainActor.run { self.appState.pitchCorrector }
                let pv = await MainActor.run { self.appState.phaseVocoder }

                let processed = pc.autoTune(
                    samples: samples,
                    sampleRate: Float(format.sampleRate),
                    key: key,
                    strength: strength,
                    pitchDetector: pd,
                    phaseVocoder: pv
                )

                let outputURL = await MainActor.run { self.appState.project.tunedRecordingURL }
                let outputFile = try AVAudioFile(
                    forWriting: outputURL,
                    settings: format.settings,
                    commonFormat: format.commonFormat,
                    interleaved: format.isInterleaved
                )
                guard let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(processed.count)) else {
                    throw NSError(domain: "AutoTune", code: 3)
                }
                outBuffer.frameLength = AVAudioFrameCount(processed.count)
                let ptr = outBuffer.floatChannelData![0]
                for i in 0..<processed.count { ptr[i] = processed[i] }
                try outputFile.write(from: outBuffer)

                await MainActor.run {
                    self.appState.isProcessingAutoTune = false
                    self.appState.hasAutoTunedRecording = true
                    self.appState.markStageComplete(.autoTune)
                }
            } catch {
                await MainActor.run {
                    self.appState.isProcessingAutoTune = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
