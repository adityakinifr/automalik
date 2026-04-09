import SwiftUI
import AVFoundation

struct VocalsCard: View {
    @EnvironmentObject var appState: AppState
    @Binding var nowPlayingURL: URL?
    @Binding var errorMessage: String?

    @State private var countdown: Int = 0
    @State private var countdownTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                cardIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text("VOCALS")
                        .font(.system(size: 11, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Sing Along")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                statusDot
            }

            Divider().background(Theme.border)

            // Big circular record button (or countdown)
            ZStack {
                if countdown > 0 {
                    Circle()
                        .fill(Theme.primaryGradient)
                        .frame(width: 88, height: 88)
                        .glow(color: Theme.pink, radius: 20)
                    Text("\(countdown)")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    CircleGlowButton(
                        systemImage: appState.playbackRecorder.isRecording ? "stop.fill" : "mic.fill",
                        gradient: appState.playbackRecorder.isRecording ? Theme.warmGradient : Theme.primaryGradient,
                        isActive: appState.playbackRecorder.isRecording
                    ) {
                        toggleRecording()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            // Status / instructions area
            statusArea

            Spacer(minLength: 0)

            // Volume sliders
            VStack(spacing: 8) {
                volumeSlider("Track", value: $appState.instrumentalPlaybackVolume, icon: "music.note", color: Theme.cyan)
                volumeSlider("Guide", value: $appState.guideVocalVolume, icon: "person.wave.2.fill", color: Theme.pink)
                    .onChange(of: appState.guideVocalVolume) { newValue in
                        appState.playbackRecorder.setGuideVolume(newValue)
                    }
                volumeSlider("Mic", value: $appState.micMonitorVolume, icon: "headphones", color: Theme.purple)
            }

            HStack(spacing: 4) {
                Image(systemName: "headphones")
                    .font(.system(size: 9))
                Text("USE HEADPHONES")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
            }
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
        .glassCard()
    }

    // MARK: - Status area

    @ViewBuilder
    private var statusArea: some View {
        if countdown > 0 {
            VStack(spacing: 4) {
                Text("GET READY")
                    .font(.system(size: 11, weight: .black))
                    .tracking(2)
                    .foregroundStyle(Theme.pink)
                Text("Recording starts in...")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        } else if appState.playbackRecorder.isRecording {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.pink).frame(width: 8, height: 8)
                        .glow(color: Theme.pink, radius: 4)
                    Text("RECORDING")
                        .font(.system(size: 11, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Theme.pink)
                }
                let elapsed = appState.playbackRecorder.playbackProgress * appState.playbackRecorder.playbackDuration
                let total = appState.playbackRecorder.playbackDuration
                Text("\(formatDuration(elapsed)) / \(formatDuration(total))")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                Text("Tap stop when finished")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        } else if appState.hasRecording {
            VStack(spacing: 6) {
                Text("Recording captured ✓")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.lime)
                Button {
                    nowPlayingURL = appState.project.rawRecordingURL
                    try? appState.playbackRecorder.playFile(appState.project.rawRecordingURL)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                        Text("Play Recording")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        } else if appState.hasSeparatedAudio {
            VStack(spacing: 4) {
                Text("Ready to record")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text("The instrumental will play.\nSing along — your voice is recorded.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity)
        } else {
            Text("Isolate vocals first")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Components

    private var cardIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.primaryGradient)
                .frame(width: 40, height: 40)
                .glow(color: Theme.pink, radius: 10)
            Image(systemName: "mic.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(appState.hasRecording ? Theme.lime : Theme.textTertiary)
            .frame(width: 8, height: 8)
            .glow(color: Theme.lime, radius: 4)
    }

    private func volumeSlider(_ label: String, value: Binding<Float>, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 36, alignment: .leading)
            Slider(value: value, in: 0...1)
                .tint(color)
            Text("\(Int(value.wrappedValue * 100))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 24, alignment: .trailing)
        }
    }

    // MARK: - Actions

    private func toggleRecording() {
        if appState.playbackRecorder.isRecording {
            appState.playbackRecorder.stop()
            appState.hasRecording = true
            appState.markStageComplete(.recording)
            runAutoTune()
            return
        }

        guard appState.hasSeparatedAudio else {
            errorMessage = "Isolate vocals first to get an instrumental to sing over."
            return
        }

        // Start a 3-second countdown before recording begins
        countdown = 3
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                countdown -= 1
                if countdown <= 0 {
                    countdownTimer?.invalidate()
                    countdownTimer = nil
                    beginRecording()
                }
            }
        }
    }

    private func beginRecording() {
        do {
            try appState.playbackRecorder.startPlaybackAndRecording(
                instrumentalURL: appState.project.instrumentalURL,
                guideVocalURL: appState.project.vocalsURL,
                recordingURL: appState.project.rawRecordingURL,
                instrumentalVolume: appState.instrumentalPlaybackVolume,
                guideVocalVolume: appState.guideVocalVolume,
                micMonitorVolume: appState.micMonitorVolume
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func runAutoTune() {
        let inputURL = appState.project.rawRecordingURL
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
                    NSLog("[AutoMalik] auto-tune failed: \(error)")
                }
            }
        }
    }
}
