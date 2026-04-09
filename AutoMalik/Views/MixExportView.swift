import SwiftUI
import UniformTypeIdentifiers

struct MixExportView: View {
    @EnvironmentObject var appState: AppState

    @State private var errorMessage: String?
    @State private var isMixing = false
    @State private var showExportPanel = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("Mix & Export")
                    .font(.largeTitle.bold())

                Text("Adjust the mix levels and export your final track.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            .padding(.top, 20)

            Spacer()

            // Mix controls
            VStack(spacing: 20) {
                Text("Mix Levels")
                    .font(.headline)

                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "music.note")
                            .frame(width: 24)
                        Text("Instrumental")
                            .frame(width: 100, alignment: .leading)
                        Slider(value: $appState.instrumentalMixVolume, in: 0...1)
                            .frame(maxWidth: 300)
                        Text("\(Int(appState.instrumentalMixVolume * 100))%")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 50)
                    }

                    HStack {
                        Image(systemName: "mic.fill")
                            .frame(width: 24)
                        Text("Vocals")
                            .frame(width: 100, alignment: .leading)
                        Slider(value: $appState.vocalMixVolume, in: 0...1)
                            .frame(maxWidth: 300)
                        Text("\(Int(appState.vocalMixVolume * 100))%")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 50)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 550)

            Spacer()

            // Status
            if isMixing {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Mixing tracks...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if appState.hasFinalMix {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)

                    Text("Mix complete!")
                        .font(.headline)

                    Button("Play Final Mix") {
                        playPreview(appState.project.finalMixURL)
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Controls
            VStack(spacing: 12) {
                if !isMixing {
                    Button(action: createMix) {
                        Label("Create Mix", systemImage: "wand.and.stars")
                            .font(.headline)
                            .frame(width: 200, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if appState.hasFinalMix {
                    Button("Export as WAV") {
                        exportFile()
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

    private func createMix() {
        errorMessage = nil
        isMixing = true

        let vocalSource = appState.hasAutoTunedRecording
            ? appState.project.tunedRecordingURL
            : appState.project.rawRecordingURL

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
                    self.isMixing = false
                    self.appState.hasFinalMix = true
                    self.appState.markStageComplete(.mixExport)
                }
            } catch {
                await MainActor.run {
                    self.isMixing = false
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

    private func playPreview(_ url: URL) {
        do {
            try appState.playbackRecorder.playFile(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
