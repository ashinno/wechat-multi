import Cocoa

/// Small floating panel shown while a clone is being prepared. The initial copy
/// + re-sign can take 3–10 seconds on slow disks, which feels like a hang
/// without feedback. The panel surfaces a moving progress bar and the current
/// stage label.
///
/// Shows on a delay so that fast operations (sub-second) don't flash a window
/// at the user.
final class PreparationPanel {
    private let panel: NSPanel
    private let progressIndicator: NSProgressIndicator
    private let statusLabel: NSTextField
    private let titleLabel: NSTextField
    private var pendingShow: DispatchWorkItem?
    private var isVisible = false

    init() {
        let size = NSSize(width: 380, height: 130)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.center()

        let container = NSView(frame: NSRect(origin: .zero, size: size))

        titleLabel = NSTextField(labelWithString: "Preparing instance…")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = true
        progressIndicator.usesThreadedAnimation = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(progressIndicator)

        statusLabel = NSTextField(labelWithString: "Starting…")
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(statusLabel)

        let pad: CGFloat = 20
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: pad),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),

            progressIndicator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            progressIndicator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            progressIndicator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),

            statusLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad)
        ])

        panel.contentView = container
    }

    /// Show the panel after a short delay. If `hide()` is called before the
    /// delay elapses, the panel never appears — this keeps fast operations
    /// from flashing a window.
    func showAfterDelay(title: String, delay: TimeInterval = 0.4) {
        pendingShow?.cancel()
        titleLabel.stringValue = title
        statusLabel.stringValue = "Starting…"

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.progressIndicator.startAnimation(nil)
            self.panel.makeKeyAndOrderFront(nil)
            self.isVisible = true
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Update the secondary status line. Safe to call from any queue.
    func updateStatus(_ stage: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.stringValue = stage
        }
    }

    func hide() {
        pendingShow?.cancel()
        pendingShow = nil
        guard isVisible else { return }
        isVisible = false
        progressIndicator.stopAnimation(nil)
        panel.orderOut(nil)
    }
}
