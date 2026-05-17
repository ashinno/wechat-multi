import Cocoa
import SwiftUI

/// Hosts `AboutView` in a small standalone window — opened from the popover's
/// "About WeChat Multi" footer item.
///
/// Uses a transparent titlebar + `fullSizeContentView` so the jade gradient
/// reaches the top of the window. Custom `NSWindow` subclass so the window
/// can become key without a visible title (otherwise keyboard input is
/// swallowed and the system shake animation on close looks dead).
final class AboutWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void
    private var didFireClose = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose

        let window = AboutWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()

        super.init(window: window)
        window.delegate = self

        let host = NSHostingController(rootView: AboutView())
        host.view.frame = NSRect(x: 0, y: 0, width: 360, height: 560)
        window.contentView = host.view
        contentViewController = host
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func showAndFocus() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard !didFireClose else { return }
        didFireClose = true
        onClose()
    }
}

private final class AboutWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
