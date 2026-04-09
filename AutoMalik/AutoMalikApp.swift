import SwiftUI

@main
struct AutoMalikApp: App {
    @StateObject private var appState = AppState()

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
