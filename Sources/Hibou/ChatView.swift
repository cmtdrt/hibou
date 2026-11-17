import AppKit
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @AppStorage(Language.storageKey) private var language: Language = .fr
    @State private var draft = ""
    @State private var showingSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if showingSettings {
                SettingsView(onClose: { showingSettings = false })
            } else {
                conversation
                inputBar
            }
        }
        .frame(width: 380, height: 375)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Focus the input every time the popup opens.
            if !showingSettings { inputFocused = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: MenuBarIcon.image)
                .renderingMode(.template)
                .foregroundStyle(.secondary)
            Text("Hibou")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if !showingSettings {
                iconButton("square.and.pencil", help: language.t("Nouvelle conversation", "New conversation")) {
                    store.newConversation()
                    draft = ""
                    inputFocused = true
                }
                .disabled(store.messages.isEmpty && !store.isRunning)
            }
            iconButton(showingSettings ? "xmark" : "gearshape",
                       help: showingSettings ? language.t("Fermer", "Close") : language.t("Réglages", "Settings")) {
                showingSettings.toggle()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.messages.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(store.messages) { message in
                            MessageRow(message: message, activity: store.activity, isRunning: store.isRunning)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                }
            }
            .onChange(of: store.messages) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(nsImage: MenuBarIcon.image)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 44)
                .foregroundStyle(.quaternary)
            Text(language.t("Pose ta question à Claude", "Ask Claude anything"))
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(language.t("Message…", "Message…"), text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit(send)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.primary.opacity(0.08))
                )

            if store.isRunning {
                roundButton("stop.fill", help: language.t("Arrêter", "Stop")) { store.stop() }
            } else {
                roundButton("arrow.up", help: language.t("Envoyer (Entrée)", "Send (Return)"), action: send)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
    }

    private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 2)
        .help(help)
    }

    private func send() {
        guard !store.isRunning else { return }
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        store.send(text)
    }
}

// MARK: - Message row

private struct MessageRow: View {
    let message: ChatMessage
    let activity: String?
    let isRunning: Bool
    @AppStorage(Language.storageKey) private var language: Language = .fr

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill(Color.accentColor.opacity(0.15))
                    )
            }
        case .assistant:
            if message.text.isEmpty {
                thinking
            } else {
                Text(markdown(message.text))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .error:
            Label(message.text, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private var thinking: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(activity.map { language.t("Utilise \($0)…", "Using \($0)…") } ?? language.t("Réfléchit…", "Thinking…"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
