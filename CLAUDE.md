# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Voice Pilot is a native macOS menu bar app (Swift/SwiftUI, `SwiftPM`, macOS 14+) that continuously listens with `SFSpeechRecognizer` and forwards voice input to a terminal running Claude Code CLI. It is packaged as an `LSUIElement` (accessory) agent — no Dock icon, just a status bar item plus a floating panel.

## Build & run

```bash
swift build                      # debug
swift build -c release           # release binary at .build/release/VoicePilot
.build/release/VoicePilot &      # run (first launch prompts for Mic + Accessibility perms)
pkill VoicePilot                 # stop
```

There are no tests, no linter, and no CI configuration — `swift build` is the only verification step. The package (`Package.swift`) is a single executable target; `Resources/` (Info.plist, entitlements, AppIcon.icns) is copied in as a bundle resource.

Keystroke delivery uses `NSAppleScript` → `System Events`, which **requires Accessibility permission**. Revert ⇄ CGEvent was tried and reverted (see `28da7ff`); stick with AppleScript.

## Architecture

`AppDelegate` (Sources/VoicePilot/App.swift) is the composition root. It wires a fixed graph of singletons and routes every recognized utterance through `handleUtterance`:

```
SpeechEngine ──utterance──▶ AppDelegate.handleUtterance
                                    │
    ┌───────────────────────────────┼───────────────────────────────┐
    ▼                               ▼                               ▼
CommandDetector              PromptBuilder (API)             PromptRefiner
 (short phrases)             (multi-turn draft)               (local cleanup)
    │                               │                               │
    └──▶ TerminalController ◀───────┴───────────────────────────────┘
                 │
                 └── AppleScript → frontmost terminal app (paste + Enter)
```

**Utterance routing order** (see `App.swift:60`) — order matters, first match wins:
1. Mute/window control keywords ("mute", "expand", "minimize", …)
2. If `PromptBuilder.isActive`: route to builder ("send"/"cancel"/"start over" or feed input)
3. If `ConfirmationManager.isShowingConfirmation`: handle yes/cancel
4. Builder activation keywords ("build prompt", "prompt mode", …)
5. `CommandDetector` (short ≤4-word commands → `TerminalCommand` enum)
6. Otherwise → `PromptRefiner.refine` → paste to terminal

### Key components

- **`SpeechEngine`** — Owns `AVAudioEngine` + `SFSpeechRecognitionTask` with server-side recognition (`requiresOnDeviceRecognition = false`). Uses a 2s silence timer to chunk utterances, dedupes deliveries within 1.5s, and auto-restarts recognition after `isFinal` or error. The `onUtterance` closure is the sole entry point back into `AppDelegate`.
- **`CommandDetector`** — Pure keyword table → `TerminalCommand` enum (enter/confirm/deny/cancel/scrollUp/scrollDown). Only matches utterances ≤4 words to avoid eating prompts.
- **`TerminalController`** — Two execution paths: single `execute(TerminalCommand)` using AppleScript key codes, and `pasteAndEnter(String)` which saves the clipboard, sets the text, activates a detected terminal process (Terminal/iTerm2/kitty/Alacritty/WezTerm/Ghostty), pastes via ⌘V + Return, then restores the clipboard after 2s. `terminalOnly` toggle switches between "find terminal" and "send to frontmost app".
- **`PromptRefiner`** — Local-only cleanup (strip trigger words like "send"/"go", regex out fillers). The Anthropic API branch is currently dead code — `refine()` returns immediately after `cleanBasic`; everything after the early `return` on line 23 is unreachable. Don't delete it without checking intent.
- **`PromptBuilder`** — Multi-turn refinement mode. Calls the Anthropic Messages API (`api.anthropic.com/v1/messages`) with the full conversation history, using a system prompt that forces "output only the refined prompt". Model is user-selectable (Haiku/Sonnet/Opus). Without an API key it falls back to concatenating user inputs.
- **`ConfirmationManager`** — Two modes: `showBriefly` (2s toast after a send, no countdown) and `show` (original/refined diff with a countdown timer and Tink sound before auto-sending). `showBriefly` is what the current code path uses; the countdown flow is vestigial.
- **`FloatingPanelController` + `MainView`** — One `NSWindow` at `.floating` level, dark, ~300×90 "mini" or ~320×300 "full"/"builder". The green zoom button and voice keywords both call `toggleMini()`. Panel selects between `MiniContent`, `FullContent`, and `BuilderContent` based on `isMini` and `promptBuilder.isActive`.
- **`StatusBarController`** — Menu bar item whose SF Symbol cycles between `mic.circle` / `mic.fill` / `mic.slash` driven by Combine subscriptions on `speechEngine.$isListening` and `$currentTranscript`.
- **`NativeToggle`** — SwiftUI wrappers around `NSSegmentedControl` / `NSButton` for native look inside the floating panel.

### API keys

Both `PromptRefiner` and `PromptBuilder` look up `ANTHROPIC_API_KEY` in this order: `ProcessInfo` env, then `.env` files under `~/claude-apps/{voice-pilot,listo,listo-local,connectivity-hub,neo-agent}/.env` and `~/.env`. No key → graceful fallback (local cleanup or concatenation).

## Conventions & gotchas

- All UI state lives on `@Published` properties; cross-component communication uses Combine or direct references passed in initializers — there is no global event bus.
- Always marshal `@Published` writes and timer callbacks to `DispatchQueue.main` (existing code is consistent about this).
- Recognition restarts itself on `isFinal`/error with a 0.3s delay; if you change that flow, make sure `isListening` gates the restart or you'll spawn duplicate tasks.
- `Info.plist` and `VoicePilot.entitlements` under `Resources/` are required: microphone usage, speech recognition usage, `LSUIElement`, audio-input + apple-events entitlements. Removing any of these breaks permissions on launch.
- The app is distributed unsigned/unsandboxed (`app-sandbox = false`). Keep it that way unless you are also setting up signing.
- The git log uses Conventional Commits (`feat:`, `fix:`). Match that style.
