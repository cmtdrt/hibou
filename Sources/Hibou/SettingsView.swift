import AppKit
import SwiftUI

struct SettingsView: View {
    var onClose: () -> Void

    @AppStorage(Language.storageKey) private var language: Language = .fr
    @State private var workingDirectory = Settings.workingDirectory
    @State private var claudePath = Settings.claudePathOverride
    @State private var permissionMode = Settings.permissionMode
    @State private var launchAtLogin = Settings.launchAtLogin

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section(language.t("Langue", "Language")) {
                        Picker("", selection: $language) {
                            ForEach(Language.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    section(language.t("Dossier de travail", "Working folder"),
                            hint: language.t("Claude Code est lancé dans ce dossier.",
                                             "Claude Code runs in this folder.")) {
                        HStack {
                            Text((workingDirectory as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(language.t("Choisir…", "Choose…"), action: chooseFolder)
                        }
                    }

                    section(language.t("Permissions", "Permissions"),
                            hint: language.t("S'applique dès le prochain message.",
                                             "Applies from the next message.")) {
                        Picker("", selection: $permissionMode) {
                            ForEach(PermissionMode.allCases) { Text($0.label(language)).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .onChange(of: permissionMode) { Settings.permissionMode = permissionMode }
                    }

                    section(language.t("Commande claude", "claude command"),
                            hint: language.t("Laisse vide pour la détection automatique.",
                                             "Leave empty to detect it automatically.")) {
                        TextField(ClaudeLocator.resolve() ?? language.t("introuvable — indique le chemin",
                                                                         "not found — enter its path"),
                                  text: $claudePath)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: claudePath) { Settings.claudePathOverride = claudePath }
                    }

                    Toggle(language.t("Lancer Hibou au démarrage", "Launch Hibou at login"), isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) {
                            Settings.launchAtLogin = launchAtLogin
                            launchAtLogin = Settings.launchAtLogin
                        }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().opacity(0.5)

            HStack {
                Button(language.t("Quitter Hibou", "Quit Hibou")) { NSApp.terminate(nil) }
                Spacer()
                Button("OK", action: onClose).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func section<Content: View>(_ title: String, hint: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content()
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workingDirectory)
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
            Settings.workingDirectory = url.path
        }
    }
}
