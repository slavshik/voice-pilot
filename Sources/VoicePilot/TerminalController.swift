import Foundation
import AppKit

class TerminalController: ObservableObject {
    @Published var backendKind: BackendKind
    @Published private(set) var targetDescription: String?

    var onError: ((String) -> Void)?

    let tmuxBackend = TmuxBackend()
    let appleScriptBackend = AppleScriptBackend()

    private let defaultsBackendKey = "deliveryBackend"

    init() {
        let saved = UserDefaults.standard.string(forKey: defaultsBackendKey)
            .flatMap { BackendKind(rawValue: $0) }

        if let saved = saved {
            backendKind = saved
        } else if tmuxBackend.isAvailable() {
            backendKind = .tmux
        } else {
            backendKind = .appleScript
        }

        refreshTargetDescription()
    }

    private var activeBackend: DeliveryBackend {
        switch backendKind {
        case .tmux: return tmuxBackend
        case .appleScript: return appleScriptBackend
        }
    }

    func setBackend(_ kind: BackendKind) {
        backendKind = kind
        UserDefaults.standard.set(kind.rawValue, forKey: defaultsBackendKey)
        refreshTargetDescription()
    }

    func pinCurrentTmuxPane() {
        do {
            try tmuxBackend.pinCurrentActivePane()
            refreshTargetDescription()
        } catch {
            report(error)
        }
    }

    func clearTmuxPin() {
        tmuxBackend.clearPin()
        refreshTargetDescription()
    }

    func setTmuxPath(_ path: String?) {
        tmuxBackend.configuredTmuxPath = path?.isEmpty == true ? nil : path
        refreshTargetDescription()
    }

    func refreshTargetDescription() {
        let desc = activeBackend.describeTarget()
        DispatchQueue.main.async { [weak self] in
            self?.targetDescription = desc
        }
    }

    // MARK: - Delivery

    func execute(_ command: TerminalCommand) {
        do {
            try activeBackend.sendCommand(command)
        } catch {
            report(error)
        }
    }

    func pasteAndEnter(_ text: String) {
        do {
            try activeBackend.sendText(text)
            refreshTargetDescription()
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        let msg: String
        if let delivery = error as? DeliveryError {
            msg = delivery.shortMessage
        } else {
            msg = String(describing: error)
        }
        print("[TerminalController] \(msg)")
        DispatchQueue.main.async { [weak self] in
            self?.onError?(msg)
        }
    }
}
