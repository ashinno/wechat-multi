import Cocoa
import SwiftUI

/// Hosts `WhatsNewView` in a small floating window — opened on first launch
/// after a version bump. Mirrors the Onboarding/About controller pattern.
final class WhatsNewWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void
    private var didFireClose = false

    init(entries: [Changelog.Entry], onClose: @escaping () -> Void) {
        self.onClose = onClose

        let window = WhatsNewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
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

        let host = NSHostingController(rootView: WhatsNewView(entries: entries) { [weak self] in
            self?.close()
        })
        host.view.frame = NSRect(x: 0, y: 0, width: 460, height: 540)
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

private final class WhatsNewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
