import SwiftUI
import AVFoundation
import AppKit

struct PermissionsSheet: View {
    @Binding var isPresented: Bool

    @State private var micStatus: AVAuthorizationStatus = .notDetermined

    private let pollTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Theme.purple.opacity(0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.purple)
                }
                .padding(.bottom, 4)
                Text("Permissions")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("AutoMalik needs two macOS permissions to capture audio and record your voice.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            VStack(spacing: 12) {
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "Records your voice while singing",
                    granted: micStatus == .authorized,
                    actionLabel: micStatus == .denied ? "Open Settings" : "Allow",
                    action: requestMic
                )
                permissionRow(
                    icon: "rectangle.on.rectangle",
                    title: "Screen & System Audio",
                    subtitle: "If capture fails, remove and re-add AutoMalik in System Settings",
                    granted: nil,
                    actionLabel: "Open Settings",
                    action: openScreenSettings
                )
            }

            Button {
                isPresented = false
            } label: {
                Text(allGranted ? "All set — let's go" : "Continue anyway")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(allGranted ? Theme.lime.opacity(0.85) : Theme.surfaceElevated)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .frame(width: 460)
        .background(Theme.surface)
        .onAppear { refresh() }
        .onReceive(pollTimer) { _ in refresh() }
    }

    private var allGranted: Bool {
        micStatus == .authorized
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        granted: Bool?,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        let isGranted = granted == true

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isGranted ? Theme.lime.opacity(0.18) : Color.white.opacity(0.05))
                    .frame(width: 38, height: 38)
                Image(systemName: isGranted ? "checkmark" : icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isGranted ? Theme.lime : Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if isGranted {
                Text("ON")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Theme.lime)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.lime.opacity(0.15)))
            } else {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.purple))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
        )
    }

    private func refresh() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    private func requestMic() {
        if micStatus == .denied || micStatus == .restricted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in refresh() }
        }
    }

    private func openScreenSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
