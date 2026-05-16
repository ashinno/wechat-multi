import Cocoa
import SwiftUI

/// Standalone window hosting the first-run onboarding flow. Fires the
/// `onClose` callback regardless of how the window dismisses (Get Started,
/// Skip, or the system close button) so the AppDelegate can drop activation
/// policy back to `.accessory` exactly once.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void
    private var didFireClose = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose

        let window = OnboardingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
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

        let host = NSHostingController(rootView: OnboardingView { [weak self] in
            self?.close()
        })
        host.view.frame = NSRect(x: 0, y: 0, width: 600, height: 480)
        window.contentView = host.view
        contentViewController = host
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func showAndFocus() {
        // LSUIElement apps need a temporary activation policy upgrade so a
        // window can take focus. We drop back when the window closes.
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

/// NSWindow subclass that accepts keyboard input even though the window has
/// no title bar visible. `canBecomeKey` defaults to false for fullSizeContent
/// windows that hide their title, which would swallow our keyboard shortcuts
/// (Return / Escape / arrows) used to advance through the onboarding.
private final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
