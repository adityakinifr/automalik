import SwiftUI
import AVFoundation
import Combine
import Speech

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
    @Published var lyricTranscriptionLanguage: LyricsTranscriptionLanguage = .english
    @Published var isTranscribingLyrics = false
    @Published var lyricTranscriptionProgress: Double = 0
    @Published var lyricTranscriptionStatus = ""
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
    let lyricsTranscriber = LyricsTranscriber()

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

    func generateLyrics(from audioURL: URL, language: LyricsTranscriptionLanguage) async throws {
        guard !isTranscribingLyrics else { return }

        isTranscribingLyrics = true
        lyricTranscriptionProgress = 0
        lyricTranscriptionStatus = "Preparing audio"
        defer {
            isTranscribingLyrics = false
            lyricTranscriptionProgress = 0
            lyricTranscriptionStatus = ""
        }

        let lyrics = try await lyricsTranscriber.transcribe(audioURL: audioURL, language: language) { [weak self] progress, status in
            Task { @MainActor in
                self?.lyricTranscriptionProgress = progress
                self?.lyricTranscriptionStatus = status
            }
        }
        setLyrics(lyrics)
    }

    func currentLyricIndex() -> Int? {
        LyricsParser.currentIndex(in: lyricLines, at: playbackRecorder.playbackTime)
    }
}

enum LyricsTranscriptionLanguage: String, CaseIterable, Identifiable {
    case english = "en-US"
    case hindi = "hi-IN"
    case bilingual = "hi-IN+en-US"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .hindi:
            return "Hindi"
        case .bilingual:
            return "Hindi + English"
        }
    }

    var recognitionLocales: [Locale] {
        switch self {
        case .english:
            return [Locale(identifier: "en-US")]
        case .hindi:
            return [Locale(identifier: "hi-IN")]
        case .bilingual:
            return [Locale(identifier: "hi-IN"), Locale(identifier: "en-US")]
        }
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

struct RecognizedLyricToken {
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let confidence: Float
}

enum LyricsTranscriptionError: LocalizedError {
    case speechDenied
    case speechRestricted
    case recognizerUnavailable(String)
    case noSpeechFound
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .speechDenied:
            return "Speech recognition access is denied. Enable it in System Settings → Privacy & Security → Speech Recognition."
        case .speechRestricted:
            return "Speech recognition is restricted on this Mac."
        case let .recognizerUnavailable(language):
            return "Speech recognition is not available for \(language) right now."
        case .noSpeechFound:
            return "No recognizable lyrics were found. Try the isolated vocals stem or a cleaner source."
        case .emptyAudio:
            return "The selected audio file is empty."
        }
    }
}

final class LyricsTranscriber {
    private let chunkDuration: TimeInterval = 35
    private let chunkOverlap: TimeInterval = 5

    func transcribe(
        audioURL: URL,
        language: LyricsTranscriptionLanguage,
        progress: @escaping (Double, String) -> Void
    ) async throws -> String {
        let status = await requestSpeechAuthorization()
        switch status {
        case .authorized:
            break
        case .denied:
            throw LyricsTranscriptionError.speechDenied
        case .restricted:
            throw LyricsTranscriptionError.speechRestricted
        case .notDetermined:
            throw LyricsTranscriptionError.speechDenied
        @unknown default:
            throw LyricsTranscriptionError.speechRestricted
        }

        progress(0.04, "Preparing audio")
        let chunks = try splitAudio(audioURL)
        guard !chunks.isEmpty else { throw LyricsTranscriptionError.emptyAudio }

        var tokens: [RecognizedLyricToken] = []
        var availableRecognizers: [(displayName: String, recognizer: SFSpeechRecognizer)] = []
        for locale in language.recognitionLocales {
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable {
                availableRecognizers.append((locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier, recognizer))
            }
        }

        guard !availableRecognizers.isEmpty else {
            throw LyricsTranscriptionError.recognizerUnavailable(language.displayName)
        }

        let totalJobs = chunks.count * availableRecognizers.count
        var completedJobs = 0
        for recognizerInfo in availableRecognizers {
            for (index, chunk) in chunks.enumerated() {
                let status = availableRecognizers.count > 1
                    ? "Transcribing \(recognizerInfo.displayName) \(index + 1) of \(chunks.count)"
                    : "Transcribing \(index + 1) of \(chunks.count)"
                progress(Double(completedJobs) / Double(max(1, totalJobs)), status)
                do {
                    let chunkTokens = try await recognize(url: chunk.url, offset: chunk.offset, recognizer: recognizerInfo.recognizer)
                    tokens.append(contentsOf: chunkTokens)
                } catch {
                    NSLog("[AutoMalik] lyric transcription chunk failed at \(chunk.offset)s: \(error)")
                }
                completedJobs += 1
            }
        }

        let mergedTokens = mergeOverlappingTokens(tokens)
        let lrc = formatLRC(from: mergedTokens)
        guard !lrc.isEmpty else { throw LyricsTranscriptionError.noSpeechFound }
        progress(1, "Lyrics created")
        return lrc
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func recognize(url: URL, offset: TimeInterval, recognizer: SFSpeechRecognizer) async throws -> [RecognizedLyricToken] {
        try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            if #available(macOS 13.0, *) {
                request.addsPunctuation = false
            }

            var didResume = false
            var bestResult: SFSpeechRecognitionResult?

            _ = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    bestResult = result
                    if result.isFinal && !didResume {
                        didResume = true
                        continuation.resume(returning: self.tokens(from: result, offset: offset))
                    }
                }

