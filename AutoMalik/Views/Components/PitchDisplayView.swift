import SwiftUI

struct PitchDisplayView: View {
    let detectedPitch: Float
    let targetPitch: Float
    let noteName: String

    var body: some View {
        VStack(spacing: 8) {
            // Note name
            Text(noteName)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            // Pitch deviation indicator
            GeometryReader { geo in
                let centerX = geo.size.width / 2
                let deviation = pitchDeviation
                let indicatorX = centerX + CGFloat(deviation) * (geo.size.width / 2)

                ZStack {
                    // Background bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)

                    // Center marker
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: 16)
                        .position(x: centerX, y: geo.size.height / 2)

                    // Pitch indicator
                    Circle()
                        .fill(deviationColor)
                        .frame(width: 12, height: 12)
                        .position(x: min(max(indicatorX, 6), geo.size.width - 6), y: geo.size.height / 2)
                }
            }
            .frame(height: 20)

            // Frequency display
            HStack {
                Text("\(Int(detectedPitch)) Hz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if targetPitch > 0 && detectedPitch > 0 {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(targetPitch)) Hz")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .frame(maxWidth: 200)
    }

    private var pitchDeviation: Float {
        guard detectedPitch > 0 && targetPitch > 0 else { return 0 }
        let cents = 1200 * log2(detectedPitch / targetPitch)
        return max(-1, min(1, cents / 50)) // 50 cents = full scale
    }

    private var deviationColor: Color {
        let absDev = abs(pitchDeviation)
        if absDev < 0.2 { return .green }
        if absDev < 0.5 { return .yellow }
        return .red
    }
}
