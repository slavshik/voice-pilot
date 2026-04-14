import Foundation
import Speech
import AVFoundation

class SpeechEngine: ObservableObject {
    @Published var isListening = false
    @Published var currentTranscript = ""

    private var recognizerLocale: Locale
    private var speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onUtterance: (String) -> Void
    private var activeSessionID: UInt64 = 0
    private let fallbackLocaleIdentifier = "en-US"

    // Silence detection
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0
    private var lastTranscript = ""
    private var lastDeliveryTime: Date = .distantPast

    init(onUtterance: @escaping (String) -> Void, initialLocale: Locale = Locale(identifier: "en-US")) {
        self.onUtterance = onUtterance
        let resolved = Self.resolveRecognizer(for: initialLocale, fallbackIdentifier: "en-US")
        self.recognizerLocale = resolved.locale
        self.speechRecognizer = resolved.recognizer
    }

    func setRecognizerLocale(_ locale: Locale) {
        guard locale.identifier != recognizerLocale.identifier else { return }
        let resolved = Self.resolveRecognizer(for: locale, fallbackIdentifier: fallbackLocaleIdentifier)
        let wasListening = isListening
        teardownCurrentSession()
        recognizerLocale = resolved.locale
        speechRecognizer = resolved.recognizer
        print("Speech recognizer locale changed to: \(resolved.locale.identifier)")
        if wasListening {
            DispatchQueue.main.async { [weak self] in
                self?.beginRecognition()
            }
        }
    }

    func startListening() {
        requestPermissions { [weak self] granted in
            guard granted else {
                print("Speech recognition permission denied")
                return
            }
            DispatchQueue.main.async {
                self?.beginRecognition()
            }
        }
    }

    func stopListening() {
        teardownCurrentSession()
        DispatchQueue.main.async {
            self.isListening = false
        }
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            let granted = status == .authorized
            if !granted {
                print("Speech recognition not authorized: \(status.rawValue)")
            }
            completion(granted)
        }
    }

    private func teardownCurrentSession() {
        activeSessionID &+= 1
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    private static func resolveRecognizer(
        for locale: Locale,
        fallbackIdentifier: String
    ) -> (locale: Locale, recognizer: SFSpeechRecognizer?) {
        if let recognizer = SFSpeechRecognizer(locale: locale) {
            return (locale, recognizer)
        }
        print("SFSpeechRecognizer unavailable for \(locale.identifier); falling back to \(fallbackIdentifier)")
        let fallback = Locale(identifier: fallbackIdentifier)
        return (fallback, SFSpeechRecognizer(locale: fallback))
    }

    private func beginRecognition() {
        guard let speechRecognizer else {
            print("Speech recognizer unavailable for locale: \(recognizerLocale.identifier)")
            DispatchQueue.main.async {
                self.isListening = false
            }
            return
        }

        activeSessionID &+= 1
        let sessionID = activeSessionID

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        if #available(macOS 13, *) {
            request.addsPunctuation = true
        }
        print("Speech recognition start locale=\(recognizerLocale.identifier)")

        let startedLocaleIdentifier = recognizerLocale.identifier

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self, sessionID == self.activeSessionID else { return }

            if let result = result {
                let transcript = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.currentTranscript = transcript
                }
                self.resetSilenceTimer(transcript: transcript, isFinal: result.isFinal)
            }

            var shouldFallbackLocale = false
            if let error = error {
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 209 {
                    print("Speech recognition: missing Assistant asset for locale \(startedLocaleIdentifier)")
                    if startedLocaleIdentifier != self.fallbackLocaleIdentifier {
                        shouldFallbackLocale = true
                        print("Speech recognition falling back to \(self.fallbackLocaleIdentifier)")
                    }
                } else if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
                    // Normal silence — just restart.
                } else {
                    print("Speech recognition error (\(startedLocaleIdentifier)): domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)")
                }
            }

            if error != nil || (result?.isFinal == true) {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil

                if shouldFallbackLocale {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard self.isListening else { return }
                        self.setRecognizerLocale(Locale(identifier: self.fallbackLocaleIdentifier))
                    }
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if self.isListening {
                        self.beginRecognition()
                    }
                }
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isListening = true
                self.currentTranscript = ""
            }
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    private func resetSilenceTimer(transcript: String, isFinal: Bool) {
        silenceTimer?.invalidate()

        if isFinal {
            let now = Date()
            if now.timeIntervalSince(lastDeliveryTime) < 1.5 {
                return
            }
            deliverUtterance(transcript)
            return
        }

        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                self.deliverUtterance(text)
            }
        }
    }

    private func deliverUtterance(_ text: String) {
        let now = Date()
        if now.timeIntervalSince(lastDeliveryTime) < 1.5 {
            return
        }

        lastTranscript = text
        lastDeliveryTime = now
        DispatchQueue.main.async {
            self.currentTranscript = ""
        }

        recognitionRequest?.endAudio()

        onUtterance(text)
    }
}
