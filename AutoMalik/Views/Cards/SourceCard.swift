import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import AppKit

struct SourceCard: View {
    @EnvironmentObject var appState: AppState
    @Binding var isImporting: Bool
    @Binding var nowPlayingURL: URL?
    @Binding var errorMessage: String?

    @State private var isSeparating = false
    @State private var isDropTargeted = false
    @State private var urlInput = ""
    @State private var isDownloading = false
    @State private var fileInfo: FileInfo?

    struct FileInfo {
        let name: String
        let duration: TimeInterval
        let sizeBytes: Int64
    }

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
                StepBadge(number: 1, state: appState.sourceCardState)
            }

            Divider().background(Theme.border)

            // Body content
            VStack(spacing: 14) {
                if appState.hasCapturedAudio {
                    capturedState
                } else if appState.isCapturing {
                    capturingState
                } else if isDownloading {
                    downloadingState
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

        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard()
        .overlay(
            // Drop target highlight
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.cyan, lineWidth: isDropTargeted ? 3 : 0)
                .glow(color: Theme.cyan, radius: isDropTargeted ? 16 : 0)
                .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: appState.hasCapturedAudio) { newValue in
            if newValue {
                fileInfo = loadFileInfo(url: appState.project.capturedAudioURL)
            } else {
                fileInfo = nil
            }
        }
        .onAppear {
            if appState.hasCapturedAudio {
                fileInfo = loadFileInfo(url: appState.project.capturedAudioURL)
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 12) {
            // Drop zone
            VStack(spacing: 6) {
                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "waveform.badge.plus")
                    .font(.system(size: 32))
                    .foregroundStyle(isDropTargeted ? Theme.cyan : Theme.purple)
                    .glow(color: isDropTargeted ? Theme.cyan : Theme.purple, radius: 12)
                Text(isDropTargeted ? "Drop to import" : "Drop a song here")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDropTargeted ? Theme.cyan : Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            // OR divider
            HStack(spacing: 8) {
                Rectangle().fill(Theme.border).frame(height: 1)
                Text("OR").font(.system(size: 9, weight: .black)).tracking(2).foregroundStyle(Theme.textTertiary)
                Rectangle().fill(Theme.border).frame(height: 1)
            }

            // URL input
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Paste YouTube URL...", text: $urlInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .onSubmit { downloadFromURL() }
                if !urlInput.isEmpty {
                    Button {
                        downloadFromURL()
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            )

            // Two action buttons side by side
            HStack(spacing: 8) {
                Button {
                    isImporting = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 16))
                        Text("Browse")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.coolGradient.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cyan.opacity(0.5), lineWidth: 1))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    NSLog("[AutoMalik] Capture System Audio button tapped")
                    startCapture()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 16))
                        Text("Capture")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.primaryGradient.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.coral.opacity(0.5), lineWidth: 1))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Button {
                loadStepOneSnapshot()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                    Text("Load Saved Step 1")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.mint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.mint.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.mint.opacity(0.35), lineWidth: 1))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private var downloadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.cyan)
            Text("Downloading from URL...")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("This may take a moment")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.mint.opacity(0.16))
                        .frame(width: 42, height: 42)
                    Image(systemName: appState.hasSeparatedAudio ? "checkmark.seal.fill" : "music.note")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.mint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.hasSeparatedAudio ? "Source ready" : "Source loaded")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    if let info = fileInfo {
                        Text(info.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 6) {
                            Label(formatDuration(info.duration), systemImage: "clock")
                            Text("•")
                            Text(formatSize(info.sizeBytes))
                        }
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                    } else {
                        Text("Captured audio is available")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer(minLength: 8)

                sourceIconButton(
                    systemImage: "play.fill",
                    tint: Theme.cyan,
                    help: "Play source"
                ) {
                    nowPlayingURL = appState.project.capturedAudioURL
                    try? appState.playbackRecorder.playFile(appState.project.capturedAudioURL)
                }

                sourceIconButton(
                    systemImage: "arrow.counterclockwise",
                    tint: Theme.pink,
                    help: "Reset source"
                ) {
                    resetSource()
                }
            }

            if appState.hasSeparatedAudio {
                Text("Instrumental and vocal stems are isolated. Preview either stem or save this Step 1 package for later.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(appState.hasSeparatedAudio ? Theme.mint.opacity(0.28) : Theme.border, lineWidth: 1)
        )
    }

    private func resetSource() {
        appState.playbackRecorder.stop()
        if nowPlayingURL == appState.project.capturedAudioURL ||
            nowPlayingURL == appState.project.instrumentalURL ||
            nowPlayingURL == appState.project.vocalsURL {
            nowPlayingURL = nil
        }

        let fm = FileManager.default
        for url in [
            appState.project.capturedAudioURL,
            appState.project.instrumentalURL,
            appState.project.vocalsURL,
            appState.project.stepOneManifestURL
        ] {
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }

        appState.hasCapturedAudio = false
        appState.hasSeparatedAudio = false
        appState.completedStages.remove(.capture)
        appState.completedStages.remove(.separation)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Stems")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(Theme.textTertiary)
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
            }

            HStack(spacing: 10) {
                stemButton(
                    "Instrumental",
                    subtitle: "Backing track",
                    systemImage: "speaker.wave.2.fill",
                    url: appState.project.instrumentalURL,
                    color: Theme.cyan
                )
                stemButton(
                    "Vocals",
                    subtitle: "Isolated voice",
                    systemImage: "waveform",
                    url: appState.project.vocalsURL,
                    color: Theme.pink
                )
            }

            HStack(spacing: 10) {
                Button {
                    saveStepOneSnapshot()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save Step 1")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Save the captured source and isolated stems")

                Button {
                    loadStepOneSnapshot()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down.fill")
                        Text("Load")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Load a saved Step 1 package")
            }
        }
    }

    private func stemButton(_ label: String, subtitle: String, systemImage: String, url: URL, color: Color) -> some View {
        Button {
            nowPlayingURL = url
            try? appState.playbackRecorder.playFile(url)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer(minLength: 4)

                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(color)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Play \(label.lowercased())")
    }

    private func sourceIconButton(systemImage: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Header bits

    private var cardIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.coolGradient)
                .frame(width: 40, height: 40)
                .glow(color: Theme.cyan, radius: 10)
            Image(systemName: "music.note")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
    }

