import SwiftUI

struct GlowButton: View {
    let title: String
    let systemImage: String?
    let gradient: LinearGradient
    let isLoading: Bool
    let action: () -> Void

    @State private var isHovering = false

    init(
        _ title: String,
        systemImage: String? = nil,
        gradient: LinearGradient = Theme.primaryGradient,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.gradient = gradient
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(gradient)
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: Theme.purple.opacity(isHovering ? 0.8 : 0.5), radius: isHovering ? 24 : 16, x: 0, y: 4)
            .scaleEffect(isHovering ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3), value: isHovering)
        .disabled(isLoading)
    }
}

struct CircleGlowButton: View {
    let systemImage: String
    let gradient: LinearGradient
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false
    @State private var pulse: CGFloat = 1.0

    init(
        systemImage: String,
        gradient: LinearGradient = Theme.primaryGradient,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.gradient = gradient
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer pulse ring
                if isActive {
                    Circle()
                        .stroke(Theme.pink, lineWidth: 2)
                        .frame(width: 100, height: 100)
                        .scaleEffect(pulse)
                        .opacity(2.0 - pulse)
                }

                Circle()
                    .fill(gradient)
                    .frame(width: 88, height: 88)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: Theme.pink.opacity(0.7), radius: 30, x: 0, y: 0)

                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(isHovering ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3), value: isHovering)
        .onAppear {
            if isActive {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulse = 1.5
                }
            }
        }
        .onChange(of: isActive) { newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulse = 1.5
                }
            } else {
                pulse = 1.0
            }
        }
    }
}
