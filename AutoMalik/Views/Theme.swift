import SwiftUI

enum Theme {
    // MARK: - Colors

    static let background = Color(red: 0.055, green: 0.058, blue: 0.062)
    static let backgroundDeep = Color(red: 0.028, green: 0.030, blue: 0.033)
    static let panel = Color(red: 0.075, green: 0.080, blue: 0.087)
    static let surface = Color(red: 0.105, green: 0.112, blue: 0.122)
    static let surfaceElevated = Color(red: 0.145, green: 0.153, blue: 0.166)
    static let controlFill = Color.white.opacity(0.055)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.16)

    // Accents
    static let teal = Color(red: 0.10, green: 0.73, blue: 0.70)
    static let coral = Color(red: 0.96, green: 0.38, blue: 0.32)
    static let amber = Color(red: 0.95, green: 0.69, blue: 0.25)
    static let mint = Color(red: 0.35, green: 0.84, blue: 0.54)
    static let purple = Color(red: 0.58, green: 0.43, blue: 0.94)
    static let cyan = teal
    static let pink = coral
    static let lime = mint

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.66)
    static let textTertiary = Color.white.opacity(0.42)

    // MARK: - Gradients

    static let primaryGradient = LinearGradient(
        colors: [coral, amber],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [teal, mint],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let coolGradient = LinearGradient(
        colors: [teal, purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmGradient = LinearGradient(
        colors: [coral, amber],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.035, green: 0.037, blue: 0.041),
            Color(red: 0.062, green: 0.067, blue: 0.071),
            Color(red: 0.044, green: 0.047, blue: 0.052)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Shadows / Glow

    static func glow(color: Color, radius: CGFloat = 16) -> some View {
        Circle()
            .fill(color)
            .blur(radius: radius)
            .opacity(0.3)
    }
}

// MARK: - View Modifiers

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Theme.surface)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .opacity(0.18)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.045), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }
}

struct GlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.24), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(0.08), radius: radius * 1.8, x: 0, y: 0)
    }
}

struct PanelCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.surface.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 8) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    func glow(color: Color, radius: CGFloat = 10) -> some View {
        modifier(GlowEffect(color: color, radius: radius))
    }

    func panelCard() -> some View {
        modifier(PanelCard())
    }
}
