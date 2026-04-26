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
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Theme.teal.opacity(isHovering ? 0.26 : 0.16), radius: isHovering ? 18 : 12, x: 0, y: 6)
            .scaleEffect(isHovering ? 1.015 : 1.0)
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
                        Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 2)
                    )
                    .shadow(color: Theme.coral.opacity(0.30), radius: 24, x: 0, y: 8)

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
