import Foundation

enum PipelineStage: Int, CaseIterable, Identifiable {
    case capture = 0
    case separation
    case recording
    case autoTune
    case mixExport

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .capture: return "Capture"
        case .separation: return "Separate"
        case .recording: return "Record"
        case .autoTune: return "Auto-Tune"
        case .mixExport: return "Mix & Export"
        }
    }

    var systemImage: String {
        switch self {
        case .capture: return "waveform.badge.mic"
        case .separation: return "music.note.list"
        case .recording: return "mic.fill"
        case .autoTune: return "tuningfork"
        case .mixExport: return "square.and.arrow.down"
        }
    }

    var stepNumber: Int { rawValue + 1 }
}
