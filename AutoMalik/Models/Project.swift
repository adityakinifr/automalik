import Foundation

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
}
