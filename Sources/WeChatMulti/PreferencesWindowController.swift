import Cocoa
import SwiftUI

/// Wraps `PreferencesView` in an `NSWindowController` so it shows up as a real
/// standalone window (with title bar, close button, separate from the popover).
final class PreferencesWindowController: NSWindowController {
    convenience init(state: AppState) {
        let hosting = NSHostingController(rootView: PreferencesView(state: state))
        let window = NSWindow(contentViewController: hosting)
        window.title = "WeChat Multi — Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 380))
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func showAndFocus() {
        // LSUIElement apps must temporarily upgrade activation policy so a
        // window can take focus; we drop back to .accessory when it closes.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }
}
