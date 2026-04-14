import Foundation

enum RefinerModel: String, CaseIterable {
    case free = "openrouter/auto"
    case freeRouter = "openrouter/free"
    case claudeHaiku = "anthropic/claude-haiku-4.5"
    case claudeSonnet = "anthropic/claude-sonnet-4.5"
    case gpt5Mini = "openai/gpt-5-mini"
    case gemini25Flash = "google/gemini-2.5-flash"
    case llama33 = "meta-llama/llama-3.3-70b-instruct"

    var displayName: String {
        switch self {
        case .free: return "Auto (paid, cheapest)"
        case .freeRouter: return "Free router"
        case .claudeHaiku: return "Claude Haiku 4.5"
        case .claudeSonnet: return "Claude Sonnet 4.5"
        case .gpt5Mini: return "GPT-5 mini"
        case .gemini25Flash: return "Gemini 2.5 Flash"
        case .llama33: return "Llama 3.3 70B"
        }
    }
}

class PromptRefiner {
    private let apiKey: String
    var model: RefinerModel = .freeRouter
    var activeLanguageCode = VoiceLanguageCatalog.fallbackLanguageCode

    init() {
        if let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty {
            self.apiKey = key
        } else if let key = Self.loadKeyFromEnvFile() {
            self.apiKey = key
        } else {
            self.apiKey = ""
            print("Warning: No OPENROUTER_API_KEY found. Prompt refinement will pass through raw text.")
        }
    }

    func refine(_ rawSpeech: String, completion: @escaping (_ refined: String, _ source: String) -> Void) {
        let profile = VoiceLanguageCatalog.profile(for: activeLanguageCode)
        let cleaned = stripTriggerWords(rawSpeech, triggerWords: profile.promptTriggerWords)

        guard !apiKey.isEmpty else {
            completion(cleanBasic(cleaned, languageCode: activeLanguageCode), "local")
            return
        }

        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 250,
            "messages": [
                ["role": "system", "content": systemPrompt(for: activeLanguageCode)],
                ["role": "user", "content": cleaned]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(cleanBasic(cleaned, languageCode: activeLanguageCode), "local")
            return
        }

        let modelTag = model.displayName
        let source = "OpenRouter • \(modelTag)"

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://github.com/voice-pilot", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Voice Pilot", forHTTPHeaderField: "X-Title")
        request.httpBody = jsonData
        request.timeoutInterval = 8

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            let fallback = self.cleanBasic(cleaned, languageCode: self.activeLanguageCode)

            if let error = error {
                print("[PromptRefiner] Network error: \(error.localizedDescription)")
                completion(fallback, "local (network error)")
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(fallback, "local (bad response)")
                return
            }
            if let errorInfo = json["error"] as? [String: Any] {
                print("[PromptRefiner] API error: \(errorInfo)")
                completion(fallback, "local (API error)")
                return
            }
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                completion(fallback, "local (no content)")
                return
            }

            let extracted = self.extractPrompt(content)
            if extracted.isEmpty {
                completion(fallback, "local (rejected)")
            } else {
                completion(extracted, source)
            }
        }.resume()
    }

    private func extractPrompt(_ text: String) -> String {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if lower.contains(pattern) { return "" }
        }
        if result.count > text.count * 3 { return "" }
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
        case "ru":
            return """
            Ты конвертер голоса в промт. Вход: грязная расшифровка речи. Выход: чистый промт для CLI.

            ПРАВИЛА:
            1. Верни ТОЛЬКО очищенный промт.
            2. Без вопросов, комментариев и извинений.
            3. Убирай слова-паразиты, исправляй грамматику.
            4. 1-3 предложения максимум, прямо и по делу.
            5. Если ввод неясен — делай лучшее предположение, НЕ проси уточнений.
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
                    if trimmed.hasPrefix("OPENROUTER_API_KEY=") {
                        let value = String(trimmed.dropFirst("OPENROUTER_API_KEY=".count))
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if !value.isEmpty { return value }
                    }
                }
            }
        }
        return nil
    }
}
