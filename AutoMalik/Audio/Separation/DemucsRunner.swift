import Foundation

@MainActor
class DemucsRunner: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var isSetUp = false

    private let appSupportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AutoMalik", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var venvPath: URL { appSupportDir.appendingPathComponent("demucs_env") }
    private var pythonPath: URL { venvPath.appendingPathComponent("bin/python3") }

    // MARK: - Setup

    func checkSetup() async -> Bool {
        let pythonExists = FileManager.default.fileExists(atPath: pythonPath.path)
        if pythonExists {
            // Verify demucs is installed
            let result = await runCommand(pythonPath.path, arguments: ["-m", "demucs", "--help"])
            isSetUp = result
            return result
        }
        isSetUp = false
        return false
    }

    func setup() async throws {
        statusMessage = "Finding Python..."
        progress = 0.1

        // Find system Python
        let pythonCmd = await findPython()
        guard let pythonCmd else {
            throw DemucsError.pythonNotFound
        }

        // Create virtual environment
        statusMessage = "Creating Python environment..."
        progress = 0.2

        let venvProcess = Process()
        venvProcess.executableURL = URL(fileURLWithPath: pythonCmd)
        venvProcess.arguments = ["-m", "venv", venvPath.path]
        try venvProcess.run()
        venvProcess.waitUntilExit()

        guard venvProcess.terminationStatus == 0 else {
            throw DemucsError.venvCreationFailed
        }

        // Install demucs
        statusMessage = "Installing Demucs (this may take a few minutes)..."
        progress = 0.3

        let pipPath = venvPath.appendingPathComponent("bin/pip3").path
        let pipProcess = Process()
        pipProcess.executableURL = URL(fileURLWithPath: pipPath)
        pipProcess.arguments = ["install", "demucs"]
        try pipProcess.run()
        pipProcess.waitUntilExit()

        guard pipProcess.terminationStatus == 0 else {
            throw DemucsError.installFailed
        }

        progress = 1.0
        statusMessage = "Setup complete!"
        isSetUp = true
    }

    // MARK: - Separation

    func separate(inputFile: URL, outputDir: URL) async throws -> (instrumental: URL, vocals: URL) {
        isProcessing = true
        progress = 0
        statusMessage = "Starting vocal separation..."

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        // Run demucs
        let process = Process()
        process.executableURL = pythonPath
        process.arguments = [
            "-m", "demucs",
            "--two-stems", "vocals",
            "-n", "htdemucs",
            "--out", outputDir.path,
            inputFile.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        // Read output for progress
        let handle = pipe.fileHandleForReading
        Task.detached { [weak self] in
            while let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
                await self?.parseProgress(line)
            }
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DemucsError.separationFailed
        }

        // Find output files - demucs outputs to outputDir/htdemucs/<filename>/
        let inputName = inputFile.deletingPathExtension().lastPathComponent
        let demucsOutputDir = outputDir
            .appendingPathComponent("htdemucs")
            .appendingPathComponent(inputName)

        let instrumentalFile = demucsOutputDir.appendingPathComponent("no_vocals.wav")
        let vocalsFile = demucsOutputDir.appendingPathComponent("vocals.wav")

        guard FileManager.default.fileExists(atPath: instrumentalFile.path),
              FileManager.default.fileExists(atPath: vocalsFile.path) else {
            throw DemucsError.outputNotFound
        }

        progress = 1.0
        statusMessage = "Separation complete!"

        return (instrumental: instrumentalFile, vocals: vocalsFile)
    }

    // MARK: - Helpers

    private func parseProgress(_ output: String) {
        // Demucs outputs progress like "  3%|..."
        let lines = output.components(separatedBy: "\r")
        for line in lines {
            if let match = line.range(of: #"(\d+)%"#, options: .regularExpression) {
                let percentStr = line[match].dropLast()
                if let percent = Double(percentStr) {
                    Task { @MainActor in
                        self.progress = percent / 100.0
                        self.statusMessage = "Separating vocals... \(Int(percent))%"
                    }
                }
            }
        }
    }

    private func findPython() async -> String? {
        let candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        // Try which
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return path?.isEmpty == false ? path : nil
    }

    private func runCommand(_ command: String, arguments: [String]) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    enum DemucsError: LocalizedError {
        case pythonNotFound
        case venvCreationFailed
        case installFailed
        case separationFailed
        case outputNotFound

        var errorDescription: String? {
            switch self {
            case .pythonNotFound: return "Python 3 not found. Please install Python 3 (e.g., via Homebrew: brew install python3)."
            case .venvCreationFailed: return "Failed to create Python virtual environment."
            case .installFailed: return "Failed to install Demucs. Check your internet connection."
            case .separationFailed: return "Vocal separation failed. The audio file may be corrupted."
            case .outputNotFound: return "Separation output files not found."
            }
        }
    }
}
