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
    @Published var instrumentalPlaybackVolume: Float = 0.7
    @Published var guideVocalVolume: Float = 0.35
    @Published var micMonitorVolume: Float = 0.5
    @Published var micLevel: Float = 0
    @Published var hasRecording = false

    // Auto-tune
    @Published var selectedKey = MusicalKey(root: .C, scale: .major)
    @Published var autoTuneStrength: Float = 0.8
    @Published var autoTuneEnabled = true
    @Published var isProcessingAutoTune = false
    @Published var hasAutoTunedRecording = false

    // Mix
    @Published var instrumentalMixVolume: Float = 0.7
    @Published var vocalMixVolume: Float = 1.0
    @Published var hasFinalMix = false

    // Audio components
    let capturer = SystemAudioCapturer()
    let demucsRunner = DemucsRunner()
    let playbackRecorder = PlaybackRecorder()
    let pitchDetector = PitchDetector()
    let pitchCorrector = PitchCorrector()
    let phaseVocoder = PhaseVocoder()
    let audioMixer = AudioMixer()
    let keyDetector = KeyDetector()
    let urlDownloader = URLDownloader()

    func markStageComplete(_ stage: PipelineStage) {
        completedStages.insert(stage)
    }

    func isStageAccessible(_ stage: PipelineStage) -> Bool {
        if stage == .capture { return true }
        guard let previous = PipelineStage(rawValue: stage.rawValue - 1) else { return false }
        return completedStages.contains(previous)
    }

    func newProject() {
        project = Project()
        completedStages.removeAll()
        currentStage = .capture
        hasCapturedAudio = false
        hasSeparatedAudio = false
        hasRecording = false
        hasAutoTunedRecording = false
        hasFinalMix = false
    }
}
