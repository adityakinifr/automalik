import SwiftUI

struct AnimatedBackground: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.backgroundGradient
                .ignoresSafeArea()

            // Floating glow orbs
            GeometryReader { geo in
                ZStack {
                    orb(color: Theme.purple, size: 400)
                        .offset(
                            x: sin(phase) * 100 - 50,
                            y: cos(phase * 0.7) * 80 - 100
                        )

                    orb(color: Theme.pink, size: 300)
                        .offset(
                            x: geo.size.width - 200 + cos(phase * 0.9) * 80,
                            y: geo.size.height * 0.6 + sin(phase * 1.1) * 60
                        )

                    orb(color: Theme.cyan, size: 350)
                        .offset(
                            x: geo.size.width * 0.4 + sin(phase * 1.3) * 100,
                            y: geo.size.height - 150 + cos(phase) * 70
                        )
                }
            }
            .blur(radius: 80)
            .opacity(0.4)
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
        .allowsHitTesting(false)
    }

    private func orb(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}
