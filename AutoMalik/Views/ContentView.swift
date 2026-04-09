import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    @State private var errorMessage: String?
    @State private var nowPlayingURL: URL?
    @State private var isImporting = false

    var body: some View {
        ZStack {
            AnimatedBackground()

            VStack(spacing: 20) {
                header
                heroSection
                cardRow
                exportBar
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1100, minHeight: 760)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audio, .wav, .mp3, .mpeg4Audio],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.primaryGradient)
                        .frame(width: 44, height: 44)
                        .glow(color: Theme.purple, radius: 16)
                    Image(systemName: "tuningfork")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("AUTOMALIK")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white)
                    Text("Karaoke Auto-Tuner")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            Button {
                appState.newProject()
                nowPlayingURL = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("New Session")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Hero (waveform + now playing)

    private var heroSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(nowPlayingTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text(nowPlayingSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()

                if nowPlayingURL != nil {
                    HStack(spacing: 12) {
                        Button { togglePlay() } label: {
                            Image(systemName: appState.playbackRecorder.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Theme.cyan)
                                .glow(color: Theme.cyan, radius: 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)

            AnimatedWaveform(
                audioURL: nowPlayingURL,
                liveLevel: appState.isCapturing ? appState.captureLevel : (appState.playbackRecorder.isRecording ? appState.playbackRecorder.micLevel : 0),
                isPlaying: appState.playbackRecorder.isPlaying,
                progress: appState.playbackRecorder.playbackProgress
            )
            .frame(height: 130)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .padding(.top, 16)
        .glassCard(cornerRadius: 24)
    }

    private var nowPlayingTitle: String {
        if appState.isCapturing { return "● Capturing System Audio..." }
        if appState.playbackRecorder.isRecording { return "● Recording Vocals..." }
        if let url = nowPlayingURL { return url.lastPathComponent }
        return "No track loaded"
    }

    private var nowPlayingSubtitle: String {
        if appState.isCapturing { return "LIVE INPUT" }
        if appState.playbackRecorder.isRecording { return "MIC SIGNAL" }
        if nowPlayingURL != nil { return "READY TO PLAY" }
        return "DROP A FILE OR CAPTURE FROM SYSTEM"
    }

    // MARK: - Cards

    private var cardRow: some View {
        HStack(spacing: 16) {
            SourceCard(
                isImporting: $isImporting,
                nowPlayingURL: $nowPlayingURL,
                errorMessage: $errorMessage
            )
            VocalsCard(
                nowPlayingURL: $nowPlayingURL,
                errorMessage: $errorMessage
            )
            AutoTuneCard(
                nowPlayingURL: $nowPlayingURL,
                errorMessage: $errorMessage
            )
        }
    }

    // MARK: - Export bar

    private var exportBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Theme.textSecondary)
                Text("MIX")
                    .font(.system(size: 11, weight: .black))
                    .tracking(2)
                    .foregroundStyle(Theme.textSecondary)
            }

            mixSlider(label: "Inst", value: $appState.instrumentalMixVolume, color: Theme.cyan)
            mixSlider(label: "Vox", value: $appState.vocalMixVolume, color: Theme.pink)

            Spacer()

            GlowButton(
                "Create Mix",
                systemImage: "wand.and.stars",
                gradient: Theme.coolGradient
            ) {
                createMix()
            }

            GlowButton(
                "Export WAV",
                systemImage: "square.and.arrow.down",
                gradient: Theme.primaryGradient
            ) {
                exportFile()
            }
            .opacity(appState.hasFinalMix ? 1.0 : 0.4)
            .disabled(!appState.hasFinalMix)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassCard(cornerRadius: 20)
    }

    private func mixSlider(label: String, value: Binding<Float>, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 26)
            Slider(value: value, in: 0...1)
                .frame(width: 100)
                .tint(color)
            Text("\(Int(value.wrappedValue * 100))")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 26)
        }
    }

    // MARK: - Actions

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // Copy file into project directory
            do {
                let dest = appState.project.capturedAudioURL
                let fm = FileManager.default
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                try fm.copyItem(at: url, to: dest)
                appState.hasCapturedAudio = true
                appState.markStageComplete(.capture)
                nowPlayingURL = dest
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func togglePlay() {
        if appState.playbackRecorder.isPlaying {
            appState.playbackRecorder.stop()
        } else if let url = nowPlayingURL {
            try? appState.playbackRecorder.playFile(url)
        }
    }

    private func createMix() {
        guard appState.hasSeparatedAudio else {
            errorMessage = "Separate vocals first to create a mix."
            return
        }

        let vocalSource = appState.hasAutoTunedRecording
            ? appState.project.tunedRecordingURL
            : (appState.hasRecording ? appState.project.rawRecordingURL : appState.project.vocalsURL)

        Task.detached {
            do {
                let mixer = AudioMixer()
                let instrumentalURL = await MainActor.run { self.appState.project.instrumentalURL }
                let outputURL = await MainActor.run { self.appState.project.finalMixURL }
                let instVol = await MainActor.run { self.appState.instrumentalMixVolume }
                let vocVol = await MainActor.run { self.appState.vocalMixVolume }

                try mixer.mixTracks(
                    instrumentalURL: instrumentalURL,
                    vocalURL: vocalSource,
                    instrumentalVolume: instVol,
                    vocalVolume: vocVol,
                    outputURL: outputURL
                )

                await MainActor.run {
                    self.appState.hasFinalMix = true
                    self.nowPlayingURL = outputURL
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.wav]
        panel.nameFieldStringValue = "AutoMalik_Mix.wav"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: url.path) {
                    try fm.removeItem(at: url)
                }
                try fm.copyItem(at: appState.project.finalMixURL, to: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
