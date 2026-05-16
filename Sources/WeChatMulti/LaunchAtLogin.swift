import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` — the macOS 13+ way to register
/// the app as a login item without a separate helper-app bundle. The system
/// persists the registration across reboots, so we only call `register()` /
/// `unregister()` when the user toggles the setting.
///
/// On first registration macOS may show a "Login Items" approval prompt in
/// System Settings; if the user denies it, `.status` returns `.requiresApproval`
/// — we treat that the same as disabled in the UI and let the user fix it.
enum LaunchAtLogin {

    /// Current effective state. `.requiresApproval` is reported as `false`
    /// (the OS hasn't actually granted launching yet), so the toggle stays
    /// off until the user approves in System Settings.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the OS recognized our registration but is waiting on user
    /// approval in System Settings > General > Login Items. Surface this to
    /// the UI so we can show a one-liner pointing the user to settings.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Register or unregister the app as a login item. Throws if the OS
    /// rejects the call (rare — usually only when running outside /Applications
    /// in a way that LaunchServices can't track).
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            // Idempotent: if already registered, do nothing.
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }
}
