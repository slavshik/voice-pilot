import Foundation
import AppKit

final class AppleScriptBackend: DeliveryBackend {
    let kind: BackendKind = .appleScript

    private let terminalCandidates = [
        "Terminal", "iTerm2", "kitty", "Alacritty", "WezTerm", "Ghostty"
    ]

    func isAvailable() -> Bool { true }

    func describeTarget() -> String? {
        detectTerminalApp()
    }

    func sendText(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let termApp = detectTerminalApp()
        let activateBlock: String
        if let termApp = termApp {
            // Use System Events to activate non-scriptable apps (Alacritty, Ghostty, kitty).
            activateBlock = """
            tell application "System Events"
                set frontmost of (first process whose name is "\(termApp)") to true
            end tell
            delay 0.3
            """
        } else {
            activateBlock = ""
        }

        let script = """
        \(activateBlock)
        tell application "System Events"
            keystroke "v" using command down
        end tell
        delay 0.3
        tell application "System Events"
            key code 36
        end tell
        """

        runAppleScript(script)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    func sendCommand(_ command: TerminalCommand) throws {
        switch command {
        case .enter:
            sendKey("return")
        case .confirm:
            sendKeystroke("y")
            usleep(100_000)
            sendKey("return")
        case .deny:
            sendKeystroke("n")
            usleep(100_000)
            sendKey("return")
        case .cancel:
            sendKey("c", using: "control down")
        case .scrollUp:
            sendKey("upArrow", using: "shift down")
        case .scrollDown:
            sendKey("downArrow", using: "shift down")
        }
    }

    private func detectTerminalApp() -> String? {
        for app in terminalCandidates {
            let script = """
            tell application "System Events"
                exists (process "\(app)")
            end tell
            """
            if let result = runAppleScriptReturning(script), result.booleanValue {
                return app
            }
        }
        return nil
    }

    private func sendKeystroke(_ text: String) {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        runAppleScript("""
        tell application "System Events"
            keystroke "\(escaped)"
        end tell
        """)
    }

    private func sendKey(_ key: String, using modifier: String? = nil) {
        let script: String
        if let modifier = modifier {
            script = """
            tell application "System Events"
                key code \(keyCode(key)) using {\(modifier)}
            end tell
            """
        } else {
            script = """
            tell application "System Events"
                key code \(keyCode(key))
            end tell
            """
        }
        runAppleScript(script)
    }

    private func keyCode(_ name: String) -> Int {
        switch name {
        case "return": return 36
        case "escape": return 53
        case "c": return 8
        case "v": return 9
        case "upArrow": return 126
        case "downArrow": return 125
        default: return 0
        }
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            print("[AppleScriptBackend] error: \(error)")
        }
        return result
    }

    private func runAppleScriptReturning(_ source: String) -> NSAppleEventDescriptor? {
        runAppleScript(source)
    }
}
