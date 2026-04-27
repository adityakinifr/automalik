import SwiftUI
import AVFoundation
import Combine

@MainActor
class AppState: ObservableObject {
    // Navigation
    @Published var currentStage: PipelineStage = .capture
    @Published var completedStages: Set<PipelineStage> = []

    // Project
    @Published var project: Project = Project()

    // Capture
    @Published var isCapturing = false
    @Published var captureLevel: Float = 0
    @Published var captureDuration: TimeInterval = 0
    @Published var hasCapturedAudio = false

    // Separation
    @Published var isSeparating = false
    @Published var separationProgress: Double = 0
    @Published var hasSeparatedAudio = false

    // Recording
    @Published var isRecording = false
    @Published var isPlayingInstrumental = false
    @Published var lyricsText = ""
    @Published var lyricLines: [LyricLine] = []
    @Published var instrumentalPlaybackVolume: Float = 1.0
    @Published var guideVocalVolume: Float = 0.35
    @Published var micMonitorVolume: Float = 0.5
    @Published var micLevel: Float = 0
    @Published var hasRecording = false

    // Auto-tune
    @Published var selectedKey = MusicalKey(root: .C, scale: .major)
    @Published var autoTuneStrength: Float = 0.45
    @Published var autoTuneEnabled = true
    @Published var isProcessingAutoTune = false
    @Published var hasAutoTunedRecording = false

    // Mix
    @Published var instrumentalMixVolume: Float = 1.0
    @Published var vocalMixVolume: Float = 1.0
    @Published var hasFinalMix = false

    // Audio components
    let capturer = SystemAudioCapturer()
    let demucsRunner = DemucsRunner()
    let playbackRecorder = PlaybackRecorder()
    let pitchDetector = PitchDetector()
    let offlinePitchTuner = OfflinePitchTuner()
    let audioMixer = AudioMixer()
    let keyDetector = KeyDetector()
    let urlDownloader = URLDownloader()
    let liveAutoTuner = LiveAutoTuner()

    // Live mode
    @Published var isLiveMode = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        playbackRecorder.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func markStageComplete(_ stage: PipelineStage) {
        completedStages.insert(stage)
    }

    func isStageAccessible(_ stage: PipelineStage) -> Bool {
        if stage == .capture { return true }
        guard let previous = PipelineStage(rawValue: stage.rawValue - 1) else { return false }
        return completedStages.contains(previous)
    }

    func newProject() {
        playbackRecorder.stop()
        project = Project()
        completedStages.removeAll()
        currentStage = .capture
        hasCapturedAudio = false
        hasSeparatedAudio = false
        hasRecording = false
        hasAutoTunedRecording = false
        hasFinalMix = false
        setLyrics("")
    }

    func saveStepOneSnapshot(to folderURL: URL, sourceName: String? = nil) throws {
        try project.saveStepOneSnapshot(to: folderURL, sourceName: sourceName)
    }

    func loadStepOneSnapshot(from folderURL: URL) throws {
        playbackRecorder.stop()

        let loadedProject = Project()
        try loadedProject.loadStepOneSnapshot(from: folderURL)

        project = loadedProject
        hasCapturedAudio = true
        hasSeparatedAudio = true
        hasRecording = false
        hasAutoTunedRecording = false
        hasFinalMix = false
        setLyrics("")

        completedStages = [.capture, .separation]
        currentStage = .recording
    }

    var hasLyrics: Bool {
        !lyricLines.isEmpty
    }

    var lyricsAreTimed: Bool {
        LyricsParser.isTimed(lyricLines)
    }

    func setLyrics(_ text: String) {
        lyricsText = text
        lyricLines = LyricsParser.parse(text)

        do {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if FileManager.default.fileExists(atPath: project.lyricsURL.path) {
                    try FileManager.default.removeItem(at: project.lyricsURL)
                }
            } else {
                try text.write(to: project.lyricsURL, atomically: true, encoding: .utf8)
            }
        } catch {
            NSLog("[AutoMalik] failed to save lyrics: \(error)")
        }
    }

    func importLyrics(from url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        setLyrics(text)
    }

    func currentLyricIndex() -> Int? {
        LyricsParser.currentIndex(in: lyricLines, at: playbackRecorder.playbackTime)
    }
}

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval?
    let text: String
}

enum LyricsParser {
    static func parse(_ rawText: String) -> [LyricLine] {
        rawText
            .components(separatedBy: .newlines)
            .flatMap(parseLine)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                switch (lhs.time, rhs.time) {
                case let (l?, r?):
                    return l < r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return false
                }
            }
    }

    static func isTimed(_ lines: [LyricLine]) -> Bool {
        lines.contains { $0.time != nil }
    }

    static func currentIndex(in lines: [LyricLine], at time: TimeInterval) -> Int? {
        let timedLines = lines.enumerated().filter { $0.element.time != nil }
        guard !timedLines.isEmpty else { return nil }

        var current = timedLines[0].offset
        for (index, line) in timedLines {
            guard let lineTime = line.time else { continue }
            if lineTime <= time {
                current = index
            } else {
                break
            }
        }
        return current
    }

    private static func parseLine(_ rawLine: String) -> [LyricLine] {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return [] }

        let matches = timestampMatches(in: line)
        guard !matches.isEmpty else {
            return [LyricLine(time: nil, text: line)]
        }

        var lyricText = line
        for match in matches.reversed() {
            if let range = Range(match.range, in: line) {
                lyricText.removeSubrange(range)
            }
        }
        lyricText = lyricText.trimmingCharacters(in: .whitespacesAndNewlines)

        return matches.compactMap { match in
            guard let time = timestamp(from: match, in: line) else { return nil }
            return LyricLine(time: time, text: lyricText)
        }
    }

    private static func timestampMatches(in line: String) -> [NSTextCheckingResult] {
        let pattern = #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
    }

    private static func timestamp(from match: NSTextCheckingResult, in line: String) -> TimeInterval? {
        guard match.numberOfRanges >= 3,
              let minuteRange = Range(match.range(at: 1), in: line),
              let secondRange = Range(match.range(at: 2), in: line),
              let minutes = Double(line[minuteRange]),
              let seconds = Double(line[secondRange]) else { return nil }

        var fraction = 0.0
        if match.numberOfRanges >= 4,
           match.range(at: 3).location != NSNotFound,
           let fractionRange = Range(match.range(at: 3), in: line),
           let fractionValue = Double(line[fractionRange]) {
            let divisor = pow(10.0, Double(line[fractionRange].count))
            fraction = fractionValue / divisor
        }

        return minutes * 60 + seconds + fraction
    }
}
