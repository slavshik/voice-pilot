import Foundation
import Carbon
import Combine
import Speech

class InputLanguageManager: ObservableObject {
    @Published private(set) var activeKeyboardLanguageCode: String = VoiceLanguageCatalog.fallbackLanguageCode
    @Published private(set) var activeCommandLanguageCode: String = VoiceLanguageCatalog.fallbackLanguageCode
    @Published private(set) var activeSpeechLocale: Locale = Locale(identifier: "en-US")

    private var keyboardObserver: NSObjectProtocol?

    private static let preferredSpeechLocalesByLanguage: [String: [String]] = [
        "en": ["en-US", "en-GB"],
        "es": ["es-ES", "es-MX"],
        "de": ["de-DE"],
        "fr": ["fr-FR", "fr-CA"],
        "pl": ["pl-PL"],
        "ru": ["ru-RU"],
    ]

    init() {
        refreshActiveLanguage()

        keyboardObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshActiveLanguage()
        }
    }

    deinit {
        if let keyboardObserver {
            DistributedNotificationCenter.default().removeObserver(keyboardObserver)
        }
    }

    func refreshActiveLanguage() {
        let detectedCode = currentInputLanguageCode() ?? VoiceLanguageCatalog.fallbackLanguageCode
        let keyboardCode = normalizedLanguageCode(from: detectedCode) ?? VoiceLanguageCatalog.fallbackLanguageCode
        let commandCode = VoiceLanguageCatalog.resolvedLanguageCode(for: keyboardCode)
        let locale = preferredSpeechLocale(for: keyboardCode)

        let apply = {
            self.activeKeyboardLanguageCode = keyboardCode
            self.activeCommandLanguageCode = commandCode
            self.activeSpeechLocale = locale
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func currentInputLanguageCode() -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()

        if let languages = stringArrayProperty(source: source, key: kTISPropertyInputSourceLanguages),
           let preferred = preferredLanguageCode(from: languages) {
            return preferred
        }

        if let sourceID = stringProperty(source: source, key: kTISPropertyInputSourceID),
           let languageFromID = parseLanguageCode(fromInputSourceID: sourceID) {
            return languageFromID
        }

        return Locale.current.language.languageCode?.identifier
    }

    private func stringProperty(source: TISInputSource, key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private func stringArrayProperty(source: TISInputSource, key: CFString) -> [String]? {
        guard let ptr = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        let rawArray = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as [AnyObject]
        return rawArray.compactMap { $0 as? String }
    }

    private func preferredLanguageCode(from candidates: [String]) -> String? {
        candidates.compactMap { normalizedLanguageCode(from: $0) }.first
    }

    private func parseLanguageCode(fromInputSourceID sourceID: String) -> String? {
        let lowered = sourceID.lowercased()
        if lowered.contains("russian") { return "ru" }
        if lowered.contains("polish") { return "pl" }
        if lowered.contains("french") { return "fr" }
        if lowered.contains("german") { return "de" }
        if lowered.contains("spanish") { return "es" }
        if lowered.contains(".us") || lowered.contains("abc") || lowered.contains("british") { return "en" }

        let raw = sourceID.replacingOccurrences(of: "com.apple.", with: "")
        let pieces = raw.split(separator: ".")
        guard let last = pieces.last else { return nil }
        return normalizedLanguageCode(from: String(last))
    }

    private func preferredSpeechLocale(for languageCode: String) -> Locale {
        let supported = Set(SFSpeechRecognizer.supportedLocales().map(\.identifier))
        let preferredIDs = Self.preferredSpeechLocalesByLanguage[languageCode] ?? [languageCode]

        for identifier in preferredIDs where supported.contains(identifier) {
            return Locale(identifier: identifier)
        }

        for supportedLocale in SFSpeechRecognizer.supportedLocales() {
            if supportedLocale.language.languageCode?.identifier == languageCode {
                return supportedLocale
            }
        }

        return Locale(identifier: "en-US")
    }

    private func normalizedLanguageCode(from rawCode: String) -> String? {
        let normalized = rawCode
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        guard let base = normalized.split(separator: "-").first else { return nil }
        let code = String(base)
        guard code.count >= 2 else { return nil }
        return String(code.prefix(2))
    }
}
