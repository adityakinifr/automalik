import SwiftUI

struct AnimatedBackground: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.backgroundGradient
                .ignoresSafeArea()

            GeometryReader { geo in
                Canvas { context, size in
                    let spacing: CGFloat = 42
                    var grid = Path()
                    var x: CGFloat = 0
                    while x <= size.width {
                        grid.move(to: CGPoint(x: x + sin(phase) * 2, y: 0))
                        grid.addLine(to: CGPoint(x: x, y: size.height))
                        x += spacing
                    }
                    var y: CGFloat = 0
                    while y <= size.height {
                        grid.move(to: CGPoint(x: 0, y: y + cos(phase) * 2))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                        y += spacing
                    }
                    context.stroke(grid, with: .color(Color.white.opacity(0.028)), lineWidth: 1)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Theme.teal.opacity(0.10),
                    .clear,
                    Theme.coral.opacity(0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
        .allowsHitTesting(false)
    }
}
