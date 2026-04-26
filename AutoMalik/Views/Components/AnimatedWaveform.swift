import SwiftUI
import AVFoundation

struct AnimatedWaveform: View {
    let audioURL: URL?
    var liveLevel: Float = 0
    var isPlaying: Bool = false
    var progress: Double = 0
    var color: Color = Theme.cyan
    var onSeek: ((Double) -> Void)? = nil

    @State private var samples: [Float] = []
    @State private var animationPhase: CGFloat = 0
    @State private var hoverProgress: Double? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if samples.isEmpty {
                    // Live mode - animated bars
                    liveBarView(in: geo.size)
                } else {
                    // File mode - waveform with progress
                    waveformView(in: geo.size)
                }
            }
        }
        .task(id: audioURL) {
            if let url = audioURL {
                samples = await loadSamples(from: url, targetCount: 200)
            } else {
                samples = []
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                animationPhase = .pi * 2
            }
        }
    }

    // MARK: - Live bars

    private func liveBarView(in size: CGSize) -> some View {
        let barCount = 60
        let spacing: CGFloat = 4
        let barWidth = (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
        let midY = size.height / 2

        return HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { i in
                let phaseOffset = CGFloat(i) * 0.2
                let baseHeight = sin(animationPhase + phaseOffset) * 0.3 + 0.5
                let liveBoost = CGFloat(liveLevel) * 1.5
                let height = max(4, midY * (baseHeight + liveBoost))

                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(
                        LinearGradient(
                            colors: [Theme.cyan, Theme.purple, Theme.pink],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth, height: min(height, size.height - 4))
                    .glow(color: Theme.purple.opacity(CGFloat(liveLevel)), radius: 8)
            }
        }
    }

    // MARK: - Waveform with progress

    private func waveformView(in size: CGSize) -> some View {
        let midY = size.height / 2
        let stepWidth = size.width / CGFloat(samples.count)
        let progressX = size.width * CGFloat(progress)

        return ZStack(alignment: .leading) {
            // Background waveform (unplayed)
            Canvas { context, _ in
                var path = Path()
                for (index, sample) in samples.enumerated() {
                    let x = CGFloat(index) * stepWidth
                    let amp = max(2, CGFloat(sample) * midY * 1.8)
                    path.addRoundedRect(
                        in: CGRect(x: x, y: midY - amp/2, width: max(1, stepWidth - 1), height: amp),
                        cornerSize: CGSize(width: 1, height: 1)
                    )
                }
                context.fill(path, with: .color(Theme.textTertiary))
            }

            // Played portion (gradient)
            Canvas { context, _ in
                var path = Path()
                for (index, sample) in samples.enumerated() {
                    let x = CGFloat(index) * stepWidth
                    if x > progressX { break }
                    let amp = max(2, CGFloat(sample) * midY * 1.8)
                    path.addRoundedRect(
                        in: CGRect(x: x, y: midY - amp/2, width: max(1, stepWidth - 1), height: amp),
                        cornerSize: CGSize(width: 1, height: 1)
                    )
                }
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [Theme.cyan, Theme.purple, Theme.pink]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ))
            }

            // Hover preview line
            if let hover = hoverProgress, onSeek != nil {
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 1, height: size.height)
                    .offset(x: hover * size.width)
            }

            // Playhead
            if isPlaying || progress > 0 {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: size.height)
                    .glow(color: Theme.cyan, radius: 4)
                    .offset(x: progressX)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let p = max(0, min(1, value.location.x / size.width))
                    hoverProgress = p
                    onSeek?(p)
                }
                .onEnded { _ in
                    hoverProgress = nil
                }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let pt):
                hoverProgress = max(0, min(1, pt.x / size.width))
            case .ended:
                hoverProgress = nil
            }
        }
    }

    // MARK: - Sample loading

    private func loadSamples(from url: URL, targetCount: Int) async -> [Float] {
        await Task.detached(priority: .userInitiated) {
            guard let file = try? AVAudioFile(forReading: url) else { return [] }
            let totalFrames = Int(file.length)
            guard totalFrames > 0 else { return [] }

            let format = file.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else { return [] }
            try? file.read(into: buffer)

            guard let channelData = buffer.floatChannelData else { return [] }
            let data = channelData[0]
            let framesPerSample = max(1, totalFrames / targetCount)

            var result: [Float] = []
            for i in stride(from: 0, to: totalFrames, by: framesPerSample) {
                var maxVal: Float = 0
                let end = min(i + framesPerSample, totalFrames)
                for j in i..<end {
                    maxVal = max(maxVal, abs(data[j]))
                }
                result.append(maxVal)
            }
            return result
        }.value
    }
}
