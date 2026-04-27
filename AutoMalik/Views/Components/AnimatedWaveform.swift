import SwiftUI
import AVFoundation
import AppKit

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
    @State private var isHovering = false

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
        let waveformHeight = max(24, size.height - 20)
        let clampedProgress = max(0, min(1, progress.isFinite ? progress : 0))
        let progressX = size.width * CGFloat(clampedProgress)
        let hoverX = size.width * CGFloat(hoverProgress ?? clampedProgress)

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Theme.controlFill.opacity(0.95) : Theme.surface.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isHovering ? Theme.cyan.opacity(0.7) : Theme.border, lineWidth: isHovering ? 1.5 : 1)
                )

            waveformCanvas(in: CGSize(width: size.width, height: waveformHeight), fill: .color(Theme.textTertiary.opacity(0.55)))
                .frame(height: waveformHeight)
                .padding(.top, 2)

            waveformCanvas(
                in: CGSize(width: size.width, height: waveformHeight),
                fill: .linearGradient(
                    Gradient(colors: [Theme.cyan, Theme.purple, Theme.pink]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                )
            )
            .frame(height: waveformHeight)
            .padding(.top, 2)
            .mask(alignment: .leading) {
                Rectangle()
                    .frame(width: max(0, progressX))
            }

            // Hover preview line
            if let hover = hoverProgress, onSeek != nil {
                Rectangle()
                    .fill(Theme.mint.opacity(0.55))
                    .frame(width: 1.5, height: size.height - 12)
                    .offset(x: hover * size.width)
                    .padding(.vertical, 6)
            }

            // Playhead
            if isPlaying || clampedProgress > 0 {
                ZStack {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: size.height - 12)
                        .glow(color: Theme.cyan, radius: 5)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Theme.cyan, lineWidth: 2))
                        .shadow(color: Theme.cyan.opacity(0.35), radius: 8, y: 2)
                        .offset(y: -(size.height / 2) + 11)
                }
                .offset(x: progressX)
            }

            VStack {
                Spacer()
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.textTertiary.opacity(0.28))
                        .frame(height: 5)
                    Capsule()
                        .fill(Theme.accentGradient)
                        .frame(width: max(0, progressX), height: 5)
                    if isHovering, onSeek != nil {
                        Circle()
                            .fill(Theme.mint)
                            .frame(width: 9, height: 9)
                            .offset(x: hoverX - 4.5)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.linear(duration: isPlaying ? 0.05 : 0.12), value: clampedProgress)
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
        .onHover { hovering in
            isHovering = hovering
            if hovering, onSeek != nil {
                NSCursor.pointingHand.push()
            } else if onSeek != nil {
                NSCursor.pop()
            }
        }
    }

    private func waveformCanvas(in size: CGSize, fill: GraphicsContext.Shading) -> some View {
        let midY = size.height / 2
        let stepWidth = size.width / CGFloat(samples.count)

        return Canvas { context, _ in
            var path = Path()
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * stepWidth
                let amp = max(3, CGFloat(sample) * midY * 1.85)
                path.addRoundedRect(
                    in: CGRect(
                        x: x,
                        y: midY - amp / 2,
                        width: max(1.5, stepWidth - 1),
                        height: amp
                    ),
                    cornerSize: CGSize(width: 1.5, height: 1.5)
                )
            }
            context.fill(path, with: fill)
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