// MARK: - Actions

    private func startCapture() {
        NSLog("[AutoMalik] startCapture() called")
        if appState.isCapturing {
            NSLog("[AutoMalik] already capturing, ignoring click")
            return
        }

        // Don't gate on CGPreflightScreenCaptureAccess — it caches stale results
        // for ad-hoc dev builds. Attempt the capture; SystemAudioCapturer probes
        // SCShareableContent and throws .permissionDenied if access is missing.
        NSLog("[AutoMalik] starting capture task")
        Task {
            do {
                NSLog("[AutoMalik] Calling capturer.startCapture(to: \(appState.project.capturedAudioURL.path))")
                try await appState.capturer.startCapture(to: appState.project.capturedAudioURL)
                NSLog("[AutoMalik] startCapture returned successfully")
                appState.isCapturing = true
                appState.captureDuration = 0
                Task {
                    while appState.isCapturing {
                        appState.captureLevel = appState.capturer.audioLevel
                        appState.captureDuration = appState.capturer.duration
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                }
            } catch SystemAudioCapturer.CaptureError.permissionDenied {
                NSLog("[AutoMalik] CaptureError.permissionDenied")
                showPermissionAlert()
            } catch {
                NSLog("[AutoMalik] startCapture error: \(error)")
                errorMessage = error.localizedDescription
            }
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen & System Audio Permission Required"
        alert.informativeText = "AutoMalik needs Screen & System Audio Recording permission to capture music from other apps. If AutoMalik is already enabled, remove it from the list, add it again, then quit and relaunch AutoMalik."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            SystemAudioCapturer.openScreenRecordingSettings()
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
                try AudioNormalizer.normalize(
                    inputURL: result.instrumental,
                    referenceURL: appState.project.capturedAudioURL,
                    outputURL: appState.project.instrumentalURL
                )
                try fm.copyItem(at: result.vocals, to: appState.project.vocalsURL)
                try appState.project.writeStepOneManifest(sourceName: fileInfo?.name)
                appState.hasSeparatedAudio = true
                appState.markStageComplete(.separation)

                // Auto-detect key from the instrumental
                let instrumentalURL = appState.project.instrumentalURL
                let keyDetector = appState.keyDetector
                Task.detached {
                    if let detectedKey = keyDetector.detectKey(in: instrumentalURL) {
                        await MainActor.run {
                            appState.selectedKey = detectedKey
                            NSLog("[AutoMalik] Detected key: \(detectedKey.root.displayName) \(detectedKey.scale.rawValue)")
                        }
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveStepOneSnapshot() {
        guard appState.hasSeparatedAudio else { return }

        let panel = NSSavePanel()
        panel.title = "Save Step 1"
        panel.prompt = "Save"
        panel.nameFieldStringValue = "AutoMalik Step 1"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try appState.saveStepOneSnapshot(to: url, sourceName: fileInfo?.name)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadStepOneSnapshot() {
        let panel = NSOpenPanel()
        panel.title = "Load Saved Step 1"
        panel.prompt = "Load"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try appState.loadStepOneSnapshot(from: url)
            fileInfo = loadFileInfo(url: appState.project.capturedAudioURL)
            nowPlayingURL = appState.project.instrumentalURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        let t = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", m, s, t)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                self.importFile(at: url)
            }
        }
        return true
    }

    private func importFile(at url: URL) {
        do {
            let dest = appState.project.capturedAudioURL
            let fm = FileManager.default
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            // Convert non-WAV files via AVAudioFile -> AVAudioFile, or just copy WAV
            if url.pathExtension.lowercased() == "wav" {
                try fm.copyItem(at: url, to: dest)
            } else {
                try convertToWav(from: url, to: dest)
            }
            appState.hasCapturedAudio = true
            appState.markStageComplete(.capture)
            nowPlayingURL = dest
            fileInfo = loadFileInfo(url: dest)
            // Use original filename in display
            if let info = fileInfo {
                fileInfo = FileInfo(name: url.lastPathComponent, duration: info.duration, sizeBytes: info.sizeBytes)
            }
        } catch {
            errorMessage = "Could not import file: \(error.localizedDescription)"
        }
    }

    private func convertToWav(from sourceURL: URL, to destURL: URL) throws {
        // Use AVAudioFile to convert any supported format to WAV
        let inputFile = try AVAudioFile(forReading: sourceURL)
        let format = inputFile.processingFormat

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        let outputFile = try AVAudioFile(forWriting: destURL, settings: outputSettings, commonFormat: .pcmFormatFloat32, interleaved: true)

        let bufferSize: AVAudioFrameCount = 8192
        while inputFile.framePosition < inputFile.length {
            let framesRemaining = AVAudioFrameCount(inputFile.length - inputFile.framePosition)
            let framesToRead = min(bufferSize, framesRemaining)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else { break }
            try inputFile.read(into: buffer, frameCount: framesToRead)
            try outputFile.write(from: buffer)
        }
    }

    // MARK: - URL download

    private func downloadFromURL() {
        let urlString = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }

        if !appState.urlDownloader.isAvailable() {
            errorMessage = "yt-dlp not found. Install via: brew install yt-dlp"
            return
        }

        isDownloading = true
        Task {
            do {
                try await appState.urlDownloader.download(url: urlString, to: appState.project.capturedAudioURL)
                isDownloading = false
                appState.hasCapturedAudio = true
                appState.markStageComplete(.capture)
                nowPlayingURL = appState.project.capturedAudioURL
                fileInfo = loadFileInfo(url: appState.project.capturedAudioURL)
                urlInput = ""
            } catch {
                isDownloading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - File info

    private func loadFileInfo(url: URL) -> FileInfo? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int64) ?? 0

        var duration: TimeInterval = 0
        if let file = try? AVAudioFile(forReading: url) {
            duration = Double(file.length) / file.processingFormat.sampleRate
        }

        return FileInfo(name: url.lastPathComponent, duration: duration, sizeBytes: size)
    }
}
