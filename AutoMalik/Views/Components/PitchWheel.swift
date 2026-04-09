import SwiftUI

struct PitchWheel: View {
    let key: MusicalKey
    var detectedFreq: Float = 0

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2 - 20

            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(Theme.border, lineWidth: 1)
                    .frame(width: size, height: size)

                // Inner ring
                Circle()
                    .strokeBorder(Theme.border, lineWidth: 1)
                    .frame(width: radius * 1.4, height: radius * 1.4)

                // Note labels positioned in circle
                ForEach(0..<12, id: \.self) { i in
                    let angle = Double(i) * (2 * .pi / 12) - .pi / 2
                    let isInKey = key.validSemitones.contains(i)
                    let isRoot = i == key.root.rawValue

                    Text(noteNames[i])
                        .font(.system(size: 16, weight: isRoot ? .black : (isInKey ? .bold : .regular), design: .rounded))
                        .foregroundStyle(noteColor(isInKey: isInKey, isRoot: isRoot))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(noteBackground(isInKey: isInKey, isRoot: isRoot))
                                .frame(width: 36, height: 36)
                        )
                        .offset(
                            x: cos(angle) * radius,
                            y: sin(angle) * radius
                        )
                }

                // Detected note indicator (arrow from center)
                if detectedFreq > 0 {
                    let semitone = detectedSemitone
                    let angle = Double(semitone) * (2 * .pi / 12) - .pi / 2

                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: cos(angle) * (radius - 25), y: sin(angle) * (radius - 25)))
                    }
                    .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .glow(color: Theme.cyan, radius: 6)
                    .frame(width: size, height: size)
                }

                // Center label
                VStack(spacing: 2) {
                    Text(key.root.displayName)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(key.scale.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var detectedSemitone: Int {
        guard detectedFreq > 0 else { return 0 }
        let midi = 69.0 + 12.0 * log2(Double(detectedFreq) / 440.0)
        let s = Int(round(midi)) % 12
        return s < 0 ? s + 12 : s
    }

    private func noteColor(isInKey: Bool, isRoot: Bool) -> Color {
        if isRoot { return .white }
        if isInKey { return Theme.purple }
        return Theme.textTertiary
    }

    private func noteBackground(isInKey: Bool, isRoot: Bool) -> Color {
        if isRoot { return Theme.pink }
        if isInKey { return Theme.purple.opacity(0.2) }
        return .clear
    }
}
