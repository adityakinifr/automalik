import SwiftUI
import ScreenCaptureKit
import CoreGraphics

@main
struct AutoMalikApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Eagerly register the app with TCC for screen recording.
        // This causes AutoMalik to appear in System Settings → Privacy & Security
        // → Screen & System Audio Recording, even before the user attempts capture.
        Task.detached(priority: .background) {
            // Triggers TCC registration; safe to call regardless of current state.
            _ = CGPreflightScreenCaptureAccess()
            // Try to query shareable content - this is the canonical way to make
            // ScreenCaptureKit register the app with TCC. It will fail silently
            // if permission is not granted, but the app will now be in the list.
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1180, minHeight: 860)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1300, height: 900)
    }
}
