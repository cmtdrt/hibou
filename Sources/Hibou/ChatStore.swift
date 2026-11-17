import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, assistant, error }

    var id = UUID()
    var role: Role
    var text: String
}

/// Current conversation state, persisted to
/// ~/Library/Application Support/Hibou/conversation.json so it survives restarts.
@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isRunning = false
    /// Tool Claude is currently using (e.g. "Read"), shown while waiting.
    @Published private(set) var activity: String?

    private var sessionID: String?
    /// Folder the session was created in: Claude sessions are tied to their folder.
    private var sessionDirectory: String?
    private let runner = ClaudeRunner()
    private var pendingID: UUID?

    private struct Saved: Codable {
        var sessionID: String?
        var sessionDirectory: String?
        var messages: [ChatMessage]
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hibou", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversation.json")
    }

    init() { load() }

    // MARK: - Actions

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }

        messages.append(ChatMessage(role: .user, text: text))
        let reply = ChatMessage(role: .assistant, text: "")
        messages.append(reply)
        pendingID = reply.id
        isRunning = true
        activity = nil
        save()

        // The previous session can't be resumed from a different working folder.
        if sessionDirectory != Settings.workingDirectory { sessionID = nil }
        sessionDirectory = Settings.workingDirectory

        do {
            try runner.run(
                prompt: text,
                sessionID: sessionID,
                onEvent: { [weak self] event in
                    MainActor.assumeIsolated { self?.handle(event) }
                },
                onExit: { [weak self] status, stderr in
                    MainActor.assumeIsolated { self?.finish(status: status, stderr: stderr) }
                }
            )
        } catch {
            replacePending(with: ChatMessage(role: .error, text: error.localizedDescription))
            isRunning = false
            save()
        }
    }

    func stop() {
        runner.stop()
    }

    func newConversation() {
        if runner.isRunning { runner.stop() }
        messages = []
        sessionID = nil
        sessionDirectory = nil
        pendingID = nil
        isRunning = false
        activity = nil
        save()
    }

    // MARK: - CLI events

    private func handle(_ event: ClaudeRunner.Event) {
        switch event {
        case .textBlockStart:
            activity = nil
            updatePending { text in
                if !text.isEmpty && !text.hasSuffix("\n\n") { text += "\n\n" }
            }
        case .textDelta(let delta):
            updatePending { $0 += delta }
        case .toolUse(let name):
            activity = name
        case .result(let text, let isError, let id):
            if let id { sessionID = id }
            if isError {
                replacePending(with: ChatMessage(role: .error, text: text.isEmpty ? tr("Erreur de Claude Code.", "Claude Code error.") : text))
            } else {
                updatePending { current in
                    if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { current = text }
                }
            }
        }
    }

    private func finish(status: Int32, stderr: String) {
        if let id = pendingID, let msg = messages.first(where: { $0.id == id }) {
            if msg.role == .assistant && msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let text = status == 15 || status == 2
                    ? tr("Interrompu.", "Stopped.")
                    : (detail.isEmpty ? tr("Claude Code s'est arrêté sans réponse (code \(status)).", "Claude Code exited without replying (code \(status)).") : detail)
                replacePending(with: ChatMessage(role: .error, text: text))
            }
        }
        pendingID = nil
        isRunning = false
        activity = nil
        save()
    }

    private func updatePending(_ change: (inout String) -> Void) {
        guard let id = pendingID, let i = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[i].text)
    }

    private func replacePending(with message: ChatMessage) {
        guard let id = pendingID, let i = messages.firstIndex(where: { $0.id == id }) else { return }
        var m = message
        m.id = id
        messages[i] = m
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        sessionID = saved.sessionID
        sessionDirectory = saved.sessionDirectory
        // An empty reply means the app quit mid-generation: drop it.
        messages = saved.messages.filter { !($0.role == .assistant && $0.text.isEmpty) }
    }

    private func save() {
        let saved = Saved(sessionID: sessionID, sessionDirectory: sessionDirectory, messages: messages)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
