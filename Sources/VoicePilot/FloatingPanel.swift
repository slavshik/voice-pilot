import SwiftUI
import AppKit
import Combine

class FloatingPanelController: NSObject, ObservableObject, NSWindowDelegate {
    var window: NSWindow?
    private var speechEngine: SpeechEngine
    private var confirmationManager: ConfirmationManager
    private var promptBuilder: PromptBuilder
    private var terminalController: TerminalController
    @Published var isMini = true

    private let miniWidth: CGFloat = 300
    private let fullWidth: CGFloat = 320
    private let miniMinHeight: CGFloat = 60
    private let miniMaxHeight: CGFloat = 260
    private let fullMinHeight: CGFloat = 220
    private let fullMaxHeight: CGFloat = 560

    init(speechEngine: SpeechEngine, confirmationManager: ConfirmationManager, promptBuilder: PromptBuilder, terminalController: TerminalController) {
        self.speechEngine = speechEngine
        self.confirmationManager = confirmationManager
        self.promptBuilder = promptBuilder
        self.terminalController = terminalController
        super.init()
        showWindow()
    }

    func showWindow() {
        let view = MainView(
            speechEngine: speechEngine,
            confirmationManager: confirmationManager,
            promptBuilder: promptBuilder,
            terminalController: terminalController,
            panelController: self
        )
        .preferredColorScheme(.dark)

        let hostingView = NSHostingView(rootView: view)
        let miniSize = NSRect(x: 0, y: 0, width: 300, height: 90)

        let window = NSWindow(
            contentRect: miniSize,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Voice Pilot"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = hostingView
        window.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        window.isOpaque = true
        window.hasShadow = true
        window.minSize = NSSize(width: 260, height: 90)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 320
            let y = screenFrame.maxY - 110
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    // Green button (zoom) toggles mini/full
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        toggleMini()
        return false // We handle it ourselves
    }

    func toggleMini() {
        guard let window = window else { return }
        isMini.toggle()
        let frame = window.frame
        let targetWidth = isMini ? miniWidth : fullWidth
        let targetHeight: CGFloat = isMini ? 90 : 300
        let topY = frame.maxY
        let newFrame = NSRect(x: frame.minX, y: topY - targetHeight, width: targetWidth, height: targetHeight)
        window.setFrame(newFrame, display: true, animate: true)
    }

    func adjustContentHeight(_ measured: CGFloat) {
        guard let window = window, measured > 0 else { return }
        let minH = isMini ? miniMinHeight : fullMinHeight
        let maxH = isMini ? miniMaxHeight : fullMaxHeight
        let target = max(minH, min(measured, maxH))
        let frame = window.frame
        if abs(frame.height - target) < 0.5 { return }
        let topY = frame.maxY
        let newFrame = NSRect(x: frame.minX, y: topY - target, width: frame.width, height: target)
        window.setFrame(newFrame, display: true, animate: false)
    }
}

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Main View

struct MainView: View {
    @ObservedObject var speechEngine: SpeechEngine
    @ObservedObject var confirmationManager: ConfirmationManager
    @ObservedObject var promptBuilder: PromptBuilder
    @ObservedObject var terminalController: TerminalController
    @ObservedObject var panelController: FloatingPanelController

    let bg = Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0))

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if panelController.isMini {
                    MiniContent(
                        speechEngine: speechEngine,
                        confirmationManager: confirmationManager
                    )
                } else if promptBuilder.isActive {
                    BuilderContent(
                        speechEngine: speechEngine,
                        promptBuilder: promptBuilder
                    )
                } else {
                    FullContent(
                        speechEngine: speechEngine,
                        confirmationManager: confirmationManager,
                        promptBuilder: promptBuilder,
                        terminalController: terminalController
                    )
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
        .onPreferenceChange(ContentHeightKey.self) { height in
            panelController.adjustContentHeight(height)
        }
    }
}

// MARK: - Mini Content

struct MiniContent: View {
    @ObservedObject var speechEngine: SpeechEngine
    @ObservedObject var confirmationManager: ConfirmationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer().frame(height: 22)

            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(speechEngine.isListening ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)

                if confirmationManager.isRefining {
                    HStack(alignment: .top, spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(confirmationManager.originalText)
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.5))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Refining via OpenRouter…")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.orange.opacity(0.8))
                        }
                    }
                } else if confirmationManager.isShowingConfirmation {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                                .padding(.top, 2)
                            Text(confirmationManager.refinedText)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(Color.green.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if confirmationManager.countdown > 0 {
                                Text("\(confirmationManager.countdown)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(Color.orange.opacity(0.9))
                                    .padding(.top, 2)
                            }
                        }
                        if !confirmationManager.refinementSource.isEmpty {
                            Text(confirmationManager.refinementSource)
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.5))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.white.opacity(0.08))
                                )
                                .padding(.leading, 14)
                        }
                    }
                } else if !speechEngine.currentTranscript.isEmpty {
                    Text(speechEngine.currentTranscript)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(speechEngine.isListening ? "Listening..." : "Paused")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.3))
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Full Content

