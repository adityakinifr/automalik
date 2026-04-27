import Foundation
import AVFoundation

struct Project: Identifiable {
    let id: UUID
    let createdAt: Date
    let directory: URL

    var capturedAudioURL: URL { directory.appendingPathComponent("captured.wav") }
    var instrumentalURL: URL { directory.appendingPathComponent("instrumental.wav") }
    var vocalsURL: URL { directory.appendingPathComponent("vocals.wav") }
    var rawRecordingURL: URL { directory.appendingPathComponent("recording.wav") }
    var tunedRecordingURL: URL { directory.appendingPathComponent("tuned_recording.wav") }
    var finalMixURL: URL { directory.appendingPathComponent("final_mix.wav") }
    var lyricsURL: URL { directory.appendingPathComponent("lyrics.txt") }
    var stepOneManifestURL: URL { directory.appendingPathComponent(StepOneSnapshot.manifestFileName) }

    init() {
        self.id = UUID()
        self.createdAt = Date()
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directory = appSupport
            .appendingPathComponent("AutoMalik", isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func hasStepOneFiles() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: capturedAudioURL.path)
            && fm.fileExists(atPath: instrumentalURL.path)
            && fm.fileExists(atPath: vocalsURL.path)
    }

    func writeStepOneManifest(sourceName: String? = nil) throws {
        let manifest = StepOneSnapshot.Manifest(
            version: StepOneSnapshot.currentVersion,
            projectID: id,
            savedAt: Date(),
            sourceName: sourceName,
            capturedFileName: StepOneSnapshot.capturedFileName,
            instrumentalFileName: StepOneSnapshot.instrumentalFileName,
            vocalsFileName: StepOneSnapshot.vocalsFileName,
            capturedDuration: Self.audioDuration(at: capturedAudioURL),
            instrumentalDuration: Self.audioDuration(at: instrumentalURL),
            vocalsDuration: Self.audioDuration(at: vocalsURL)
        )
        let data = try JSONEncoder.stepOne.encode(manifest)
        try data.write(to: stepOneManifestURL, options: .atomic)
    }

    func saveStepOneSnapshot(to folderURL: URL, sourceName: String? = nil) throws {
        guard hasStepOneFiles() else {
            throw StepOneSnapshot.Error.missingRequiredFiles
        }

        let fm = FileManager.default
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        try Self.replaceItem(at: folderURL.appendingPathComponent(StepOneSnapshot.capturedFileName), with: capturedAudioURL)
        try Self.replaceItem(at: folderURL.appendingPathComponent(StepOneSnapshot.instrumentalFileName), with: instrumentalURL)
        try Self.replaceItem(at: folderURL.appendingPathComponent(StepOneSnapshot.vocalsFileName), with: vocalsURL)

        let manifest = StepOneSnapshot.Manifest(
            version: StepOneSnapshot.currentVersion,
            projectID: id,
            savedAt: Date(),
            sourceName: sourceName,
            capturedFileName: StepOneSnapshot.capturedFileName,
            instrumentalFileName: StepOneSnapshot.instrumentalFileName,
            vocalsFileName: StepOneSnapshot.vocalsFileName,
            capturedDuration: Self.audioDuration(at: capturedAudioURL),
            instrumentalDuration: Self.audioDuration(at: instrumentalURL),
            vocalsDuration: Self.audioDuration(at: vocalsURL)
        )
        let data = try JSONEncoder.stepOne.encode(manifest)
        try data.write(to: folderURL.appendingPathComponent(StepOneSnapshot.manifestFileName), options: .atomic)
    }

    func loadStepOneSnapshot(from folderURL: URL) throws {
        let manifestURL = folderURL.appendingPathComponent(StepOneSnapshot.manifestFileName)
        let manifest: StepOneSnapshot.Manifest
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder.stepOne.decode(StepOneSnapshot.Manifest.self, from: data)
        } else {
            manifest = StepOneSnapshot.Manifest.defaultManifest
        }

        let capturedSource = folderURL.appendingPathComponent(manifest.capturedFileName)
        let instrumentalSource = folderURL.appendingPathComponent(manifest.instrumentalFileName)
        let vocalsSource = folderURL.appendingPathComponent(manifest.vocalsFileName)

        guard FileManager.default.fileExists(atPath: capturedSource.path),
              FileManager.default.fileExists(atPath: instrumentalSource.path),
              FileManager.default.fileExists(atPath: vocalsSource.path) else {
            throw StepOneSnapshot.Error.missingRequiredFiles
        }

        try Self.replaceItem(at: capturedAudioURL, with: capturedSource)
        try Self.replaceItem(at: instrumentalURL, with: instrumentalSource)
        try Self.replaceItem(at: vocalsURL, with: vocalsSource)
        try writeStepOneManifest(sourceName: manifest.sourceName)
    }

    private static func replaceItem(at destination: URL, with source: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    private static func audioDuration(at url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}

enum StepOneSnapshot {
    static let currentVersion = 1
    static let manifestFileName = "automalik-step1.json"
    static let capturedFileName = "captured.wav"
    static let instrumentalFileName = "instrumental.wav"
    static let vocalsFileName = "vocals.wav"

    struct Manifest: Codable {
        let version: Int
        let projectID: UUID
        let savedAt: Date
        let sourceName: String?
        let capturedFileName: String
        let instrumentalFileName: String
        let vocalsFileName: String
        let capturedDuration: TimeInterval?
        let instrumentalDuration: TimeInterval?
        let vocalsDuration: TimeInterval?

        static var defaultManifest: Manifest {
            Manifest(
                version: currentVersion,
                projectID: UUID(),
                savedAt: Date(),
                sourceName: nil,
                capturedFileName: StepOneSnapshot.capturedFileName,
                instrumentalFileName: StepOneSnapshot.instrumentalFileName,
                vocalsFileName: StepOneSnapshot.vocalsFileName,
                capturedDuration: nil,
                instrumentalDuration: nil,
                vocalsDuration: nil
            )
        }
    }

    enum Error: LocalizedError {
        case missingRequiredFiles

        var errorDescription: String? {
            switch self {
            case .missingRequiredFiles:
                return "The selected folder must contain captured.wav, instrumental.wav, and vocals.wav."
            }
        }
    }
}

private extension JSONEncoder {
    static var stepOne: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var stepOne: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
