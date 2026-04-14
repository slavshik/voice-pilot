import SwiftUI
import Combine

@main
struct VoicePilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController?
    var speechEngine: SpeechEngine?
    var commandDetector: CommandDetector?
    var promptRefiner: PromptRefiner?
    var terminalController: TerminalController?
    var confirmationManager: ConfirmationManager?
    var floatingPanel: FloatingPanelController?
    var promptBuilder: PromptBuilder?
    var inputLanguageManager: InputLanguageManager?

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        inputLanguageManager = InputLanguageManager()
        terminalController = TerminalController()
        terminalController?.onError = { [weak self] msg in
            self?.statusBar?.flash(msg)
        }
        commandDetector = CommandDetector()
        promptRefiner = PromptRefiner()
        confirmationManager = ConfirmationManager(terminalController: terminalController!)
        promptBuilder = PromptBuilder()

        let initialLocale = inputLanguageManager?.activeSpeechLocale ?? Locale(identifier: "en-US")
        speechEngine = SpeechEngine(
            onUtterance: { [weak self] utterance in
                self?.handleUtterance(utterance)
            },
            initialLocale: initialLocale
        )

        // Show persistent floating panel with all controls
        floatingPanel = FloatingPanelController(
            speechEngine: speechEngine!,
            confirmationManager: confirmationManager!,
            promptBuilder: promptBuilder!,
            terminalController: terminalController!
        )

        statusBar = StatusBarController(
            speechEngine: speechEngine!,
            onQuit: { NSApp.terminate(nil) },
            onShowWindow: { [weak self] in
                self?.floatingPanel?.window?.makeKeyAndOrderFront(nil)
            }
        )

        inputLanguageManager?.$activeSpeechLocale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] locale in
                self?.speechEngine?.setRecognizerLocale(locale)
            }
            .store(in: &cancellables)

        inputLanguageManager?.$activeCommandLanguageCode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] languageCode in
                self?.promptRefiner?.activeLanguageCode = languageCode
                self?.promptBuilder?.activeLanguageCode = languageCode
                self?.statusBar?.flash("Lang: \(languageCode.uppercased())")
            }
            .store(in: &cancellables)

        speechEngine?.startListening()
    }

    private func handleUtterance(_ text: String) {
        let normalizedText = VoiceTextNormalizer.normalize(text)
        guard !normalizedText.isEmpty else { return }

        let languageCode = inputLanguageManager?.activeCommandLanguageCode ?? VoiceLanguageCatalog.fallbackLanguageCode
        let profile = VoiceLanguageCatalog.profile(for: languageCode)

        // Mute/unmute commands
        if isExactMatch(normalizedText, phrases: profile.app.mute) {
            speechEngine?.stopListening()
            return
        }

        // Window control commands
        if isExactMatch(normalizedText, phrases: profile.app.expandExact)
            || containsMatch(normalizedText, phrases: profile.app.expandContains) {
            floatingPanel?.toggleMini()
            return
        }
        if isExactMatch(normalizedText, phrases: profile.app.minimize) {
            if floatingPanel?.isMini == false {
                floatingPanel?.toggleMini()
            }
            return
        }

        // --- Prompt Builder mode ---
        if promptBuilder?.isActive == true {
            // "send" / "done" / "ship it" — send the draft to terminal
            if isExactMatch(normalizedText, phrases: profile.app.builderSend) {
                if let draft = promptBuilder?.currentDraft, !draft.isEmpty {
                    terminalController?.pasteAndEnter(draft)
                    confirmationManager?.showBriefly(draft)
                    promptBuilder?.stop()
                }
                return
            }
            // "cancel" / "discard" / "voice control" — exit builder without sending
            if isExactMatch(normalizedText, phrases: profile.app.builderCancelExact)
                || containsMatch(normalizedText, phrases: profile.app.builderCancelContains) {
                promptBuilder?.stop()
                return
            }
            // "start over" — reset but stay in builder
            if isExactMatch(normalizedText, phrases: profile.app.builderReset) {
                promptBuilder?.start()
                return
            }
            // Otherwise — feed input to builder
            print("[App] Builder input: \(text)")
            promptBuilder?.addInput(text) {
                print("[App] Builder refinement complete")
            }
            return
        }

        // --- Normal mode ---

        // Voice command to activate prompt builder
        if containsMatch(normalizedText, phrases: profile.app.builderActivateContains)
            || isExactMatch(normalizedText, phrases: profile.app.builderActivateExact) {
            promptBuilder?.start()
            return
        }

        // Check if it's a confirmation/cancel for pending prompt
        if confirmationManager?.isShowingConfirmation == true {
            if isExactMatch(normalizedText, phrases: profile.app.confirmationYes) {
                confirmationManager?.confirmNow()
                return
            }
            if isExactMatch(normalizedText, phrases: profile.app.confirmationNo) {
                confirmationManager?.cancel()
                return
            }
        }

        // Check if it's a terminal command
        if let command = commandDetector?.detect(text, languageCode: languageCode) {
            DispatchQueue.main.async { [weak self] in
                self?.statusBar?.flash(command.description)
                self?.terminalController?.execute(command)
            }
            return
        }

        // It's a prompt — clean up and send directly to terminal
        promptRefiner?.refine(text) { [weak self] refined in
            DispatchQueue.main.async {
                self?.confirmationManager?.showBriefly(refined)
                self?.terminalController?.pasteAndEnter(refined)
            }
        }
    }

    private func isExactMatch(_ normalizedText: String, phrases: [String]) -> Bool {
        for phrase in phrases where normalizedText == VoiceTextNormalizer.normalize(phrase) {
            return true
        }
        return false
    }

    private func containsMatch(_ normalizedText: String, phrases: [String]) -> Bool {
        for phrase in phrases where normalizedText.contains(VoiceTextNormalizer.normalize(phrase)) {
            return true
        }
        return false
    }
}
