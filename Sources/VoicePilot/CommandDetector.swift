import Foundation

enum TerminalCommand {
    case enter
    case confirm
    case deny
    case cancel
    case scrollUp
    case scrollDown

    var description: String {
        switch self {
        case .enter: return "Enter"
        case .confirm: return "Confirm (y)"
        case .deny: return "Deny (n)"
        case .cancel: return "Cancel (Ctrl+C)"
        case .scrollUp: return "Scroll Up"
        case .scrollDown: return "Scroll Down"
        }
    }
}

class CommandDetector {
    func detect(_ text: String, languageCode: String) -> TerminalCommand? {
        let profile = VoiceLanguageCatalog.profile(for: languageCode)
        let normalized = VoiceTextNormalizer.normalize(text)

        // Only match short utterances as commands (< 5 words)
        let wordCount = normalized.split(separator: " ").count
        guard wordCount <= 4 else { return nil }

        for entry in profile.commandKeywords {
            for keyword in entry.keywords {
                let normalizedKeyword = VoiceTextNormalizer.normalize(keyword)
                if normalized == normalizedKeyword || normalized == "say \(normalizedKeyword)" {
                    return entry.command
                }
            }
        }

        return nil
    }
}
