import SwiftUI

struct CaptureView: View {
    @EnvironmentObject var appState: AppState

    @State private var errorMessage: String?
    @State private var showingPreview = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("Capture System Audio")
                    .font(.largeTitle.bold())

                Text("Play a song in any app (Spotify, YouTube, Apple Music, etc.) then click Start to capture the audio.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            .padding(.top, 20)

            Spacer()

            // Level meter and duration
            if appState.isCapturing {
                VStack(spacing: 16) {
                    // Audio level
                    LevelMeterView(level: appState.captureLevel)
                        .frame(height: 20)
                        .frame(maxWidth: 400)

                    // Duration
                    Text(formatDuration(appState.captureDuration))
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundStyle(.primary)

                    // Recording indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                            .opacity(pulseOpacity)

                        Text("Capturing...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if appState.hasCapturedAudio && !appState.isCapturing {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)

                    Text("Audio captured successfully!")
                        .font(.headline)

                    Button("Preview") {
                        previewCapturedAudio()
                    }
                }
            }

            Spacer()

            // Controls
            VStack(spacing: 12) {
                if appState.isCapturing {
                    Button(action: stopCapture) {
                        Label("Stop Capture", systemImage: "stop.fill")
                            .font(.headline)
                            .frame(width: 200, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(action: startCapture) {
                        Label("Start Capture", systemImage: "record.circle")
                            .font(.headline)
                            .frame(width: 200, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if appState.hasCapturedAudio && !appState.isCapturing {
                    Button("Continue to Separation") {
                        appState.markStageComplete(.capture)
                        appState.currentStage = .separation
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

    private func startCapture() {
        errorMessage = nil
        Task {
            do {
                try await appState.capturer.startCapture(to: appState.project.capturedAudioURL)
                appState.isCapturing = true
                appState.captureDuration = 0

                // Bind level updates
                Task {
                    while appState.isCapturing {
                        appState.captureLevel = appState.capturer.audioLevel
                        appState.captureDuration = appState.capturer.duration
                        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopCapture() {
        Task {
            do {
                _ = try await appState.capturer.stopCapture()
                appState.isCapturing = false
                appState.hasCapturedAudio = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func previewCapturedAudio() {
        Task {
            do {
                try appState.playbackRecorder.playFile(appState.project.capturedAudioURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    @State private var pulseOpacity: Double = 1.0

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Level Meter

struct LevelMeterView: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))

                RoundedRectangle(cornerRadius: 4)
                    .fill(levelGradient)
                    .frame(width: max(0, geo.size.width * CGFloat(min(level, 1.0))))
                    .animation(.easeOut(duration: 0.05), value: level)
            }
        }
    }

    private var levelGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
