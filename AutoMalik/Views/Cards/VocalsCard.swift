import SwiftUI

struct VocalsCard: View {
    @EnvironmentObject var appState: AppState
    @Binding var nowPlayingURL: URL?
    @Binding var errorMessage: String?

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

            // Big circular record button
            ZStack {
                CircleGlowButton(
                    systemImage: appState.playbackRecorder.isRecording ? "stop.fill" : "mic.fill",
                    gradient: appState.playbackRecorder.isRecording ? Theme.warmGradient : Theme.primaryGradient,
                    isActive: appState.playbackRecorder.isRecording
                ) {
                    toggleRecording()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            if appState.playbackRecorder.isRecording {
                VStack(spacing: 6) {
                    Text("● REC")
                        .font(.system(size: 11, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Theme.pink)
                    Text(formatDuration(appState.playbackRecorder.playbackProgress * appState.playbackRecorder.playbackDuration))
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                }
            } else if appState.hasRecording {
                Button {
                    nowPlayingURL = appState.project.rawRecordingURL
                    try? appState.playbackRecorder.playFile(appState.project.rawRecordingURL)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                        Text("Play Recording")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
                }
                .buttonStyle(.plain)
            } else {
                Text(appState.hasSeparatedAudio ? "Tap to record over instrumental" : "Separate vocals first")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            // Volume sliders
            VStack(spacing: 8) {
                volumeSlider("Track", value: $appState.instrumentalPlaybackVolume, icon: "music.note", color: Theme.cyan)
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
        } else {
            guard appState.hasSeparatedAudio else {
                errorMessage = "Isolate vocals first to get an instrumental to sing over."
                return
            }
            do {
                try appState.playbackRecorder.startPlaybackAndRecording(
                    instrumentalURL: appState.project.instrumentalURL,
                    recordingURL: appState.project.rawRecordingURL,
                    instrumentalVolume: appState.instrumentalPlaybackVolume,
                    micMonitorVolume: appState.micMonitorVolume
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
