import AppKit
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @AppStorage(Language.storageKey) private var language: Language = .fr
    @State private var draft = ""
    @State private var inputHeight = InputField.lineHeight
    @State private var inputFocusRequest = 0
    @State private var showingSettings = false
    @State private var scrollKeeper = ScrollKeeper()

    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var popupIsKey = true
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            Group {
                if showingSettings {
                    SettingsView(onClose: { showingSettings = false })
                } else {
                    conversation
                    inputBar
                }
            }
            // Clicking anywhere below the header confirms a title being edited.
            .simultaneousGesture(TapGesture().onEnded { if editingTitle { commitTitle() } })
        }
        .frame(width: 380, height: 375)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            popupIsKey = true
            if !showingSettings && !editingTitle { inputFocusRequest += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            // Closing the popup discards an unfinished rename.
            popupIsKey = false
            if editingTitle { cancelTitle() }
            store.persistScroll()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: MenuBarIcon.image)
                .renderingMode(.template)
                .foregroundStyle(.secondary)
            titleView
            Spacer(minLength: 8)
            if !showingSettings {
                iconButton("square.and.pencil", help: language.t("Nouvelle conversation", "New conversation")) {
                    cancelTitle()
                    store.newConversation()
                    draft = ""
                    inputFocusRequest += 1
                }
                .disabled(store.messages.isEmpty && !store.isRunning)
            }
            iconButton(showingSettings ? "xmark" : "gearshape",
                       help: showingSettings ? language.t("Fermer", "Close") : language.t("Réglages", "Settings")) {
                if editingTitle { commitTitle() }
                showingSettings.toggle()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var titleView: some View {
        if showingSettings {
            Text(language.t("Réglages", "Settings"))
                .font(.system(size: 13, weight: .semibold))
        } else if editingTitle {
            TextField("", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .focused($titleFocused)
                .onSubmit(commitTitle)
                .onExitCommand(perform: cancelTitle)
                .onChange(of: titleFocused) {
                    guard !titleFocused, editingTitle else { return }
                    // Focus also drops when the popup closes: tell the two cases apart.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        guard editingTitle else { return }
                        popupIsKey ? commitTitle() : cancelTitle()
                    }
                }
        } else {
            Text(store.displayTitle(language))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .contentShape(Rectangle())
                .onTapGesture(perform: startEditingTitle)
                .help(language.t("Cliquer pour renommer", "Click to rename"))
        }
    }

    private func startEditingTitle() {
        titleDraft = store.displayTitle(language)
        editingTitle = true
        DispatchQueue.main.async { titleFocused = true }
    }

    private func commitTitle() {
        guard editingTitle else { return }
        editingTitle = false
        store.rename(titleDraft)
        inputFocusRequest += 1
    }

    private func cancelTitle() {
        editingTitle = false
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
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.messages) { message in
                            MessageRow(message: message, activity: store.activity, isRunning: store.isRunning)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                    .background(EnclosingScrollViewReader { scrollView in
                        scrollKeeper.onScroll = { offset, atBottom in
                            store.scrollOffset = offset
                            store.scrollAtBottom = atBottom
                        }
                        scrollKeeper.attach(scrollView, restoreTo: store.scrollOffset, atBottom: store.scrollAtBottom)
                    })
                }
            }
            .onChange(of: store.messages) {
                // Follow new text only if the user was already at the bottom.
                if store.scrollAtBottom { proxy.scrollTo("bottom", anchor: .bottom) }
            }
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
            InputField(text: $draft, height: $inputHeight, focusRequest: inputFocusRequest, onSubmit: send)
                .frame(height: inputHeight)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text(language.t("Message…", "Message…"))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                    }
                }
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
