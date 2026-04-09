import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var appState: AppState

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("Record Your Voice")
                    .font(.largeTitle.bold())

                Text("Sing along with the instrumental track. Your voice will be recorded separately.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            .padding(.top, 20)

            // Headphones notice
            HStack(spacing: 8) {
                Image(systemName: "headphones")
                    .foregroundStyle(.orange)
                Text("Use headphones for best results to avoid feedback")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .padding(8)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Recording status
            if appState.isRecording {
                VStack(spacing: 16) {
                    // Playback progress
                    ProgressView(value: appState.playbackRecorder.playbackProgress)
                        .frame(maxWidth: 500)

                    Text(formatDuration(appState.playbackRecorder.playbackProgress * appState.playbackRecorder.playbackDuration))
                        .font(.system(size: 36, weight: .light, design: .monospaced))

                    // Mic level
                    VStack(spacing: 4) {
                        Text("Mic Level")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LevelMeterView(level: appState.playbackRecorder.micLevel)
                            .frame(height: 16)
                            .frame(maxWidth: 300)
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                        Text("Recording...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if appState.hasRecording && !appState.isRecording {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)

                    Text("Recording complete!")
                        .font(.headline)

                    Button("Preview Recording") {
                        playPreview(appState.project.rawRecordingURL)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()

            // Volume controls
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "music.note")
                    Text("Instrumental Volume")
                        .font(.caption)
                    Slider(value: $appState.instrumentalPlaybackVolume, in: 0...1)
                        .frame(maxWidth: 200)
                    Text("\(Int(appState.instrumentalPlaybackVolume * 100))%")
                        .font(.caption)
                        .frame(width: 40)
                }

                HStack {
                    Image(systemName: "mic")
                    Text("Monitor Volume")
                        .font(.caption)
                    Slider(value: $appState.micMonitorVolume, in: 0...1)
                        .frame(maxWidth: 200)
                    Text("\(Int(appState.micMonitorVolume * 100))%")
                        .font(.caption)
                        .frame(width: 40)
                }
            }
            .frame(maxWidth: 400)

            // Controls
            VStack(spacing: 12) {
                if appState.isRecording {
                    Button(action: stopRecording) {
                        Label("Stop Recording", systemImage: "stop.fill")
                            .font(.headline)
                            .frame(width: 200, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(action: startRecording) {
                        Label("Start Recording", systemImage: "record.circle")
                            .font(.headline)
                            .frame(width: 200, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if appState.hasRecording && !appState.isRecording {
                    Button("Continue to Auto-Tune") {
                        appState.markStageComplete(.recording)
                        appState.currentStage = .autoTune
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

    private func startRecording() {
        errorMessage = nil
        do {
            try appState.playbackRecorder.startPlaybackAndRecording(
                instrumentalURL: appState.project.instrumentalURL,
                recordingURL: appState.project.rawRecordingURL,
                instrumentalVolume: appState.instrumentalPlaybackVolume,
                micMonitorVolume: appState.micMonitorVolume
            )
            appState.isRecording = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopRecording() {
        appState.playbackRecorder.stop()
        appState.isRecording = false
        appState.hasRecording = true
    }

    private func playPreview(_ url: URL) {
        do {
            try appState.playbackRecorder.playFile(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
