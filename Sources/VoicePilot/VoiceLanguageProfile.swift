import Foundation

struct AppVoicePhraseSet {
    let mute: [String]
    let expandExact: [String]
    let expandContains: [String]
    let minimize: [String]
    let builderActivateExact: [String]
    let builderActivateContains: [String]
    let builderSend: [String]
    let builderCancelExact: [String]
    let builderCancelContains: [String]
    let builderReset: [String]
    let confirmationYes: [String]
    let confirmationNo: [String]
}

struct VoiceLanguageProfile {
    let languageCode: String
    let app: AppVoicePhraseSet
    let commandKeywords: [(keywords: [String], command: TerminalCommand)]
    let promptTriggerWords: [String]
    let promptFillerWords: [String]
    let refinerSystemPrompt: String
    let builderSystemPrompt: String
}

struct VoiceTextNormalizer {
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let alnumAndSpace = lowered.replacingOccurrences(
            of: "[^\\p{L}\\p{N}\\s]",
            with: " ",
            options: .regularExpression
        )
        let collapsed = alnumAndSpace.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum VoiceLanguageCatalog {
    static let fallbackLanguageCode = "en"
    static let supportedLanguageCodes: Set<String> = Set(profiles.keys)

    static func resolvedLanguageCode(for languageCode: String) -> String {
        let normalized = normalizeLanguageCode(languageCode)
        if profiles[normalized] != nil {
            return normalized
        }
        return fallbackLanguageCode
    }

    static func profile(for languageCode: String) -> VoiceLanguageProfile {
        let resolved = resolvedLanguageCode(for: languageCode)
        return profiles[resolved] ?? english
    }

    private static func normalizeLanguageCode(_ languageCode: String) -> String {
        let normalized = languageCode
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return String(normalized.split(separator: "-").first ?? "")
    }

    private static let english = VoiceLanguageProfile(
        languageCode: "en",
        app: AppVoicePhraseSet(
            mute: ["mute", "shut up", "stop listening", "pause"],
            expandExact: ["expand", "open", "open up", "bigger", "make it bigger"],
            expandContains: ["expand"],
            minimize: ["minimize", "collapse", "shrink"],
            builderActivateExact: ["draft mode", "builder", "go for it", "prompt"],
            builderActivateContains: ["build prompt", "prompt builder", "prompt mode", "switch to prompt"],
            builderSend: ["send", "done", "ship it", "send it"],
            builderCancelExact: ["cancel", "discard", "nevermind"],
            builderCancelContains: ["voice control", "back to voice", "switch to voice"],
            builderReset: ["start over", "reset"],
            confirmationYes: ["send", "go", "yes"],
            confirmationNo: ["cancel", "no", "abort"]
        ),
        commandKeywords: [
            (["enter", "submit", "return", "press enter"], .enter),
            (["yes", "confirm", "one", "accept", "approve", "yeah"], .confirm),
            (["no", "deny", "reject", "two", "decline", "nah"], .deny),
            (["cancel", "stop", "abort", "kill", "quit", "escape"], .cancel),
            (["scroll up", "page up", "go up"], .scrollUp),
            (["scroll down", "page down", "go down"], .scrollDown),
        ],
        promptTriggerWords: ["send", "send it", "send now", "go", "go now"],
        promptFillerWords: ["um", "uh", "like", "you know", "basically", "actually", "so like", "i mean"],
        refinerSystemPrompt: """
        You are a speech-to-prompt converter. Input: messy voice transcription. Output: clean prompt for a terminal CLI.

        RULES:
        1. Output ONLY the cleaned prompt. Zero other text.
        2. No questions. No commentary. No apologies. No explanations.
        3. No prefixes like "Here's..." or "Refined:". Just the prompt.
        4. Remove filler words.
        5. Fix grammar and make intent clear.
        6. 1-3 sentences max. Be direct.
        7. If input is unclear, make your best guess. NEVER ask for clarification.
        """,
        builderSystemPrompt: """
        You are a prompt builder. The user is dictating a prompt for a terminal CLI via voice.
        Your job: take all their input so far and produce ONE refined, professional prompt.

        RULES:
        1. Output ONLY the refined prompt. Nothing else.
        2. NEVER ask questions, add commentary, or explain yourself.
        3. Incorporate all user feedback and corrections into the prompt.
        4. If the user says to change something, update the prompt accordingly.
        5. Remove filler words, fix grammar, make it precise and actionable.
        6. The prompt should be ready to paste directly into the CLI.
        7. Keep it concise but complete — include all the user's requirements.
        """
    )

    private static let spanish = VoiceLanguageProfile(
        languageCode: "es",
        app: AppVoicePhraseSet(
            mute: ["silencio", "callate", "deja de escuchar", "pausa", "mute"],
            expandExact: ["expandir", "abrir", "mas grande", "hazlo mas grande"],
            expandContains: ["expand"],
            minimize: ["minimizar", "colapsar", "encoger"],
            builderActivateExact: ["modo borrador", "constructor", "prompt"],
            builderActivateContains: ["crear prompt", "modo prompt", "constructor de prompts", "cambiar a prompt"],
            builderSend: ["enviar", "enviarlo", "mandalo", "listo", "hecho"],
            builderCancelExact: ["cancelar", "descartar", "olvidalo"],
            builderCancelContains: ["control de voz", "volver a voz", "cambiar a voz"],
            builderReset: ["empezar de nuevo", "reiniciar"],
            confirmationYes: ["enviar", "si", "confirmar", "vale"],
            confirmationNo: ["cancelar", "no", "abortar"]
        ),
        commandKeywords: [
            (["intro", "enviar", "retorno", "aceptar"], .enter),
            (["si", "confirmar", "aceptar", "vale"], .confirm),
            (["no", "negar", "rechazar"], .deny),
            (["cancelar", "detener", "abortar", "salir", "escape"], .cancel),
            (["desplazar arriba", "subir pagina", "arriba"], .scrollUp),
            (["desplazar abajo", "bajar pagina", "abajo"], .scrollDown),
        ],
        promptTriggerWords: ["enviar", "enviarlo", "mandalo", "enviar ahora"],
        promptFillerWords: ["eh", "este", "pues", "o sea", "como que", "en plan"],
        refinerSystemPrompt: """
        Eres un convertidor de voz a prompt. Entrada: transcripcion de voz desordenada. Salida: prompt limpio para CLI.

        REGLAS:
        1. Devuelve SOLO el prompt limpio.
        2. Sin preguntas, comentarios ni explicaciones.
        3. Quita muletillas y corrige gramatica.
        4. Maximo 1-3 frases, directo y accionable.
        """,
        builderSystemPrompt: """
        Eres un constructor de prompts. El usuario dicta un prompt para Claude Code CLI por voz.
        Toma todas sus entradas y produce UN prompt refinado y profesional.

        REGLAS:
        1. Devuelve SOLO el prompt final.
        2. No hagas preguntas ni agregues comentarios.
        3. Incorpora correcciones y cambios del usuario.
        4. Elimina muletillas y mejora gramatica.
        5. Debe quedar listo para pegar en Claude Code CLI.
        """
    )

    private static let german = VoiceLanguageProfile(
        languageCode: "de",
        app: AppVoicePhraseSet(
            mute: ["stummschalten", "ruhe", "nicht zuhoren", "pause", "mute"],
            expandExact: ["erweitern", "offnen", "grosser", "mach es grosser"],
            expandContains: ["erweiter"],
            minimize: ["minimieren", "zusammenklappen", "verkleinern"],
            builderActivateExact: ["entwurf modus", "builder", "prompt"],
            builderActivateContains: ["prompt erstellen", "prompt modus", "zum prompt wechseln"],
            builderSend: ["senden", "fertig", "abschicken"],
            builderCancelExact: ["abbrechen", "verwerfen", "vergiss es"],
            builderCancelContains: ["sprachsteuerung", "zuruck zur sprachsteuerung", "zu sprachsteuerung wechseln"],
            builderReset: ["von vorne", "zurucksetzen"],
            confirmationYes: ["senden", "ja", "bestatigen", "okay"],
            confirmationNo: ["abbrechen", "nein", "stopp"]
        ),
        commandKeywords: [
            (["eingabe", "senden", "return", "enter"], .enter),
            (["ja", "bestatigen", "okay"], .confirm),
            (["nein", "ablehnen"], .deny),
            (["abbrechen", "stopp", "beenden", "escape"], .cancel),
            (["nach oben scrollen", "seite hoch", "hoch"], .scrollUp),
            (["nach unten scrollen", "seite runter", "runter"], .scrollDown),
        ],
        promptTriggerWords: ["senden", "jetzt senden", "schick es", "abschicken"],
        promptFillerWords: ["ah", "ahm", "ehm", "also", "halt", "sozusagen"],
        refinerSystemPrompt: """
        Du bist ein Sprach-zu-Prompt-Konverter. Eingabe: unordentliche Spracherkennung. Ausgabe: sauberer CLI-Prompt.

        REGELN:
        1. Gib NUR den bereinigten Prompt aus.
        2. Keine Fragen, Kommentare oder Erklarungen.
        3. Entferne Fullworter und verbessere Grammatik.
        4. Maximal 1-3 Satze, direkt und umsetzbar.
        """,
        builderSystemPrompt: """
        Du bist ein Prompt-Builder. Der Nutzer diktiert einen Prompt fur Claude Code CLI per Sprache.
        Nutze alle bisherigen Eingaben und erzeuge EINEN verfeinerten Prompt.

        REGELN:
        1. Gib NUR den finalen Prompt aus.
        2. Keine Fragen oder Kommentare.
        3. Ubernimm Korrekturen und Anderungen des Nutzers.
        4. Entferne Fullworter und verbessere die Grammatik.
        5. Der Prompt muss direkt in Claude Code CLI einfugbar sein.
        """
    )

    private static let french = VoiceLanguageProfile(
        languageCode: "fr",
        app: AppVoicePhraseSet(
            mute: ["silence", "tais toi", "arrete d ecouter", "pause", "muet"],
            expandExact: ["agrandir", "ouvrir", "plus grand", "rends le plus grand"],
            expandContains: ["agrand"],
            minimize: ["minimiser", "reduire", "replier"],
            builderActivateExact: ["mode brouillon", "constructeur", "prompt"],
            builderActivateContains: ["creer un prompt", "mode prompt", "constructeur de prompts", "passer au prompt"],
            builderSend: ["envoyer", "envoie", "termine", "c est bon"],
            builderCancelExact: ["annuler", "ignorer", "laisse tomber"],
            builderCancelContains: ["controle vocal", "retour a la voix", "passer a la voix"],
            builderReset: ["recommencer", "reinitialiser"],
            confirmationYes: ["envoyer", "oui", "confirmer", "d accord"],
            confirmationNo: ["annuler", "non", "abandonner"]
        ),
        commandKeywords: [
            (["entree", "envoyer", "valider", "return"], .enter),
            (["oui", "confirmer", "d accord"], .confirm),
            (["non", "refuser", "rejeter"], .deny),
            (["annuler", "arreter", "abandonner", "echap"], .cancel),
            (["defiler vers le haut", "page precedente", "monter"], .scrollUp),
            (["defiler vers le bas", "page suivante", "descendre"], .scrollDown),
        ],
        promptTriggerWords: ["envoyer", "envoie", "envoie le", "envoi maintenant"],
        promptFillerWords: ["euh", "ben", "du coup", "genre", "en fait"],
        refinerSystemPrompt: """
        Tu es un convertisseur voix-vers-prompt. Entree: transcription vocale brouillonne. Sortie: prompt CLI propre.

        REGLES:
        1. Retourne UNIQUEMENT le prompt nettoye.
        2. Aucune question, aucun commentaire, aucune explication.
        3. Supprime les mots parasites et corrige la grammaire.
        4. 1 a 3 phrases max, directes et actionnables.
        """,
        builderSystemPrompt: """
        Tu es un generateur de prompts. L'utilisateur dicte un prompt pour Claude Code CLI a la voix.
        Utilise tout l'historique pour produire UN prompt final affine.

        REGLES:
        1. Retourne UNIQUEMENT le prompt final.
        2. Aucune question ni commentaire.
        3. Integre les corrections de l'utilisateur.
        4. Supprime les mots parasites et ameliore la grammaire.
        5. Le prompt doit etre pret a coller dans Claude Code CLI.
        """
    )

    private static let polish = VoiceLanguageProfile(
        languageCode: "pl",
        app: AppVoicePhraseSet(
            mute: ["wycisz", "cisza", "przestan sluchac", "pauza", "mute"],
            expandExact: ["rozszerz", "otworz", "wieksze", "zrob to wieksze"],
            expandContains: ["rozszerz"],
            minimize: ["zminimalizuj", "zwin", "zmniejsz"],
            builderActivateExact: ["tryb szkicu", "builder", "prompt"],
            builderActivateContains: ["zbuduj prompt", "tryb promptu", "przelacz na prompt"],
            builderSend: ["wyslij", "wyslij to", "gotowe", "wykonaj"],
            builderCancelExact: ["anuluj", "odrzuc", "niewazne"],
            builderCancelContains: ["sterowanie glosem", "powrot do glosu", "przelacz na glos"],
            builderReset: ["zacznij od nowa", "reset"],
            confirmationYes: ["wyslij", "tak", "potwierdz"],
            confirmationNo: ["anuluj", "nie", "przerwij"]
        ),
        commandKeywords: [
            (["enter", "wyslij", "zatwierdz", "powrot"], .enter),
            (["tak", "potwierdz", "akceptuj"], .confirm),
            (["nie", "odrzuc"], .deny),
            (["anuluj", "przerwij", "stop", "escape"], .cancel),
            (["przewin do gory", "strona w gore", "do gory"], .scrollUp),
            (["przewin w dol", "strona w dol", "w dol"], .scrollDown),
        ],
        promptTriggerWords: ["wyslij", "wyslij teraz", "wyslij to"],
        promptFillerWords: ["yyy", "eee", "jakby", "no wiec", "w sensie"],
        refinerSystemPrompt: """
        Jestes konwerterem mowy na prompt. Wejscie: chaotyczna transkrypcja mowy. Wyjscie: czysty prompt CLI.

        ZASADY:
        1. Zwracaj WYLACZNIE oczyszczony prompt.
        2. Bez pytan, komentarzy i wyjasnien.
        3. Usun wypelniacze i popraw gramatyke.
        4. 1-3 zdania maksymalnie, konkretnie i rzeczowo.
        """,
        builderSystemPrompt: """
        Jestes kreatorem promptow. Uzytkownik dyktuje prompt do Claude Code CLI.
        Wykorzystaj cala dotychczasowa tresc i utworz JEDEN dopracowany prompt.

        ZASADY:
        1. Zwroc WYLACZNIE finalny prompt.
        2. Bez pytan i komentarzy.
        3. Uwzglednij poprawki i zmiany uzytkownika.
        4. Usun wypelniacze i popraw gramatyke.
        5. Prompt ma byc gotowy do wklejenia do Claude Code CLI.
        """
    )

    private static let russian = VoiceLanguageProfile(
        languageCode: "ru",
        app: AppVoicePhraseSet(
            mute: ["мут", "тихо", "выключи микрофон", "перестань слушать", "пауза"],
            expandExact: ["разверни", "открой", "увеличь", "сделай больше"],
            expandContains: ["разверн", "увелич"],
            minimize: ["сверни", "уменьши", "минимизируй"],
            builderActivateExact: ["режим черновика", "билдер", "промпт"],
            builderActivateContains: ["создай промпт", "режим промпта", "переключись на промпт"],
            builderSend: ["отправь", "отправить", "готово", "выполни"],
            builderCancelExact: ["отмена", "отмени", "забудь"],
            builderCancelContains: ["управление голосом", "вернись к голосу", "переключись на голос"],
            builderReset: ["начать заново", "сброс"],
            confirmationYes: ["отправь", "да", "подтверди"],
            confirmationNo: ["отмена", "нет", "прервать"]
        ),
        commandKeywords: [
            (["ввод", "энтер", "отправить", "подтвердить"], .enter),
            (["да", "подтвердить", "принять"], .confirm),
            (["нет", "отклонить"], .deny),
            (["отмена", "стоп", "прервать", "выход", "эскейп"], .cancel),
            (["прокрути вверх", "страница вверх", "вверх"], .scrollUp),
            (["прокрути вниз", "страница вниз", "вниз"], .scrollDown),
        ],
        promptTriggerWords: ["отправь", "отправить", "пошли", "выполни"],
        promptFillerWords: ["ээ", "эм", "ну", "как бы", "типа", "в общем"],
        refinerSystemPrompt: """
        Ты конвертер голоса в промт. Вход: грязная расшифровка речи. Выход: чистый промт для CLI.

        ПРАВИЛА:
        1. Верни ТОЛЬКО очищенный промт.
        2. Без вопросов, комментариев и извинений.
        3. Убирай слова-паразиты, исправляй грамматику.
        4. 1-3 предложения максимум, прямо и по делу.
        5. Если ввод неясен — делай лучшее предположение, НЕ проси уточнений.
        """,
        builderSystemPrompt: """
        Ты конструктор промтов. Пользователь диктует промт для Claude Code CLI голосом.
        Используй все его вводы и создай ОДИН отполированный промт.

        ПРАВИЛА:
        1. Верни ТОЛЬКО финальный промт. Ничего больше.
        2. НЕ задавай вопросы, не комментируй и не объясняй.
        3. Учитывай все исправления и пожелания пользователя.
        4. Убирай слова-паразиты, исправляй грамматику.
        5. Промт должен быть готов к вставке в Claude Code CLI.
        """
    )

    private static let profiles: [String: VoiceLanguageProfile] = [
        english.languageCode: english,
        spanish.languageCode: spanish,
        german.languageCode: german,
        french.languageCode: french,
        polish.languageCode: polish,
        russian.languageCode: russian,
    ]
}