                if error != nil, !didResume {
                    didResume = true
                    if let bestResult {
                        continuation.resume(returning: self.tokens(from: bestResult, offset: offset))
                    } else {
                        continuation.resume(returning: [])
                    }
                }
            }
        }
    }

    private func tokens(from result: SFSpeechRecognitionResult, offset: TimeInterval) -> [RecognizedLyricToken] {
        result.bestTranscription.segments.compactMap { segment in
            let text = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecognizedLyricToken(
                text: text,
                timestamp: offset + segment.timestamp,
                duration: segment.duration,
                confidence: segment.confidence
            )
        }
    }

    private func splitAudio(_ audioURL: URL) throws -> [(url: URL, offset: TimeInterval)] {
        let input = try AVAudioFile(forReading: audioURL)
        let format = input.processingFormat
        guard input.length > 0, format.sampleRate > 0 else { throw LyricsTranscriptionError.emptyAudio }

        let chunksDirectory = audioURL.deletingLastPathComponent().appendingPathComponent("lyrics_transcription_chunks", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: chunksDirectory.path) {
            try fm.removeItem(at: chunksDirectory)
        }
        try fm.createDirectory(at: chunksDirectory, withIntermediateDirectories: true)

        let framesPerChunk = AVAudioFramePosition(chunkDuration * format.sampleRate)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]

        var chunks: [(url: URL, offset: TimeInterval)] = []
        var chunkIndex = 0
        var startFrame: AVAudioFramePosition = 0
        let stepFrames = AVAudioFramePosition((chunkDuration - chunkOverlap) * format.sampleRate)

        while startFrame < input.length {
            input.framePosition = startFrame
            let chunkURL = chunksDirectory.appendingPathComponent(String(format: "lyrics_chunk_%03d.wav", chunkIndex))
            let output = try AVAudioFile(
                forWriting: chunkURL,
                settings: outputSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )

            let chunkEnd = min(startFrame + framesPerChunk, input.length)
            var framesRemaining = chunkEnd - startFrame
            while framesRemaining > 0 {
                let framesToRead = min(AVAudioFrameCount(8192), AVAudioFrameCount(framesRemaining))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else { break }
                try input.read(into: buffer, frameCount: framesToRead)
                if buffer.frameLength == 0 { break }
                normalize(buffer)
                try output.write(from: buffer)
                framesRemaining -= AVAudioFramePosition(buffer.frameLength)
            }

            chunks.append((chunkURL, Double(startFrame) / format.sampleRate))
            if chunkEnd >= input.length { break }
            startFrame += max(1, stepFrames)
            chunkIndex += 1
        }

        return chunks
    }

    private func normalize(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        guard channels > 0, frames > 0 else { return }

        var peak: Float = 0
        for channel in 0..<channels {
            let data = channelData[channel]
            for frame in 0..<frames {
                peak = max(peak, abs(data[frame]))
            }
        }

        guard peak > 0.001, peak < 0.72 else { return }
        let gain = min(6.0, 0.82 / peak)
        for channel in 0..<channels {
            let data = channelData[channel]
            for frame in 0..<frames {
                data[frame] = max(-0.98, min(0.98, data[frame] * gain))
            }
        }
    }

    private func mergeOverlappingTokens(_ tokens: [RecognizedLyricToken]) -> [RecognizedLyricToken] {
        let sortedTokens = tokens
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }

        var merged: [RecognizedLyricToken] = []
        for token in sortedTokens {
            if let lastIndex = merged.indices.last,
               abs(merged[lastIndex].timestamp - token.timestamp) < 0.55 {
                let current = merged[lastIndex]
                if tokenScore(token) > tokenScore(current) {
                    merged[lastIndex] = token
                }
            } else if !merged.contains(where: { existing in
                abs(existing.timestamp - token.timestamp) < 1.2 &&
                normalizedText(existing.text) == normalizedText(token.text)
            }) {
                merged.append(token)
            }
        }
        return merged.sorted { $0.timestamp < $1.timestamp }
    }

    private func tokenScore(_ token: RecognizedLyricToken) -> Float {
        let textBonus: Float = token.text.count > 1 ? 0.12 : 0
        let scriptBonus: Float = token.text.unicodeScalars.contains { (0x0900...0x097F).contains(Int($0.value)) } ? 0.08 : 0
        return token.confidence + textBonus + scriptBonus
    }

    private func normalizedText(_ text: String) -> String {
        text
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func formatLRC(from tokens: [RecognizedLyricToken]) -> String {
        let sortedTokens = tokens.sorted { $0.timestamp < $1.timestamp }
        var lines: [(time: TimeInterval, text: String)] = []
        var currentTokens: [RecognizedLyricToken] = []

        for token in sortedTokens {
            if let last = currentTokens.last {
                let pause = token.timestamp - (last.timestamp + last.duration)
                let currentText = currentTokens.map(\.text).joined(separator: " ")
                if pause > 0.85 || currentText.count >= 44 || token.timestamp - currentTokens[0].timestamp > 4.5 {
                    appendLine(from: currentTokens, to: &lines)
                    currentTokens = []
                }
            }
            currentTokens.append(token)
        }
        appendLine(from: currentTokens, to: &lines)

        return lines
            .filter { !$0.text.isEmpty }
            .map { "\(lrcTimestamp($0.time)) \($0.text)" }
            .joined(separator: "\n")
    }

    private func appendLine(from tokens: [RecognizedLyricToken], to lines: inout [(time: TimeInterval, text: String)]) {
        guard let first = tokens.first else { return }
        let text = tokens
            .map(\.text)
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lines.append((first.timestamp, text))
    }

    private func lrcTimestamp(_ time: TimeInterval) -> String {
        let safeTime = max(0, time)
        let minutes = Int(safeTime) / 60
        let seconds = Int(safeTime) % 60
        let centiseconds = Int((safeTime - floor(safeTime)) * 100)
        return String(format: "[%02d:%02d.%02d]", minutes, seconds, centiseconds)
    }
}
