import Foundation

/// Downloads audio from a URL (YouTube, SoundCloud, etc.) using yt-dlp + ffmpeg.
@MainActor
class URLDownloader: ObservableObject {
    @Published var isDownloading = false
    @Published var statusMessage = ""

    /// Find yt-dlp on the system
    func findYtDlp() -> String? {
        let candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/Users/\(NSUserName())/.pyenv/shims/yt-dlp"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        // Fallback to PATH lookup
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["yt-dlp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return path?.isEmpty == false ? path : nil
    }

    func isAvailable() -> Bool {
        return findYtDlp() != nil
    }

    /// Download audio from a URL and save as WAV at the given destination
    func download(url: String, to destination: URL) async throws {
        guard let ytDlpPath = findYtDlp() else {
            throw DownloadError.ytDlpNotFound
        }

        isDownloading = true
        statusMessage = "Downloading..."
        defer {
            Task { @MainActor in
                self.isDownloading = false
            }
        }

        // Use a temp directory for the intermediate file
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoMalik-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let outputTemplate = tempDir.appendingPathComponent("audio.%(ext)s").path

        // Run yt-dlp to download and convert to WAV
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        process.arguments = [
            "-x",                               // extract audio
            "--audio-format", "wav",            // convert to WAV
            "--audio-quality", "0",             // best quality
            "--postprocessor-args", "-ar 44100 -ac 2",  // 44.1kHz stereo
            "-o", outputTemplate,
            "--no-playlist",
            url
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            NSLog("[URLDownloader] yt-dlp failed: \(output)")
            throw DownloadError.downloadFailed(output)
        }

        // Find the downloaded WAV file
        let downloadedFile = tempDir.appendingPathComponent("audio.wav")
        guard FileManager.default.fileExists(atPath: downloadedFile.path) else {
            throw DownloadError.outputNotFound
        }

        // Move it to the destination
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: downloadedFile, to: destination)
    }

    enum DownloadError: LocalizedError {
        case ytDlpNotFound
        case downloadFailed(String)
        case outputNotFound

        var errorDescription: String? {
            switch self {
            case .ytDlpNotFound:
                return "yt-dlp not found. Install via: brew install yt-dlp"
            case .downloadFailed(let msg):
                let snippet = msg.suffix(200)
                return "Download failed: \(snippet)"
            case .outputNotFound:
                return "Downloaded file not found."
            }
        }
    }
}
