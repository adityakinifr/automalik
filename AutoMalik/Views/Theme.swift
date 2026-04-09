import SwiftUI

enum Theme {
    // MARK: - Colors

    static let background = Color(red: 0.04, green: 0.04, blue: 0.10)
    static let backgroundDeep = Color(red: 0.02, green: 0.02, blue: 0.06)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.18)
    static let surfaceElevated = Color(red: 0.13, green: 0.13, blue: 0.22)
    static let border = Color.white.opacity(0.08)

    // Vibrant accents
    static let purple = Color(red: 0.62, green: 0.31, blue: 0.87)   // #9D4EDD
    static let pink = Color(red: 1.0, green: 0.0, blue: 0.43)        // #FF006E
    static let cyan = Color(red: 0.0, green: 0.96, blue: 1.0)        // #00F5FF
    static let lime = Color(red: 0.20, green: 1.0, blue: 0.42)       // #33FF6B

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.35)

    // MARK: - Gradients

    static let primaryGradient = LinearGradient(
        colors: [purple, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let coolGradient = LinearGradient(
        colors: [cyan, purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmGradient = LinearGradient(
        colors: [pink, Color.orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.04, blue: 0.16),
            Color(red: 0.02, green: 0.02, blue: 0.08),
            Color(red: 0.10, green: 0.03, blue: 0.18)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Shadows / Glow

    static func glow(color: Color, radius: CGFloat = 20) -> some View {
        Circle()
            .fill(color)
            .blur(radius: radius)
            .opacity(0.5)
    }
}

// MARK: - View Modifiers

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Theme.surface)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .opacity(0.3)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

struct GlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.6), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(0.3), radius: radius * 2, x: 0, y: 0)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    func glow(color: Color, radius: CGFloat = 12) -> some View {
        modifier(GlowEffect(color: color, radius: radius))
    }
}
