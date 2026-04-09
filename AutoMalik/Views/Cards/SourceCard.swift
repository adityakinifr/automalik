import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

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
                statusDot
            }

            Divider().background(Theme.border)

            // Body content
            VStack(spacing: 12) {
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

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
        .glassCard()
        .overlay(
            // Drop target highlight
            RoundedRectangle(cornerRadius: 20)
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
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.coolGradient.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cyan.opacity(0.5), lineWidth: 1))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
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
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.primaryGradient.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.purple.opacity(0.5), lineWidth: 1))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
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
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.lime)
                Text("Source loaded")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            if let info = fileInfo {
                VStack(spacing: 2) {
                    Text(info.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(formatDuration(info.duration))
                        Text("•")
                        Text(formatSize(info.sizeBytes))
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 8)
            }
            HStack(spacing: 14) {
                Button {
                    nowPlayingURL = appState.project.capturedAudioURL
                    try? appState.playbackRecorder.playFile(appState.project.capturedAudioURL)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                        Text("Play")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
                }
                .buttonStyle(.plain)

                Button {
                    resetSource()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                        Text("Reset")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.pink)
                }
                .buttonStyle(.plain)
            }
        }
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
            appState.project.vocalsURL
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
        NSLog("[AutoMalik] startCapture() called")
        if appState.isCapturing {
            NSLog("[AutoMalik] already capturing, ignoring click")
            return
        }

        let hasPerm = SystemAudioCapturer.hasScreenRecordingPermission()
        NSLog("[AutoMalik] CGPreflightScreenCaptureAccess() = \(hasPerm)")

        if !hasPerm {
            NSLog("[AutoMalik] No permission - calling CGRequestScreenCaptureAccess()")
            let granted = SystemAudioCapturer.requestScreenRecordingPermission()
            NSLog("[AutoMalik] CGRequestScreenCaptureAccess() = \(granted)")
            if !granted {
                NSLog("[AutoMalik] Showing permission alert")
                showPermissionAlert()
                return
            }
        }

        NSLog("[AutoMalik] Permission OK, starting capture task")
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
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "AutoMalik needs Screen Recording permission to capture system audio. Click 'Open Settings' to grant it, then quit and relaunch AutoMalik."
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
                try fm.copyItem(at: result.instrumental, to: appState.project.instrumentalURL)
                try fm.copyItem(at: result.vocals, to: appState.project.vocalsURL)
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