struct FullContent: View {
    @ObservedObject var speechEngine: SpeechEngine
    @ObservedObject var confirmationManager: ConfirmationManager
    @ObservedObject var promptBuilder: PromptBuilder
    @ObservedObject var terminalController: TerminalController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Spacer().frame(height: 22)

                // Transcript
                if !speechEngine.currentTranscript.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                            .padding(.top, 2)
                        Text(speechEngine.currentTranscript)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.2))
                        Text("Speak a command or prompt...")
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.2))
                    }
                }

                if confirmationManager.isRefining {
                    HStack(alignment: .top, spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(confirmationManager.originalText)
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.5))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Refining via OpenRouter…")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.orange.opacity(0.8))
                        }
                    }
                }

                if confirmationManager.isShowingConfirmation {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                                .padding(.top, 2)
                            Text(confirmationManager.refinedText)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(Color.green.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !confirmationManager.refinementSource.isEmpty {
                            Text(confirmationManager.refinementSource)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.5))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.08))
                                )
                                .padding(.leading, 16)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Bottom bar
            VStack(spacing: 8) {
                // Native mode toggle
                NativeSegmentedToggle(
                    items: ["Voice Control", "Prompt Builder"],
                    selectedIndex: Binding(
                        get: { promptBuilder.isActive ? 1 : 0 },
                        set: { idx in
                            if idx == 1 { promptBuilder.start() }
                            else { promptBuilder.stop() }
                        }
                    )
                )
                .frame(height: 24)

                // Status row
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(speechEngine.isListening ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(speechEngine.isListening ? "Listening" : "Muted")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.25))
                    }
                    Spacer()
                    NativeButton(title: speechEngine.isListening ? "Mute" : "Unmute") {
                        speechEngine.toggleListening()
                    }
                    .frame(width: 65, height: 20)
                    BackendMenu(terminalController: terminalController)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.02))
        }
    }
}

// MARK: - Backend Menu

struct BackendMenu: View {
    @ObservedObject var terminalController: TerminalController

    var body: some View {
        Menu {
            Button("Auto-detect tmux pane") {
                terminalController.clearTmuxPin()
                terminalController.setBackend(.tmux)
            }
            Button("Pin current active tmux pane") {
                terminalController.setBackend(.tmux)
                terminalController.pinCurrentTmuxPane()
            }
            Button("Use AppleScript") {
                terminalController.setBackend(.appleScript)
            }
            Divider()
            Button("Set tmux path…") {
                promptForTmuxPath()
            }
            Button("Refresh target") {
                terminalController.refreshTargetDescription()
            }
        } label: {
            Text(labelText)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(.white.opacity(0.7))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(maxWidth: 160, alignment: .trailing)
        .onAppear { terminalController.refreshTargetDescription() }
    }

    private var labelText: String {
        let prefix = terminalController.backendKind.displayName
        if let target = terminalController.targetDescription, !target.isEmpty {
            return "\(prefix): \(target)"
        }
        return prefix
    }

    private func promptForTmuxPath() {
        let alert = NSAlert()
        alert.messageText = "tmux binary path"
        alert.informativeText = "Leave empty to auto-detect from Homebrew / /usr/bin."
        alert.alertStyle = .informational
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = terminalController.tmuxBackend.configuredTmuxPath ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            terminalController.setTmuxPath(field.stringValue)
        }
    }
}

// MARK: - Builder Content

struct BuilderContent: View {
    @ObservedObject var speechEngine: SpeechEngine
    @ObservedObject var promptBuilder: PromptBuilder

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Spacer().frame(height: 22)

                if !speechEngine.currentTranscript.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                        Text(speechEngine.currentTranscript)
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.5))
                            .lineLimit(2)
                    }
                }

                if promptBuilder.isRefining {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Refining...")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                } else if !promptBuilder.currentDraft.isEmpty {
                    ScrollView {
                        Text(promptBuilder.currentDraft)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Describe your prompt...")
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.25))
                        Text("Speak freely. Refine as you go.")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.15))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(spacing: 8) {
                // Native mode toggle
                NativeSegmentedToggle(
                    items: ["Voice Control", "Prompt Builder"],
                    selectedIndex: Binding(
                        get: { promptBuilder.isActive ? 1 : 0 },
                        set: { idx in
                            if idx == 1 { promptBuilder.start() }
                            else { promptBuilder.stop() }
                        }
                    )
                )
                .frame(height: 24)

                // Model + hints row
                HStack {
                    Picker("", selection: Binding(
                        get: { promptBuilder.selectedModel },
                        set: { promptBuilder.selectedModel = $0 }
                    )) {
                        ForEach(BuilderModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)
                    .controlSize(.small)

                    Spacer()

                    Text("\"send\" \u{2022} \"cancel\"")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.2))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.02))
        }
    }
}
