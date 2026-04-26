import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import CoreGraphics

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    @State private var errorMessage: String?
    @State private var nowPlayingURL: URL?
    @State private var isImporting = false
    @State private var toast: Toast?
    @State private var showPermissions = false
    @AppStorage("hasSeenPermissions") private var hasSeenPermissions = false

    var body: some View {
        ZStack {
            AnimatedBackground()

            VStack(spacing: 0) {
                topToolbar

                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)

                HStack(spacing: 0) {
                    workflowSidebar
                        .frame(width: 250)

                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 1)

                    mainWorkspace

                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 1)

                    inspectorPanel
                        .frame(width: 330)
                }
            }

            if let toast {
                VStack {
                    Spacer()
                    ToastView(toast: toast)
                        .padding(.bottom, 28)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1220, minHeight: 820)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audio, .wav, .mp3, .mpeg4Audio],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { msg in
            Text(msg)
        }
        .sheet(isPresented: $showPermissions) {
            PermissionsSheet(isPresented: $showPermissions)
                .onDisappear { hasSeenPermissions = true }
        }
        .onAppear {
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            let micNeedsAttention = micStatus == .denied || micStatus == .restricted || (!hasSeenPermissions && micStatus == .notDetermined)
            if micNeedsAttention {
                showPermissions = true
            }
        }
        .onChange(of: appState.hasSeparatedAudio) { newValue in
            if newValue { showToast(Toast(message: "Vocals isolated", icon: "waveform", tint: Theme.cyan)) }
        }
        .onChange(of: appState.hasRecording) { newValue in
            if newValue { showToast(Toast(message: "Recording captured", icon: "mic.fill", tint: Theme.pink)) }
        }
        .onChange(of: appState.hasAutoTunedRecording) { newValue in
            if newValue { showToast(Toast(message: "Auto-tuned to \(appState.selectedKey.root.displayName) \(appState.selectedKey.scale.rawValue)", icon: "tuningfork", tint: Theme.lime)) }
        }
        .onChange(of: appState.hasFinalMix) { newValue in
            if newValue { showToast(Toast(message: "Mix ready to export", icon: "square.and.arrow.up", tint: Theme.purple)) }
        }
    }

    private func showToast(_ t: Toast) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            toast = t
        }
        let id = t.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toast?.id == id {
                withAnimation(.easeOut(duration: 0.25)) { toast = nil }
            }
        }
    }

    // MARK: - Chrome

    private var topToolbar: some View {
        HStack {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.primaryGradient)
                        .frame(width: 42, height: 42)
                        .shadow(color: Theme.coral.opacity(0.24), radius: 16, y: 8)
                    Image(systemName: "tuningfork")
                        .font(.system(size: 19, weight: .black))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("AutoMalik")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Karaoke tuning studio")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                statusPill(systemImage: "music.note", title: sessionStatusTitle, tint: sessionStatusTint)
                statusPill(systemImage: "pianokeys", title: "\(appState.selectedKey.root.displayName) \(appState.selectedKey.scale.rawValue)", tint: Theme.amber)

                Button {
                    showPermissions = true
                } label: {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 34)
                        .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Permissions")

                Button {
                    appState.newProject()
                    nowPlayingURL = nil
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 34)
                        .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("New Session")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var workflowSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Workflow")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text("Move from source capture to a finished tuned mix.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
            }

            VStack(spacing: 8) {
                ForEach(PipelineStage.allCases) { stage in
                    workflowRow(stage)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Text("Session")
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(Theme.textTertiary)

                metricRow("Source", value: appState.hasCapturedAudio ? "Loaded" : "Empty", tint: appState.hasCapturedAudio ? Theme.mint : Theme.textTertiary)
                metricRow("Vocals", value: appState.hasRecording ? "Recorded" : (appState.hasSeparatedAudio ? "Ready" : "Waiting"), tint: appState.hasRecording ? Theme.mint : Theme.textTertiary)
                metricRow("Mix", value: appState.hasFinalMix ? "Ready" : "Not built", tint: appState.hasFinalMix ? Theme.mint : Theme.textTertiary)
            }
            .padding(14)
            .background(Theme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
        }
        .padding(20)
        .background(Theme.panel.opacity(0.88))
    }

    private var mainWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroSection

                HStack(alignment: .top, spacing: 16) {
                    SourceCard(
                        isImporting: $isImporting,
                        nowPlayingURL: $nowPlayingURL,
                        errorMessage: $errorMessage
                    )
                    VocalsCard(
                        nowPlayingURL: $nowPlayingURL,
                        errorMessage: $errorMessage
                    )
                }

                bottomMixStrip
            }
            .padding(22)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Studio

    private var heroSection: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Now Playing")
                        .font(.system(size: 11, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                    Text(nowPlayingTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(nowPlayingSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()

                if nowPlayingURL != nil {
                    Button { togglePlay() } label: {
                        Image(systemName: appState.playbackRecorder.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Theme.accentGradient, in: Circle())
                            .shadow(color: Theme.teal.opacity(0.28), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)
                    .help(appState.playbackRecorder.isPlaying ? "Pause" : "Play")
                }
            }

            AnimatedWaveform(
                audioURL: nowPlayingURL,
                liveLevel: appState.isCapturing ? appState.captureLevel : (appState.playbackRecorder.isRecording ? appState.playbackRecorder.micLevel : 0),
                isPlaying: appState.playbackRecorder.isPlaying,
                progress: appState.playbackRecorder.playbackProgress,
                onSeek: { p in
                    let recorder = appState.playbackRecorder
                    if recorder.playbackDuration > 0 {
                        recorder.seek(to: p * recorder.playbackDuration)
                    } else if let url = nowPlayingURL {
                        try? recorder.playFile(url)
                        recorder.seek(to: p * recorder.playbackDuration)
                    }
                }
            )
            .frame(height: 168)
            .padding(18)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))

            HStack(spacing: 10) {
                transportStat("Mode", value: appState.isLiveMode ? "Live" : "Offline", tint: appState.isLiveMode ? Theme.mint : Theme.amber)
                transportStat("Capture", value: appState.isCapturing ? formatDuration(appState.captureDuration) : (appState.hasCapturedAudio ? "Loaded" : "Idle"), tint: appState.isCapturing ? Theme.coral : Theme.teal)
                transportStat("Tuning", value: appState.hasAutoTunedRecording ? "Printed" : (appState.isProcessingAutoTune ? "Running" : "\(Int(appState.autoTuneStrength * 100))%"), tint: Theme.purple)
                Spacer()
            }
        }
        .padding(22)
        .glassCard(cornerRadius: 8)
    }

    private var nowPlayingTitle: String {
        if appState.isCapturing { return "● Capturing System Audio..." }
        if appState.playbackRecorder.isRecording { return "● Recording Vocals..." }
        if let url = nowPlayingURL { return url.lastPathComponent }
        return "No track loaded"
    }

    private var nowPlayingSubtitle: String {
        if appState.isCapturing { return "LIVE INPUT" }
        if appState.playbackRecorder.isRecording { return "MIC SIGNAL" }
        if nowPlayingURL != nil { return "READY TO PLAY" }
        return "DROP A FILE OR CAPTURE FROM SYSTEM"
    }

    // MARK: - Inspector

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader("Tuning", systemImage: "tuningfork")

                    PitchWheel(key: appState.selectedKey)
                        .frame(height: 205)
                        .padding(.vertical, 4)

                    keyControls

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Strength")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(Int(appState.autoTuneStrength * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        Slider(value: $appState.autoTuneStrength, in: 0...1)
                            .tint(Theme.coral)
                            .onChange(of: appState.autoTuneStrength) { newValue in
                                appState.liveAutoTuner.setStrength(newValue)
                            }
                    }
                }
                .panelCard()

                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader("Monitor", systemImage: "slider.horizontal.3")
                    mixSlider(label: "Track", value: $appState.instrumentalPlaybackVolume, color: Theme.teal)
                    mixSlider(label: "Guide", value: $appState.guideVocalVolume, color: Theme.coral)
                    mixSlider(label: "Mic", value: $appState.micMonitorVolume, color: Theme.purple)
                }
                .panelCard()

                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader("Mixdown", systemImage: "square.and.arrow.down")
                    mixSlider(label: "Inst", value: $appState.instrumentalMixVolume, color: Theme.teal)
                    mixSlider(label: "Vox", value: $appState.vocalMixVolume, color: Theme.coral)

                    GlowButton(
                        "Create Mix",
                        systemImage: "wand.and.stars",
                        gradient: Theme.accentGradient
                    ) {
                        createMix()
                    }
                    .frame(maxWidth: .infinity)

                    GlowButton(
                        "Export WAV",
                        systemImage: "square.and.arrow.down",
                        gradient: Theme.primaryGradient
                    ) {
                        exportFile()
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(appState.hasFinalMix ? 1.0 : 0.42)
                    .disabled(!appState.hasFinalMix)
                }
                .panelCard()
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .background(Theme.panel.opacity(0.72))
    }

    private var keyControls: some View {
        HStack(spacing: 10) {
            Picker("Root", selection: selectedRoot) {
                ForEach(NoteName.allCases) { note in
                    Text(note.displayName).tag(note)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Picker("Scale", selection: selectedScale) {
                ForEach(ScaleType.allCases) { scale in
                    Text(scale.rawValue).tag(scale)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }

    private var bottomMixStrip: some View {
        HStack(spacing: 14) {
            statusPill(systemImage: "waveform", title: appState.hasSeparatedAudio ? "Stems isolated" : "Source needed", tint: appState.hasSeparatedAudio ? Theme.mint : Theme.textTertiary)
            statusPill(systemImage: "mic.fill", title: appState.hasRecording ? "Vocal take ready" : "No take yet", tint: appState.hasRecording ? Theme.mint : Theme.textTertiary)
            statusPill(systemImage: "checkmark.seal", title: appState.hasFinalMix ? "Mix ready" : "Export pending", tint: appState.hasFinalMix ? Theme.mint : Theme.textTertiary)
            Spacer()
        }
        .padding(16)
        .glassCard(cornerRadius: 8)
    }

    private func mixSlider(label: String, value: Binding<Float>, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 42, alignment: .leading)
            Slider(value: value, in: 0...1)
                .tint(color)
            Text("\(Int(value.wrappedValue * 100))")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func workflowRow(_ stage: PipelineStage) -> some View {
        let state = stageState(stage)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(stageTint(stage, state: state).opacity(state == .pending ? 0.08 : 0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: state == .complete ? "checkmark" : stage.systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(stageTint(stage, state: state))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(stage.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(state == .pending ? Theme.textSecondary : .white)
                Text(stageSubtitle(stage))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(state == .active ? Theme.surface : Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(state == .active ? Theme.borderStrong : Theme.border, lineWidth: 1))
    }

    private func stageState(_ stage: PipelineStage) -> CardStepState {
        if appState.completedStages.contains(stage) || (stage == .mixExport && appState.hasFinalMix) {
            return .complete
        }
        if stage == .capture && !appState.hasCapturedAudio { return .active }
        if stage == .separation && appState.hasCapturedAudio && !appState.hasSeparatedAudio { return .active }
        if stage == .recording && appState.hasSeparatedAudio && !appState.hasRecording { return .active }
        if stage == .autoTune && appState.hasRecording && !appState.hasAutoTunedRecording { return .active }
        if stage == .mixExport && appState.hasAutoTunedRecording && !appState.hasFinalMix { return .active }
        return .pending
    }

    private func stageSubtitle(_ stage: PipelineStage) -> String {
        switch stage {
        case .capture:
            return appState.hasCapturedAudio ? "Track loaded" : "Import or record system audio"
        case .separation:
            return appState.hasSeparatedAudio ? "Instrumental and vocals ready" : "Split the source"
        case .recording:
            return appState.hasRecording ? "Take captured" : "Record your vocal"
        case .autoTune:
            return appState.hasAutoTunedRecording ? "Tuned vocal printed" : "Correct pitch"
        case .mixExport:
            return appState.hasFinalMix ? "WAV ready" : "Balance and export"
        }
    }

    private func stageTint(_ stage: PipelineStage, state: CardStepState) -> Color {
        if state == .complete { return Theme.mint }
        if state == .pending { return Theme.textTertiary }
        switch stage {
        case .capture: return Theme.teal
        case .separation: return Theme.amber
        case .recording: return Theme.coral
        case .autoTune: return Theme.purple
        case .mixExport: return Theme.mint
        }
    }

    private func statusPill(systemImage: String, title: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Theme.controlFill, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
    }

    private func transportStat(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func metricRow(_ label: String, value: String, tint: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.teal)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
        }
    }

    private var selectedRoot: Binding<NoteName> {
        Binding(
            get: { appState.selectedKey.root },
            set: { appState.selectedKey = MusicalKey(root: $0, scale: appState.selectedKey.scale) }
        )
    }

    private var selectedScale: Binding<ScaleType> {
        Binding(
            get: { appState.selectedKey.scale },
            set: { appState.selectedKey = MusicalKey(root: appState.selectedKey.root, scale: $0) }
        )
    }

    private var sessionStatusTitle: String {
        if appState.isCapturing { return "Capturing" }
        if appState.playbackRecorder.isRecording { return "Recording" }
        if appState.liveAutoTuner.isRunning { return "Live Tune" }
        if appState.hasFinalMix { return "Mix Ready" }
        if appState.hasAutoTunedRecording { return "Tuned" }
        if appState.hasSeparatedAudio { return "Stems Ready" }
        if appState.hasCapturedAudio { return "Source Loaded" }
        return "New Session"
    }

    private var sessionStatusTint: Color {
        if appState.isCapturing || appState.playbackRecorder.isRecording { return Theme.coral }
        if appState.liveAutoTuner.isRunning || appState.hasFinalMix { return Theme.mint }
        if appState.hasSeparatedAudio || appState.hasAutoTunedRecording { return Theme.teal }
        return Theme.amber
    }

    // MARK: - Actions

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // Copy file into project directory
            do {
                let dest = appState.project.capturedAudioURL
                let fm = FileManager.default
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                try fm.copyItem(at: url, to: dest)
                appState.hasCapturedAudio = true
                appState.markStageComplete(.capture)
                nowPlayingURL = dest
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func togglePlay() {
        if appState.playbackRecorder.isPlaying {
            appState.playbackRecorder.stop()
        } else if let url = nowPlayingURL {
            try? appState.playbackRecorder.playFile(url)
        }
    }

    private func createMix() {
        guard appState.hasSeparatedAudio else {
            errorMessage = "Separate vocals first to create a mix."
            return
        }

        let vocalSource = appState.hasAutoTunedRecording
            ? appState.project.tunedRecordingURL
            : (appState.hasRecording ? appState.project.rawRecordingURL : appState.project.vocalsURL)

        Task.detached {
            do {
                let mixer = AudioMixer()
                let instrumentalURL = await MainActor.run { self.appState.project.instrumentalURL }
                let outputURL = await MainActor.run { self.appState.project.finalMixURL }
                let instVol = await MainActor.run { self.appState.instrumentalMixVolume }
                let vocVol = await MainActor.run { self.appState.vocalMixVolume }

                try mixer.mixTracks(
                    instrumentalURL: instrumentalURL,
                    vocalURL: vocalSource,
                    instrumentalVolume: instVol,
                    vocalVolume: vocVol,
                    outputURL: outputURL
                )

                await MainActor.run {
                    self.appState.hasFinalMix = true
                    self.nowPlayingURL = outputURL
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.wav]
        panel.nameFieldStringValue = "AutoMalik_Mix.wav"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: url.path) {
                    try fm.removeItem(at: url)
                }
                try fm.copyItem(at: appState.project.finalMixURL, to: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
