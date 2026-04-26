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
                liveToggle
                StepBadge(number: 2, state: appState.vocalsCardState)
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
                    let isActive = appState.playbackRecorder.isRecording || appState.liveAutoTuner.isRunning
                    CircleGlowButton(
                        systemImage: isActive ? "stop.fill" : "mic.fill",
                        gradient: isActive ? Theme.warmGradient : Theme.primaryGradient,
                        isActive: isActive
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
        .cardDimmed(appState.vocalsCardState == .pending)
    }

    // MARK: - Status area

    @ViewBuilder
    private var statusArea: some View {
        if appState.liveAutoTuner.isRunning {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.lime).frame(width: 8, height: 8)
                        .glow(color: Theme.lime, radius: 4)
                    Text("LIVE AUTO-TUNE")
                        .font(.system(size: 11, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Theme.lime)
                }
                if appState.liveAutoTuner.detectedFreq > 0 {
                    Text(MusicalKey.noteName(for: appState.liveAutoTuner.targetFreq))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(Int(appState.liveAutoTuner.detectedFreq)) Hz → \(Int(appState.liveAutoTuner.targetFreq)) Hz")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Sing into your mic")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        } else if countdown > 0 {
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
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.primaryGradient)
                .frame(width: 40, height: 40)
                .glow(color: Theme.pink, radius: 10)
            Image(systemName: "mic.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var liveToggle: some View {
        Button {
            toggleLiveMode()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.isLiveMode ? Theme.lime : Theme.textTertiary)
                    .frame(width: 6, height: 6)
                    .glow(color: appState.isLiveMode ? Theme.lime : .clear, radius: 4)
                Text("LIVE")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(appState.isLiveMode ? Theme.lime : Theme.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(appState.isLiveMode ? Theme.lime.opacity(0.15) : Color.white.opacity(0.05))
                    .overlay(
                        Capsule().strokeBorder(
                            appState.isLiveMode ? Theme.lime : Theme.border,
                            lineWidth: 1
                        )
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
        // LIVE MODE: real-time auto-tune monitoring
        if appState.isLiveMode {
            if appState.liveAutoTuner.isRunning {
                appState.liveAutoTuner.stop()
                if FileManager.default.fileExists(atPath: appState.project.tunedRecordingURL.path) {
                    appState.hasRecording = true
                    appState.hasAutoTunedRecording = true
                    appState.markStageComplete(.recording)
                    appState.markStageComplete(.autoTune)
                }
                return
            }

            requestMicAccess { startLiveMode() }
            return
        }

        // OFFLINE MODE: record then process
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

        requestMicAccess { startCountdown() }
    }

    private func startLiveMode() {
        // Pick the best available instrumental:
        //   1. Demucs-separated instrumental (highest quality)
        //   2. Quick center-cancellation from captured audio (instant)
        //   3. None - just sing without backing
        var instrumentalURL: URL? = nil
        if appState.hasSeparatedAudio {
            instrumentalURL = appState.project.instrumentalURL
        } else if appState.hasCapturedAudio {
            let instantURL = appState.project.directory.appendingPathComponent("instant_instrumental.wav")
            do {
                instrumentalURL = try InstantVocalRemover.removeVocals(
                    from: appState.project.capturedAudioURL,
                    to: instantURL
                )
                NSLog("[AutoMalik] Generated instant instrumental via center cancellation")
            } catch {
                NSLog("[AutoMalik] Instant vocal removal failed: \(error)")
                instrumentalURL = appState.project.capturedAudioURL
            }
        }

        do {
            appState.liveAutoTuner.setKey(appState.selectedKey)
            appState.liveAutoTuner.setStrength(appState.autoTuneStrength)
            try appState.liveAutoTuner.start(
                instrumentalURL: instrumentalURL,
                recordingURL: appState.project.tunedRecordingURL,
                instrumentalVolume: appState.instrumentalPlaybackVolume
            )
        } catch {
            errorMessage = "Live mode failed to start: \(error.localizedDescription)"
        }
    }

    private func startCountdown() {
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

    // Ensures macOS mic permission is granted before starting the engine.
    // Without this, the first tap shows the permission prompt mid-recording
    // and the input tap silently drops buffers until the user retries.
    private func requestMicAccess(_ onGranted: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            onGranted()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    if granted {
                        onGranted()
                    } else {
                        errorMessage = "AutoMalik needs microphone access to record your voice."
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Microphone access is denied. Enable it in System Settings → Privacy & Security → Microphone."
        @unknown default:
            errorMessage = "Microphone access unavailable."
        }
    }

    private func toggleLiveMode() {
        if appState.liveAutoTuner.isRunning {
            appState.liveAutoTuner.stop()
        }
        if appState.playbackRecorder.isRecording {
            appState.playbackRecorder.stop()
        }
        appState.isLiveMode.toggle()
    }

    private func beginRecording() {
        do {
            try appState.playbackRecorder.startPlaybackAndRecording(
                instrumentalURL: appState.project.instrumentalURL,
                guideVocalURL: appState.project.vocalsURL,
                recordingURL: appState.project.rawRecordingURL,
                instrumentalVolume: appState.instrumentalPlaybackVolume,
                guideVocalVolume: appState.guideVocalVolume,
                micMonitorVolume: appState.micMonitorVolume,
                onComplete: {
                    Task { @MainActor in
                        appState.hasRecording = true
                        appState.markStageComplete(.recording)
                        runAutoTune()
                    }
                }
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
        let outputURL = appState.project.tunedRecordingURL
        let key = appState.selectedKey
        let strength = appState.autoTuneStrength
        let tuner = appState.offlinePitchTuner
        let detector = appState.pitchDetector
        appState.isProcessingAutoTune = true

        Task.detached {
            do {
                try tuner.tune(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    key: key,
                    strength: strength,
                    pitchDetector: detector
                )
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
