import SwiftUI
import AVFoundation

struct WaveformView: View {
    let audioURL: URL?
    let accentColor: Color

    @State private var samples: [Float] = []

    init(audioURL: URL?, accentColor: Color = .accentColor) {
        self.audioURL = audioURL
        self.accentColor = accentColor
    }

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let midY = size.height / 2
            let stepWidth = size.width / CGFloat(samples.count)

            var path = Path()
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * stepWidth
                let amplitude = CGFloat(sample) * midY
                path.move(to: CGPoint(x: x, y: midY - amplitude))
                path.addLine(to: CGPoint(x: x, y: midY + amplitude))
            }

            context.stroke(path, with: .color(accentColor), lineWidth: 1)
        }
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: audioURL) {
            if let url = audioURL {
                samples = loadSamples(from: url, targetCount: 500)
            }
        }
    }

    private func loadSamples(from url: URL, targetCount: Int) -> [Float] {
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
    }
}
