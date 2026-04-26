import SwiftUI

enum CardStepState {
    case pending, active, complete
}

struct StepBadge: View {
    let number: Int
    let state: CardStepState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(fillColor)
                .frame(width: 28, height: 22)
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(strokeColor, lineWidth: 1)
                .frame(width: 28, height: 22)
            if state == .complete {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
            } else {
                Text("\(number)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(textColor)
            }
        }
    }

    private var fillColor: Color {
        switch state {
        case .pending:  return Color.white.opacity(0.05)
        case .active:   return Theme.purple.opacity(0.25)
        case .complete: return Theme.lime.opacity(0.20)
        }
    }

    private var strokeColor: Color {
        switch state {
        case .pending:  return Color.white.opacity(0.10)
        case .active:   return Theme.purple
        case .complete: return Theme.lime
        }
    }

    private var textColor: Color {
        switch state {
        case .pending:  return Theme.textTertiary
        case .active:   return .white
        case .complete: return .white
        }
    }
}

extension AppState {
    var sourceCardState: CardStepState {
        hasSeparatedAudio ? .complete : .active
    }

    var vocalsCardState: CardStepState {
        if hasRecording || hasAutoTunedRecording { return .complete }
        return hasSeparatedAudio ? .active : .pending
    }

    var autoTuneCardState: CardStepState {
        if hasAutoTunedRecording { return .complete }
        if hasRecording { return .active }
        return .pending
    }
}

extension View {
    func cardDimmed(_ dimmed: Bool) -> some View {
        self
            .opacity(dimmed ? 0.55 : 1.0)
            .saturation(dimmed ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: dimmed)
    }
}
