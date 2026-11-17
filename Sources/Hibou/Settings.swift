import Foundation
import ServiceManagement

/// Settings stored in UserDefaults, never in the repo.
enum Settings {
    private static let defaults = UserDefaults.standard

    enum Key {
        static let workingDirectory = "workingDirectory"
        static let claudePath = "claudePath"
        static let mcpServers = "mcpServers"
    }

    /// Folder Claude Code runs in. Defaults to the home folder.
    static var workingDirectory: String {
        get { defaults.string(forKey: Key.workingDirectory) ?? NSHomeDirectory() }
        set { defaults.set(newValue, forKey: Key.workingDirectory) }
    }

    /// Explicit path to the `claude` binary (empty = auto-detect).
    static var claudePathOverride: String {
        get { defaults.string(forKey: Key.claudePath) ?? "" }
        set { defaults.set(newValue, forKey: Key.claudePath) }
    }

    /// Whether a permission is granted. Everything is allowed until the user restricts it.
    static func isAllowed(_ permission: Permission) -> Bool {
        defaults.object(forKey: permission.storageKey) as? Bool ?? true
    }

    static func setAllowed(_ permission: Permission, _ allowed: Bool) {
        defaults.set(allowed, forKey: permission.storageKey)
    }

    /// Permission rule prefixes of the user's MCP servers (e.g. `mcp__github`).
    /// Claude Code has no `mcp__*` wildcard, so each server must be named.
    static var mcpServers: [String] {
        get { defaults.stringArray(forKey: Key.mcpServers) ?? [] }
        set { defaults.set(newValue.sorted(), forKey: Key.mcpServers) }
    }

    /// Arguments that pre-approve the allowed tools: print mode can't ask for permission mid-reply.
    static func permissionArguments() -> [String] {
        var tools: [String] = []
        if isAllowed(.web) { tools += ["WebSearch", "WebFetch"] }
        if isAllowed(.terminal) { tools += ["Bash"] }
        if isAllowed(.connectors) { tools += mcpServers }
        var args = ["--permission-mode", isAllowed(.editFiles) ? "acceptEdits" : "default"]
        if !tools.isEmpty { args += ["--allowedTools", tools.joined(separator: ",")] }
        return args
    }

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Hibou: failed to update launch at login: \(error)")
            }
        }
    }
}

enum Permission: String, CaseIterable, Identifiable {
    case web, editFiles, terminal, connectors

    var id: String { rawValue }
    var storageKey: String { "allow.\(rawValue)" }

    var symbol: String {
        switch self {
        case .web: return "globe"
        case .editFiles: return "doc.badge.gearshape"
        case .terminal: return "terminal"
        case .connectors: return "point.3.connected.trianglepath.dotted"
        }
    }

    func title(_ l: Language) -> String {
        switch self {
        case .web: return l.t("Recherche web", "Web search")
        case .editFiles: return l.t("Modifier des fichiers", "Edit files")
        case .terminal: return l.t("Commandes terminal", "Terminal commands")
        case .connectors: return l.t("Connecteurs", "Connectors")
        }
    }

    func detail(_ l: Language) -> String {
        switch self {
        case .web:
            return l.t("Chercher sur le web et lire des pages.",
                       "Search the web and read pages.")
        case .editFiles:
            return l.t("Créer et modifier des fichiers dans le dossier de travail.",
                       "Create and edit files in the working folder.")
        case .terminal:
            return l.t("Lancer des commandes (git, curl, npm…). Elles peuvent tout faire sur le Mac.",
                       "Run commands (git, curl, npm…). They can do anything on the Mac.")
        case .connectors:
            return l.t("Utiliser les connecteurs MCP (GitHub, Gmail, Agenda…).",
                       "Use MCP connectors (GitHub, Gmail, Calendar…).")
        }
    }
}

/// Keeps `Settings.mcpServers` up to date.
enum MCPDiscovery {
    /// Lists the configured servers with `claude mcp list` (takes a few seconds).
    static func refresh() {
        guard let claude = ClaudeLocator.resolve() else { return }
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: claude)
            p.arguments = ["mcp", "list"]
            p.currentDirectoryURL = URL(fileURLWithPath: Settings.workingDirectory)
            p.environment = ClaudeLocator.environment(claudePath: claude)
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return }
            // Lines look like "claude.ai Gmail: https://… - ✔ Connected".
            let names = (String(data: data, encoding: .utf8) ?? "")
                .split(whereSeparator: \.isNewline)
                .compactMap { line -> String? in
                    guard line.contains(" - "), let colon = line.range(of: ": ") else { return nil }
                    return String(line[..<colon.lowerBound])
                }
            let prefixes = names.map(prefix(forServerNamed:))
            DispatchQueue.main.async { Settings.mcpServers = prefixes }
        }
    }

    /// Adds servers seen in a run's tool names (`mcp__<server>__<tool>`). Only adds:
    /// servers without loaded tools (e.g. not yet authenticated) are missing from that list.
    static func update(fromTools tools: [String]) {
        let seen = Set(tools.compactMap { name -> String? in
            let parts = name.components(separatedBy: "__")
            guard parts.count >= 3, parts[0] == "mcp" else { return nil }
            return "mcp__\(parts[1])"
        })
        let known = Set(Settings.mcpServers)
        if !seen.isSubset(of: known) { Settings.mcpServers = Array(known.union(seen)) }
    }

    /// "claude.ai Gmail" → "mcp__claude_ai_Gmail", as Claude Code names the tools.
    static func prefix(forServerNamed name: String) -> String {
        let normalized = name.unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
                ? String(scalar) : "_"
        }.joined()
        return "mcp__\(normalized)"
    }

    static var displayNames: [String] {
        Settings.mcpServers.map { String($0.dropFirst("mcp__".count)).replacingOccurrences(of: "claude_ai_", with: "") }
    }
}
