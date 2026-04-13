import Foundation

final class TmuxBackend: DeliveryBackend {
    let kind: BackendKind = .tmux

    private let defaultsTmuxPathKey = "tmuxPath"
    private let defaultsPinnedTargetKey = "tmuxPinnedTarget"
    private let bufferName = "vpilot"

    private var cachedPaneId: String?
    private var cachedTargetDisplay: String?
    private var cacheTimestamp: Date = .distantPast
    private let cacheTTL: TimeInterval = 2.0

    private lazy var tmuxPath: String? = resolveTmuxPath()

    // MARK: - DeliveryBackend

    func isAvailable() -> Bool {
        tmuxPath != nil
    }

    func describeTarget() -> String? {
        guard isAvailable() else { return nil }
        if let cached = cachedTargetDisplay,
           Date().timeIntervalSince(cacheTimestamp) < cacheTTL {
            return cached
        }
        return try? resolveTarget().display
    }

    func sendText(_ text: String) throws {
        let target = try resolveTarget()
        // Bracketed paste — Claude CLI treats the whole block as a paste.
        try runTmux(args: ["load-buffer", "-b", bufferName, "-"], stdin: text)
        try runTmux(args: ["paste-buffer", "-b", bufferName, "-d", "-p", "-t", target.paneId])
        try runTmux(args: ["send-keys", "-t", target.paneId, "Enter"])
    }

    func sendCommand(_ command: TerminalCommand) throws {
        let target = try resolveTarget()
        switch command {
        case .enter:
            try runTmux(args: ["send-keys", "-t", target.paneId, "Enter"])
        case .confirm:
            try runTmux(args: ["send-keys", "-t", target.paneId, "-l", "y"])
            try runTmux(args: ["send-keys", "-t", target.paneId, "Enter"])
        case .deny:
            try runTmux(args: ["send-keys", "-t", target.paneId, "-l", "n"])
            try runTmux(args: ["send-keys", "-t", target.paneId, "Enter"])
        case .cancel:
            try runTmux(args: ["send-keys", "-t", target.paneId, "C-c"])
        case .scrollUp, .scrollDown:
            // Copy-mode hijacks the pane; Claude CLI TUI redraws poorly. Skip.
            throw DeliveryError.notAvailable("scroll unavailable in tmux")
        }
    }

    // MARK: - Configuration

    var pinnedTarget: String? {
        get { UserDefaults.standard.string(forKey: defaultsPinnedTargetKey) }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: defaultsPinnedTargetKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsPinnedTargetKey)
            }
            invalidateCache()
        }
    }

    var configuredTmuxPath: String? {
        get { UserDefaults.standard.string(forKey: defaultsTmuxPathKey) }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: defaultsTmuxPathKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsTmuxPathKey)
            }
            tmuxPath = resolveTmuxPath()
            invalidateCache()
        }
    }

    func pinCurrentActivePane() throws {
        let target = try scanForTarget(allowPinned: false)
        pinnedTarget = target.display
    }

    func clearPin() {
        pinnedTarget = nil
    }

    func invalidateCache() {
        cachedPaneId = nil
        cachedTargetDisplay = nil
        cacheTimestamp = .distantPast
    }

    // MARK: - Target resolution

    struct TmuxTarget {
        let paneId: String        // stable id, e.g. "%7"
        let display: String       // "session:window.pane"
    }

    private func resolveTarget() throws -> TmuxTarget {
        if let paneId = cachedPaneId,
           let display = cachedTargetDisplay,
           Date().timeIntervalSince(cacheTimestamp) < cacheTTL {
            return TmuxTarget(paneId: paneId, display: display)
        }
        let target = try scanForTarget(allowPinned: true)
        cachedPaneId = target.paneId
        cachedTargetDisplay = target.display
        cacheTimestamp = Date()
        return target
    }

    private func scanForTarget(allowPinned: Bool) throws -> TmuxTarget {
        // 1. Try pinned target from UserDefaults.
        if allowPinned, let pinned = pinnedTarget,
           let paneId = verifyTarget(pinned) {
            return TmuxTarget(paneId: paneId, display: pinned)
        }

        // 2. Scan all panes, rank attached+active, prefer claude-looking commands.
        let format = "#{pane_id}\t#{session_attached}\t#{window_active}\t#{pane_active}\t#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_current_command}"
        let output: String
        do {
            output = try runTmuxCapturing(args: ["list-panes", "-a", "-F", format])
        } catch {
            throw DeliveryError.targetNotFound
        }

        struct Candidate {
            let paneId: String
            let display: String
            let score: Int
        }

        var best: Candidate?
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 8 else { continue }
            let paneId = fields[0]
            let attached = Int(fields[1]) ?? 0
            let winActive = Int(fields[2]) ?? 0
            let paneActive = Int(fields[3]) ?? 0
            let session = fields[4]
            let window = fields[5]
            let pane = fields[6]
            let cmd = fields[7].lowercased()

            var score = 0
            if attached > 0 { score += 100 }
            if winActive > 0 { score += 20 }
            if paneActive > 0 { score += 10 }
            if cmd.contains("claude") || cmd == "node" { score += 5 }

            let candidate = Candidate(
                paneId: paneId,
                display: "\(session):\(window).\(pane)",
                score: score
            )
            if best == nil || candidate.score > best!.score {
                best = candidate
            }
        }

        guard let winner = best else {
            throw DeliveryError.targetNotFound
        }
        return TmuxTarget(paneId: winner.paneId, display: winner.display)
    }

    private func verifyTarget(_ target: String) -> String? {
        guard let output = try? runTmuxCapturing(
            args: ["display-message", "-p", "-t", target, "#{pane_id}"]
        ) else {
            return nil
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Process execution

    private func resolveTmuxPath() -> String? {
        if let configured = configuredTmuxPath,
           FileManager.default.isExecutableFile(atPath: configured) {
            return configured
        }
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    @discardableResult
    private func runTmux(args: [String], stdin: String? = nil) throws -> String {
        try runTmuxCapturing(args: args, stdin: stdin)
    }

    @discardableResult
    private func runTmuxCapturing(args: [String], stdin: String? = nil) throws -> String {
        guard let path = tmuxPath else {
            throw DeliveryError.notAvailable("tmux not found")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let inPipe: Pipe?
        if stdin != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            inPipe = pipe
        } else {
            inPipe = nil
        }

        do {
            try process.run()
        } catch {
            throw DeliveryError.processFailed("failed to launch tmux: \(error)")
        }

        if let stdin = stdin, let inPipe = inPipe {
            if let data = stdin.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(data)
            }
            try? inPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let stderr = String(data: errData, encoding: .utf8) ?? ""
            invalidateCache()
            if stderr.contains("no server running") || stderr.contains("can't find") || stderr.contains("can't find pane") {
                throw DeliveryError.targetNotFound
            }
            throw DeliveryError.processFailed(stderr.isEmpty ? "tmux exit \(process.terminationStatus)" : stderr)
        }

        return String(data: outData, encoding: .utf8) ?? ""
    }
}
