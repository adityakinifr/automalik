import SwiftUI

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let icon: String
    let tint: Color

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(toast.tint)
            Text(toast.message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(Theme.surfaceElevated)
                .overlay(
                    Capsule().strokeBorder(toast.tint.opacity(0.45), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }
}
