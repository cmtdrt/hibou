import AppKit
import SwiftUI

struct SettingsView: View {
    var onClose: () -> Void

    @AppStorage(Language.storageKey) private var language: Language = .fr
    @State private var workingDirectory = Settings.workingDirectory
    @State private var claudePath = Settings.claudePathOverride
    @State private var launchAtLogin = Settings.launchAtLogin
    @State private var showingPermissions = false

    var body: some View {
        VStack(spacing: 0) {
            if showingPermissions {
                PermissionsView(onBack: { showingPermissions = false })
            } else {
                mainPage
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

    private var mainPage: some View {
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

                section(language.t("Permissions", "Permissions")) {
                    Button { showingPermissions = true } label: {
                        HStack {
                            Text(permissionsSummary)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
    }

    private var permissionsSummary: String {
        let allowed = Permission.allCases.filter(Settings.isAllowed).count
        let total = Permission.allCases.count
        if allowed == total { return language.t("Tout est autorisé", "Everything allowed") }
        return language.t("\(allowed) sur \(total) autorisées", "\(allowed) of \(total) allowed")
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

/// Sub-page listing the permissions Hibou pre-approves.
private struct PermissionsView: View {
    var onBack: () -> Void

    @AppStorage(Language.storageKey) private var language: Language = .fr
    @State private var allowed: [Permission: Bool] =
        Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, Settings.isAllowed($0)) })

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text(language.t("Permissions", "Permissions")).font(.system(size: 12, weight: .semibold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                ForEach(Permission.allCases) { permission in
                    Toggle(isOn: binding(for: permission)) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: permission.symbol)
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(permission.title(language))
                                Text(detail(for: permission))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                Text(language.t("S'applique dès le prochain message.", "Applies from the next message."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detail(for permission: Permission) -> String {
        let base = permission.detail(language)
        guard permission == .connectors else { return base }
        let names = MCPDiscovery.displayNames
        if names.isEmpty { return base }
        return base + "\n" + language.t("Détectés : ", "Found: ") + names.joined(separator: ", ")
    }

    private func binding(for permission: Permission) -> Binding<Bool> {
        Binding(
            get: { allowed[permission] ?? true },
            set: { value in
                allowed[permission] = value
                Settings.setAllowed(permission, value)
            }
        )
    }
}
