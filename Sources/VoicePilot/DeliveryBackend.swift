import Foundation

enum BackendKind: String {
    case tmux
    case appleScript

    var displayName: String {
        switch self {
        case .tmux: return "tmux"
        case .appleScript: return "AppleScript"
        }
    }
}

enum DeliveryError: Error, CustomStringConvertible {
    case notAvailable(String)
    case targetNotFound
    case processFailed(String)

    var description: String {
        switch self {
        case .notAvailable(let reason): return reason
        case .targetNotFound: return "tmux: no pane"
        case .processFailed(let reason): return reason
        }
    }

    var shortMessage: String {
        switch self {
        case .notAvailable(let reason): return reason
        case .targetNotFound: return "tmux: no pane"
        case .processFailed: return "tmux: send failed"
        }
    }
}

protocol DeliveryBackend: AnyObject {
    var kind: BackendKind { get }
    func isAvailable() -> Bool
    func describeTarget() -> String?
    func sendText(_ text: String) throws
    func sendCommand(_ command: TerminalCommand) throws
}
