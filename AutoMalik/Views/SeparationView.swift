import SwiftUI

struct SeparationView: View {
    @EnvironmentObject var appState: AppState

    @State private var errorMessage: String?
    @State private var showSetup = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("Vocal Separation")
                    .font(.largeTitle.bold())

                Text("Separate the vocals from the instrumental using AI-powered source separation.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            .padding(.top, 20)

            Spacer()

            if !appState.demucsRunner.isSetUp && !showSetup {
                // First-time setup needed
                VStack(spacing: 16) {
                    Image(systemName: "gear.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)

                    Text("First-time Setup Required")
                        .font(.headline)

                    Text("AutoMalik uses Demucs (by Meta) for vocal separation. This requires a one-time Python environment setup (~2GB download).")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button("Set Up Demucs") {
                        showSetup = true
                        runSetup()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if showSetup && !appState.demucsRunner.isSetUp {
                // Setup in progress
                VStack(spacing: 16) {
                    ProgressView(value: appState.demucsRunner.progress)
                        .frame(maxWidth: 400)

                    Text(appState.demucsRunner.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if appState.isSeparating {
                // Separation in progress
                VStack(spacing: 16) {
                    ProgressView(value: appState.separationProgress)
                        .frame(maxWidth: 400)

                    Text(appState.demucsRunner.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if appState.separationProgress > 0 {
                        Text("\(Int(appState.separationProgress * 100))%")
                            .font(.system(size: 36, weight: .light, design: .monospaced))
                    } else {
                        ProgressView()
                            .controlSize(.large)
                    }
                }
            } else if appState.hasSeparatedAudio {
                // Separation complete
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)

                    Text("Separation complete!")
                        .font(.headline)

                    HStack(spacing: 20) {
                        Button("Play Instrumental") {
                            playPreview(appState.project.instrumentalURL)
                        }
                        .buttonStyle(.bordered)

                        Button("Play Vocals") {
                            playPreview(appState.project.vocalsURL)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Spacer()

            // Controls
            VStack(spacing: 12) {
                if appState.demucsRunner.isSetUp && !appState.isSeparating && !appState.hasSeparatedAudio {
                    Button("Start Separation") {
                        startSeparation()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if appState.hasSeparatedAudio {
                    Button("Continue to Recording") {
                        appState.markStageComplete(.separation)
                        appState.currentStage = .recording
                    }
                    .buttonStyle(.borderedProminent)
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
        .task {
            // Check if Demucs is already set up
            let isSetup = await appState.demucsRunner.checkSetup()
            if isSetup {
                appState.demucsRunner.isSetUp = true
            }
        }
    }

    // MARK: - Actions

    private func runSetup() {
        Task {
            do {
                try await appState.demucsRunner.setup()
            } catch {
                errorMessage = error.localizedDescription
                showSetup = false
            }
        }
    }

    private func startSeparation() {
        errorMessage = nil
        appState.isSeparating = true

        Task {
            do {
                let result = try await appState.demucsRunner.separate(
                    inputFile: appState.project.capturedAudioURL,
                    outputDir: appState.project.directory
                )

                // Copy output files to expected locations
                let fm = FileManager.default
                if fm.fileExists(atPath: appState.project.instrumentalURL.path) {
                    try fm.removeItem(at: appState.project.instrumentalURL)
                }
                if fm.fileExists(atPath: appState.project.vocalsURL.path) {
                    try fm.removeItem(at: appState.project.vocalsURL)
                }
                try fm.copyItem(at: result.instrumental, to: appState.project.instrumentalURL)
                try fm.copyItem(at: result.vocals, to: appState.project.vocalsURL)

                appState.isSeparating = false
                appState.hasSeparatedAudio = true

                // Update progress from runner
                Task {
                    while appState.isSeparating {
                        appState.separationProgress = appState.demucsRunner.progress
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
            } catch {
                appState.isSeparating = false
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
