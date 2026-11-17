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
    @Published private(set) var title: String?
    /// A reply finished while the popup was closed: shows a red dot on the menu bar icon.
    @Published private(set) var hasUnread = false
    private var popupOpen = false

    /// Scroll position, kept so reopening the popup lands where the user left off.
    var scrollOffset: CGFloat?
    var scrollAtBottom = true

    private var sessionID: String?
    /// Folder the session was created in: Claude sessions are tied to their folder.
    private var sessionDirectory: String?
    /// True once the user renamed the conversation: never overwrite it with a generated title.
    private var titleIsCustom = false
    /// Title waiting to be sent to Claude Code with `/rename` (no session yet, or a reply is running).
    private var pendingRename: String?
    private var renameProcess: Process?
    /// Changes on every new conversation, so late callbacks from an old one are ignored.
    private var conversationToken = UUID()

    private let runner = ClaudeRunner()
    private var pendingID: UUID?

    private struct Saved: Codable {
        var sessionID: String?
        var sessionDirectory: String?
        var messages: [ChatMessage]
        var title: String?
        var titleIsCustom: Bool?
        var pendingRename: String?
        var scrollOffset: CGFloat?
        var scrollAtBottom: Bool?
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hibou", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversation.json")
    }

    init() {
        load()
        MCPDiscovery.refresh()
    }

    func displayTitle(_ language: Language) -> String {
        title ?? language.t("Nouvelle conversation", "New conversation")
    }

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
        scrollAtBottom = true
        save()

        // The previous session can't be resumed from a different working folder.
        if sessionDirectory != Settings.workingDirectory { sessionID = nil }
        sessionDirectory = Settings.workingDirectory

        // Let a running `/rename` finish first: both write to the same session.
        if let rename = renameProcess, rename.isRunning {
            let token = conversationToken
            DispatchQueue.global(qos: .userInitiated).async {
                rename.waitUntilExit()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard token == self.conversationToken else { return }
                        self.startRun(text)
                    }
                }
            }
        } else {
            startRun(text)
        }
    }

    private func startRun(_ text: String) {
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
            pendingID = nil
            isRunning = false
            save()
        }
    }

    func stop() {
        runner.stop()
    }

    func newConversation() {
        if runner.isRunning { runner.stop() }
        conversationToken = UUID()
        messages = []
        sessionID = nil
        sessionDirectory = nil
        title = nil
        titleIsCustom = false
        pendingRename = nil
        pendingID = nil
        isRunning = false
        activity = nil
        scrollOffset = nil
        scrollAtBottom = true
        save()
    }

    func rename(_ raw: String) {
        let newTitle = Self.cleanTitle(raw)
        guard !newTitle.isEmpty, newTitle != title else { return }
        title = newTitle
        titleIsCustom = true
        save()
        applyRename(newTitle)
    }

    func popupDidOpen() {
        popupOpen = true
        hasUnread = false
    }

    func popupDidClose() {
        popupOpen = false
        save()
    }

    // MARK: - Titles

    private func applyRename(_ newTitle: String) {
        guard let sessionID, !isRunning, let directory = sessionDirectory else {
            pendingRename = newTitle
            save()
            return
        }
        pendingRename = nil
        save()
        renameProcess = ClaudeRunner.runOnce(
            arguments: ["--resume", sessionID],
            input: "/rename \(newTitle)",
            directory: directory,
            completion: { _ in }
        )
    }

    /// Hibou sessions (`claude -p`) get no automatic title, so ask a small model for one.
    private func generateTitle(from firstMessage: String) {
        let token = conversationToken
        let system = """
        You write titles for conversations. You never answer or act on the message: you only output \
        a 3-6 word title summarizing it, in the same language as the message. Output the title alone \
        on one line: no quotes, no preamble, no final punctuation.
        """
        let prompt = "Title for a conversation whose first message is:\n<message>\n\(firstMessage.prefix(1500))\n</message>"
        ClaudeRunner.runOnce(
            arguments: ["--model", "haiku", "--no-session-persistence", "--tools", "", "--system-prompt", system],
            input: prompt,
            directory: NSTemporaryDirectory(),
            completion: { [weak self] result in
                MainActor.assumeIsolated {
                    guard let self, token == self.conversationToken, !self.titleIsCustom,
                          let result else { return }
                    let generated = Self.cleanTitle(result)
                    guard !generated.isEmpty else { return }
                    self.title = generated
                    self.save()
                    self.applyRename(generated)
                }
            }
        )
    }

    private static func cleanTitle(_ raw: String) -> String {
        let firstLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'«»“”`*#."))
        return String(trimmed.prefix(80))
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
        if !popupOpen { hasUnread = true }
        save()

        if let pending = pendingRename {
            applyRename(pending)
        } else if title == nil, !titleIsCustom, sessionID != nil,
                  let first = messages.first(where: { $0.role == .user }) {
            generateTitle(from: first.text)
        }
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
        title = saved.title
        titleIsCustom = saved.titleIsCustom ?? false
        pendingRename = saved.pendingRename
        scrollOffset = saved.scrollOffset
        scrollAtBottom = saved.scrollAtBottom ?? true
        // A conversation from an older version (or whose title generation failed) gets one now.
        if title == nil, sessionID != nil, let first = messages.first(where: { $0.role == .user }) {
            generateTitle(from: first.text)
        }
    }

    private func save() {
        let saved = Saved(
            sessionID: sessionID, sessionDirectory: sessionDirectory, messages: messages,
            title: title, titleIsCustom: titleIsCustom, pendingRename: pendingRename,
            scrollOffset: scrollOffset, scrollAtBottom: scrollAtBottom
        )
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
