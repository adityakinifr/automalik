import SwiftUI

struct SourceCard: View {
    @EnvironmentObject var appState: AppState
    @Binding var isImporting: Bool
    @Binding var nowPlayingURL: URL?
    @Binding var errorMessage: String?

    @State private var isSeparating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                cardIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text("SOURCE")
                        .font(.system(size: 11, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Get Your Track")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                statusDot
            }

            Divider().background(Theme.border)

            // Body content
            VStack(spacing: 12) {
                if appState.hasCapturedAudio {
                    capturedState
                } else if appState.isCapturing {
                    capturingState
                } else {
                    emptyState
                }

                if appState.hasCapturedAudio {
                    separateButton
                }

                if appState.hasSeparatedAudio {
                    separationResults
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
        .glassCard()
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(Theme.purple)
                .glow(color: Theme.purple, radius: 12)

            Text("Drop a song or capture\nfrom system audio")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 8) {
                GlowButton("Import File", systemImage: "square.and.arrow.down.fill", gradient: Theme.coolGradient) {
                    isImporting = true
                }

                Button {
                    startCapture()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle")
                        Text("Capture System Audio")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Capsule().strokeBorder(Theme.purple, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    private var capturingState: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.pink)
                    .frame(width: 10, height: 10)
                    .glow(color: Theme.pink, radius: 6)
                Text("CAPTURING")
                    .font(.system(size: 11, weight: .black))
                    .tracking(2)
                    .foregroundStyle(Theme.pink)
            }

            Text(formatDuration(appState.captureDuration))
                .font(.system(size: 36, weight: .black, design: .monospaced))
                .foregroundStyle(.white)

            GlowButton("Stop Capture", systemImage: "stop.fill", gradient: Theme.warmGradient) {
                stopCapture()
            }
        }
        .padding(.vertical, 8)
    }

    private var capturedState: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.lime)
                Text("Source loaded")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Button("Play Source") {
                nowPlayingURL = appState.project.capturedAudioURL
                try? appState.playbackRecorder.playFile(appState.project.capturedAudioURL)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.cyan)
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var separateButton: some View {
        if !appState.hasSeparatedAudio {
            GlowButton(
                isSeparating ? "Separating..." : "Isolate Vocals",
                systemImage: "waveform.path.ecg",
                gradient: Theme.primaryGradient,
                isLoading: isSeparating
            ) {
                runSeparation()
            }

            if isSeparating {
                ProgressView(value: appState.demucsRunner.progress)
                    .tint(Theme.purple)
                Text(appState.demucsRunner.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var separationResults: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.lime)
                Text("Separated")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 8) {
                stemPill("Instrumental", url: appState.project.instrumentalURL, color: Theme.cyan)
                stemPill("Vocals", url: appState.project.vocalsURL, color: Theme.pink)
            }
        }
        .padding(.top, 4)
    }

    private func stemPill(_ label: String, url: URL, color: Color) -> some View {
        Button {
            nowPlayingURL = url
            try? appState.playbackRecorder.playFile(url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.fill").font(.system(size: 9))
                Text(label).font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.2)))
            .overlay(Capsule().strokeBorder(color, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header bits

    private var cardIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.coolGradient)
                .frame(width: 40, height: 40)
                .glow(color: Theme.cyan, radius: 10)
            Image(systemName: "music.note")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(appState.hasSeparatedAudio ? Theme.lime : (appState.hasCapturedAudio ? Theme.cyan : Theme.textTertiary))
            .frame(width: 8, height: 8)
            .glow(color: appState.hasSeparatedAudio ? Theme.lime : Theme.cyan, radius: 4)
    }

    // MARK: - Actions

    private func startCapture() {
        Task {
            do {
                try await appState.capturer.startCapture(to: appState.project.capturedAudioURL)
                appState.isCapturing = true
                appState.captureDuration = 0
                Task {
                    while appState.isCapturing {
                        appState.captureLevel = appState.capturer.audioLevel
                        appState.captureDuration = appState.capturer.duration
                        try? await Task.sleep(nanoseconds: 50_000_000)
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
                appState.markStageComplete(.capture)
                nowPlayingURL = appState.project.capturedAudioURL
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runSeparation() {
        Task {
            isSeparating = true
            defer { isSeparating = false }

            // Setup if needed
            if !appState.demucsRunner.isSetUp {
                let ok = await appState.demucsRunner.checkSetup()
                if !ok {
                    do {
                        try await appState.demucsRunner.setup()
                    } catch {
                        errorMessage = error.localizedDescription
                        return
                    }
                }
            }

            do {
                let result = try await appState.demucsRunner.separate(
                    inputFile: appState.project.capturedAudioURL,
                    outputDir: appState.project.directory
                )
                let fm = FileManager.default
                if fm.fileExists(atPath: appState.project.instrumentalURL.path) {
                    try fm.removeItem(at: appState.project.instrumentalURL)
                }
                if fm.fileExists(atPath: appState.project.vocalsURL.path) {
                    try fm.removeItem(at: appState.project.vocalsURL)
                }
                try fm.copyItem(at: result.instrumental, to: appState.project.instrumentalURL)
                try fm.copyItem(at: result.vocals, to: appState.project.vocalsURL)
                appState.hasSeparatedAudio = true
                appState.markStageComplete(.separation)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        let t = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", m, s, t)
    }
}
