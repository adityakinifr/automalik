import SwiftUI

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
                    Text(headlineText)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                statusDot
            }

            Divider().background(Theme.border)

            // Pitch wheel showing detected/selected key
            PitchWheel(key: appState.selectedKey)
                .frame(height: 200)

            Spacer(minLength: 0)

            // Status / action area
            statusArea

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
        .glassCard()
    }

    // MARK: - Status

    private var headlineText: String {
        if appState.isProcessingAutoTune { return "Processing..." }
        if appState.hasAutoTunedRecording { return "Tuned ✓" }
        if appState.hasSeparatedAudio { return "Ready" }
        return "Pitch Correct"
    }

    @ViewBuilder
    private var statusArea: some View {
        if appState.isProcessingAutoTune {
            VStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.cyan)
                Text("Tuning your vocals...")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        } else if appState.hasAutoTunedRecording {
            VStack(spacing: 8) {
                Text("Auto-tuned to \(appState.selectedKey.root.displayName) \(appState.selectedKey.scale.rawValue)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.lime)
                HStack(spacing: 14) {
                    Button {
                        nowPlayingURL = appState.project.rawRecordingURL
                        try? appState.playbackRecorder.playFile(appState.project.rawRecordingURL)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle")
                            Text("Original")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        nowPlayingURL = appState.project.tunedRecordingURL
                        try? appState.playbackRecorder.playFile(appState.project.tunedRecordingURL)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                            Text("Tuned")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        } else if appState.hasSeparatedAudio {
            VStack(spacing: 4) {
                Text("Detected key: \(appState.selectedKey.root.displayName) \(appState.selectedKey.scale.rawValue)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Auto-tune runs automatically when you finish recording")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        } else {
            Text("Isolate vocals first")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
        }
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
}
