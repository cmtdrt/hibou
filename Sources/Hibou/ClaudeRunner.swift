import Foundation

/// Runs `claude -p` in the background and turns its `stream-json` output into events.
final class ClaudeRunner {
    enum Event {
        /// A new text block starts (used to separate consecutive messages).
        case textBlockStart
        case textDelta(String)
        /// Claude is using a tool (Read, Bash, WebSearch…).
        case toolUse(String)
        case result(text: String, isError: Bool, sessionID: String?)
    }

    private var process: Process?
    private var buffer = Data()

    var isRunning: Bool { process?.isRunning ?? false }

    func run(
        prompt: String,
        sessionID: String?,
        onEvent: @escaping (Event) -> Void,
        onExit: @escaping (_ status: Int32, _ stderr: String) -> Void
    ) throws {
        guard let claude = ClaudeLocator.resolve() else {
            throw RunnerError.claudeNotFound
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: claude)
        var args = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-mode", Settings.permissionMode.rawValue,
        ]
        if let sessionID { args += ["--resume", sessionID] }
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: Settings.workingDirectory)
        p.environment = ClaudeLocator.environment(claudePath: claude)

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr

        buffer = Data()
        var stderrData = Data()
        let stderrLock = NSLock()

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else { return }
            DispatchQueue.main.async { self.consume(chunk, onEvent: onEvent) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            stderrLock.lock(); stderrData.append(chunk); stderrLock.unlock()
        }

        p.terminationHandler = { [weak self] proc in
            // Drain the pipes before finishing.
            let rest = stdout.fileHandleForReading.readDataToEndOfFile()
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            stderrLock.lock()
            stderrData.append(stderr.fileHandleForReading.readDataToEndOfFile())
            let errText = String(data: stderrData, encoding: .utf8) ?? ""
            stderrLock.unlock()
            DispatchQueue.main.async {
                guard let self else { return }
                if !rest.isEmpty { self.consume(rest, onEvent: onEvent) }
                self.consume(Data([0x0A]), onEvent: onEvent) // flush the last line
                self.process = nil
                onExit(proc.terminationStatus, errText)
            }
        }

        try p.run()
        process = p

        // Send the prompt via stdin so text starting with "-" isn't parsed as a flag.
        stdin.fileHandleForWriting.write(Data(prompt.utf8))
        try? stdin.fileHandleForWriting.close()
    }

    func stop() {
        process?.terminate()
    }

    // MARK: - Parsing

    private func consume(_ chunk: Data, onEvent: (Event) -> Void) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if !line.isEmpty { parse(Data(line), onEvent: onEvent) }
        }
    }

    private func parse(_ line: Data, onEvent: (Event) -> Void) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = obj["type"] as? String else { return }

        // Ignore subagent output: only the main conversation is shown.
        if let parent = obj["parent_tool_use_id"], !(parent is NSNull) { return }

        switch type {
        case "stream_event":
            guard let event = obj["event"] as? [String: Any],
                  let eventType = event["type"] as? String else { return }
            if eventType == "content_block_start",
               let block = event["content_block"] as? [String: Any],
               let blockType = block["type"] as? String {
                if blockType == "text" { onEvent(.textBlockStart) }
                if blockType == "tool_use", let name = block["name"] as? String { onEvent(.toolUse(name)) }
            } else if eventType == "content_block_delta",
                      let delta = event["delta"] as? [String: Any],
                      delta["type"] as? String == "text_delta",
                      let text = delta["text"] as? String {
                onEvent(.textDelta(text))
            }
        case "result":
            onEvent(.result(
                text: obj["result"] as? String ?? "",
                isError: obj["is_error"] as? Bool ?? false,
                sessionID: obj["session_id"] as? String
            ))
        default:
            break
        }
    }

    enum RunnerError: LocalizedError {
        case claudeNotFound
        var errorDescription: String? {
            tr("Impossible de trouver la commande `claude`. Installe Claude Code, ou indique son chemin dans les réglages.",
               "Can't find the `claude` command. Install Claude Code, or set its path in Settings.")
        }
    }
}

/// Finds the `claude` binary. Apps launched from Finder don't get the terminal's PATH,
/// so check the usual locations, then ask the user's login shell.
enum ClaudeLocator {
    private static var cached: String?

    static func resolve() -> String? {
        let override = Settings.claudePathOverride.trimmingCharacters(in: .whitespaces)
        if !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return FileManager.default.isExecutableFile(atPath: expanded) ? expanded : nil
        }
        if let cached, FileManager.default.isExecutableFile(atPath: cached) { return cached }

        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            cached = found
            return found
        }
        if let found = fromLoginShell() {
            cached = found
            return found
        }
        return nil
    }

    private static func fromLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-l", "-c", "command -v claude"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// The app's environment with an extended PATH so Claude finds its tools (git, node…).
    static func environment(claudePath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = [
            (claudePath as NSString).deletingLastPathComponent,
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        let current = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        env["PATH"] = (extra + current).filter { seen.insert($0).inserted }.joined(separator: ":")
        return env
    }
}
