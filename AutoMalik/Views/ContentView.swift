import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(PipelineStage.allCases, selection: $appState.currentStage) { stage in
            Button {
                if appState.isStageAccessible(stage) {
                    appState.currentStage = stage
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(stageColor(stage))
                            .frame(width: 28, height: 28)
                        if appState.completedStages.contains(stage) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(stage.stepNumber)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.title)
                            .font(.headline)
                            .foregroundStyle(appState.isStageAccessible(stage) ? .primary : .secondary)
                    }

                    Spacer()

                    Image(systemName: stage.systemImage)
                        .foregroundStyle(appState.isStageAccessible(stage) ? .secondary : .quaternary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(!appState.isStageAccessible(stage))
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem {
                Button("New Session") {
                    appState.newProject()
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch appState.currentStage {
        case .capture:
            CaptureView()
        case .separation:
            SeparationView()
        case .recording:
            RecordingView()
        case .autoTune:
            AutoTuneView()
        case .mixExport:
            MixExportView()
        }
    }

    // MARK: - Helpers

    private func stageColor(_ stage: PipelineStage) -> Color {
        if appState.completedStages.contains(stage) {
            return .green
        } else if stage == appState.currentStage {
            return .accentColor
        } else if appState.isStageAccessible(stage) {
            return .gray
        } else {
            return .gray.opacity(0.3)
        }
    }
}
