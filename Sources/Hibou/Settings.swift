import Foundation
import ServiceManagement

/// Settings stored in UserDefaults, never in the repo.
enum Settings {
    private static let defaults = UserDefaults.standard

    enum Key {
        static let workingDirectory = "workingDirectory"
        static let claudePath = "claudePath"
        static let permissionMode = "permissionMode"
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

    /// Passed to `claude --permission-mode`.
    static var permissionMode: PermissionMode {
        get { PermissionMode(rawValue: defaults.string(forKey: Key.permissionMode) ?? "") ?? .default }
        set { defaults.set(newValue.rawValue, forKey: Key.permissionMode) }
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

enum PermissionMode: String, CaseIterable, Identifiable {
    case `default`
    case acceptEdits

    var id: String { rawValue }

    func label(_ language: Language) -> String {
        switch self {
        case .default: return language.t("Lecture seule", "Read-only")
        case .acceptEdits: return language.t("Peut modifier", "Can edit files")
        }
    }
}
