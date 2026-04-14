import Foundation

class PromptRefiner {
    private let apiKey: String
    private let model = "claude-sonnet-4-6"
    var activeLanguageCode = VoiceLanguageCatalog.fallbackLanguageCode

    init() {
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            self.apiKey = key
        } else if let key = Self.loadKeyFromEnvFile() {
            self.apiKey = key
        } else {
            self.apiKey = ""
            print("Warning: No ANTHROPIC_API_KEY found. Prompt refinement will pass through raw text.")
        }
    }

    func refine(_ rawSpeech: String, completion: @escaping (String) -> Void) {
        let profile = VoiceLanguageCatalog.profile(for: activeLanguageCode)

        // Use basic cleanup only — fast and reliable
        let cleaned = stripTriggerWords(rawSpeech, triggerWords: profile.promptTriggerWords)
        completion(cleanBasic(cleaned, languageCode: activeLanguageCode))
        return

        guard !apiKey.isEmpty else {
            completion(cleanBasic(rawSpeech, languageCode: activeLanguageCode))
            return
        }

        _ = stripTriggerWords(rawSpeech, triggerWords: profile.promptTriggerWords)

        let systemPrompt = systemPrompt(for: activeLanguageCode)

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 150,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": cleaned]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(cleanBasic(rawSpeech, languageCode: activeLanguageCode))
            return
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let rawText = content.first?["text"] as? String else {
                completion(self?.cleanBasic(cleaned, languageCode: self?.activeLanguageCode ?? VoiceLanguageCatalog.fallbackLanguageCode) ?? cleaned)
                return
            }

            let result = self.extractPrompt(rawText)
            completion(result.isEmpty ? self.cleanBasic(cleaned, languageCode: self.activeLanguageCode) : result)
        }.resume()
    }

    private func extractPrompt(_ text: String) -> String {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate — if it contains questions or commentary, reject
        let lower = result.lowercased()
        let badPatterns = [
            "i need more", "could you provide", "please provide",
            "i apologize", "i'm sorry", "let me reconsider",
            "however,", "here's my", "here is my", "here's the",
            "what specific", "what do you want",
            "i don't have", "i cannot", "breaking my own",
            "confidence", "status", "budget"
        ]
        for pattern in badPatterns {
            if lower.contains(pattern) {
                return ""
            }
        }

        // If response is way longer than input, it's probably rambling
        if result.count > text.count * 3 {
            return ""
        }

        return result
    }

    private func systemPrompt(for languageCode: String) -> String {
        switch VoiceLanguageCatalog.resolvedLanguageCode(for: languageCode) {
        case "es":
            return """
            Eres un convertidor de voz a prompt. Entrada: transcripción de voz desordenada. Salida: prompt limpio para CLI.

            REGLAS:
            1. Devuelve SOLO el prompt limpio.
            2. Sin preguntas, comentarios ni explicaciones.
            3. Quita muletillas y corrige gramática.
            4. Máximo 1-3 frases, directo y accionable.
            """
        case "de":
            return """
            Du bist ein Sprach-zu-Prompt-Konverter. Eingabe: unordentliche Spracherkennung. Ausgabe: sauberer CLI-Prompt.

            REGELN:
            1. Gib NUR den bereinigten Prompt aus.
            2. Keine Fragen, Kommentare oder Erklärungen.
            3. Entferne Füllwörter und verbessere Grammatik.
            4. Maximal 1-3 Sätze, direkt und umsetzbar.
            """
        case "fr":
            return """
            Tu es un convertisseur voix-vers-prompt. Entrée: transcription vocale brouillonne. Sortie: prompt CLI propre.

            RÈGLES:
            1. Retourne UNIQUEMENT le prompt nettoyé.
            2. Aucune question, aucun commentaire, aucune explication.
            3. Supprime les mots parasites et corrige la grammaire.
            4. 1 à 3 phrases max, directes et actionnables.
            """
        case "pl":
            return """
            Jesteś konwerterem mowy na prompt. Wejście: chaotyczna transkrypcja mowy. Wyjście: czysty prompt CLI.

            ZASADY:
            1. Zwracaj WYŁĄCZNIE oczyszczony prompt.
            2. Bez pytań, komentarzy i wyjaśnień.
            3. Usuń wypełniacze i popraw gramatykę.
            4. 1-3 zdania maksymalnie, konkretnie i rzeczowo.
            """
        default:
            return """
            You are a speech-to-prompt converter. Input: messy voice transcription. Output: clean CLI prompt.

            RULES:
            1. Output ONLY the cleaned prompt. Zero other text.
            2. No questions. No commentary. No apologies. No explanations.
            3. No prefixes like "Here's..." or "Refined:". Just the prompt.
            4. Remove filler words.
            5. Fix grammar and make intent clear.
            6. 1-3 sentences max. Be direct.
            7. If input is unclear, make your best guess. NEVER ask for clarification.
            """
        }
    }

    private func stripTriggerWords(_ text: String, triggerWords: [String]) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = VoiceTextNormalizer.normalize(cleaned)
        for trigger in triggerWords {
            let normalizedTrigger = VoiceTextNormalizer.normalize(trigger)
            if lower.hasSuffix(normalizedTrigger) {
                let endIndex = cleaned.index(cleaned.endIndex, offsetBy: -trigger.count, limitedBy: cleaned.startIndex) ?? cleaned.startIndex
                cleaned = String(cleaned[cleaned.startIndex..<endIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return cleaned.isEmpty ? text : cleaned
    }

    private func cleanBasic(_ text: String, languageCode: String) -> String {
        let profile = VoiceLanguageCatalog.profile(for: languageCode)
        var cleaned = stripTriggerWords(text, triggerWords: profile.promptTriggerWords)

        let fillers = profile.promptFillerWords
        for filler in fillers {
            let escaped = NSRegularExpression.escapedPattern(for: filler)
            cleaned = cleaned.replacingOccurrences(
                of: "\\b\(escaped)\\b",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func loadKeyFromEnvFile() -> String? {
        let paths = [
            "\(NSHomeDirectory())/.env",
            "\(NSHomeDirectory())/claude-apps/voice-pilot/.env",
            "\(NSHomeDirectory())/claude-apps/neo-agent/.env",
            "\(NSHomeDirectory())/claude-apps/listo/.env",
            "\(NSHomeDirectory())/claude-apps/listo-local/.env",
            "\(NSHomeDirectory())/claude-apps/connectivity-hub/.env"
        ]
        for path in paths {
            if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                for line in contents.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("ANTHROPIC_API_KEY=") {
                        let value = String(trimmed.dropFirst("ANTHROPIC_API_KEY=".count))
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if !value.isEmpty { return value }
                    }
                }
            }
        }
        return nil
    }
}
