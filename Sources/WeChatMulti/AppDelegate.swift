import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let launcher = WeChatLauncher()
    private let preparationPanel = PreparationPanel()
    private var refreshTimer: Timer?
    private var isPreparing = false

    private lazy var appState = AppState(launcher: launcher)
    private let popover = NSPopover()
    private var preferencesController: PreferencesWindowController?
    private var onboardingController: OnboardingWindowController?

    // Busy state uses an SF Symbol so the spinning arrow communicates "working";
    // idle uses the design's monochrome Stack glyph (MenubarIcon).
    private let busySymbolName = "arrow.triangle.2.circlepath"

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupPopover()
        setupAppStateCallbacks()
        startRefreshTimer()
        showFirstLaunchHintIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    private func showFirstLaunchHintIfNeeded() {
        let key = "DidShowFirstLaunchHint"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        // Mark immediately so closing the window mid-flow still counts as shown.
        UserDefaults.standard.set(true, forKey: key)

        onboardingController = OnboardingWindowController { [weak self] in
            self?.onboardingController = nil
            NSApp.setActivationPolicy(.accessory)
        }
        onboardingController?.showAndFocus()
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIdleStatusIcon()

        // Single click handler — left-click and right-click both toggle the
        // popover. No more system NSMenu fallback; every action that used to
        // live there is now in the popover (account rows + footer + per-row
        // context menu) or the Preferences window.
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleStatusBarClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setIdleStatusIcon() {
        guard let button = statusItem.button else { return }
        button.image = MenubarIcon.template(size: 18)
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = "WeChat Multi — click to manage accounts"
    }

    private func setBusyStatusIcon() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: busySymbolName,
                            accessibilityDescription: "Preparing instance")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
    }

    @objc private func handleStatusBarClick(_ sender: NSStatusBarButton) {
        togglePopover()
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.appState.refresh()
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: MenuPanelView(state: appState))
        host.sizingOptions = [.intrinsicContentSize]
        host.view.frame = NSRect(x: 0, y: 0, width: 280, height: 240)
        popover.contentSize = NSSize(width: 280, height: 240)
        popover.contentViewController = host
    }

    private func setupAppStateCallbacks() {
        appState.onLaunchNew = { [weak self] in self?.launchNewInstance() }
        appState.onRefreshStale = { [weak self] in self?.refreshStaleAction() }
        appState.onOpenPreferences = { [weak self] in self?.openPreferences() }
        appState.onCloseMenu = { [weak self] in self?.popover.performClose(nil) }
        appState.onQuitAllInstances = { [weak self] in self?.quitAllAction() }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            appState.refresh()
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Preferences window

    private func openPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController(state: appState)
        }
        preferencesController?.showAndFocus()
    }

    // MARK: - Actions

    private func launchNewInstance() {
        guard !isPreparing else { return }
        isPreparing = true
        setBusyStatusIcon()

        let running = Set(launcher.runningInstances().map(\.slot))
        var previewSlot = 1
        while running.contains(previewSlot) { previewSlot += 1 }
        let needsPrep = launcher.slotNeedsPreparation(slot: previewSlot)
        if needsPrep {
            let name = launcher.slotName(slot: previewSlot) ?? "Slot \(previewSlot)"
            preparationPanel.showAfterDelay(title: "Preparing \(name)…")
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.launcher.launchNextAvailableInstance { stage in
                self.preparationPanel.updateStatus(stage)
            }

            DispatchQueue.main.async {
                self.preparationPanel.hide()
                self.isPreparing = false
                self.setIdleStatusIcon()
                switch result {
                case .launched:
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.appState.refresh()
                    }
                case .sourceMissing:
                    self.showAlert(title: "WeChat Not Found",
                                   message: "Install WeChat in /Applications or choose its location in Preferences.")
                    self.appState.refresh()
                case .failed(let reason):
                    self.showAlert(title: "Could Not Launch a New Instance", message: reason)
                    self.appState.refresh()
                }
            }
        }
    }

    private func quitAllAction() {
        let alert = NSAlert()
        alert.messageText = "Quit all WeChat instances?"
        alert.informativeText = "Every running WeChat window will close. Unsent messages may be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit All")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            launcher.quitAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.appState.refresh()
            }
        }
    }

    private func refreshStaleAction() {
        let stale = launcher.staleClones()
        guard !stale.isEmpty else { return }

        let running = Set(launcher.runningSlotsBlocking(stale))
        let alert = NSAlert()
        alert.messageText = "Refresh \(stale.count) outdated clone\(stale.count == 1 ? "" : "s")?"
        var detail = """
        WeChat updated since these clones were created. Refreshing rebuilds them \
        from the current /Applications/WeChat.app. Your signed-in WeChat session \
        on each clone is preserved — only the app binary is replaced.
        """
        if !running.isEmpty {
            let list = running.sorted().map { "Slot \($0)" }.joined(separator: ", ")
            detail += "\n\nThese clones are currently running and will be quit first: \(list)."
        }
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Refresh")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isPreparing = true
        setBusyStatusIcon()
        preparationPanel.showAfterDelay(title: "Refreshing \(stale.count) clone\(stale.count == 1 ? "" : "s")…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            for slot in running {
                self.preparationPanel.updateStatus("Quitting Slot \(slot)…")
                if let pid = self.launcher.runningInstances().first(where: { $0.slot == slot })?.pid {
                    self.launcher.quitInstance(pid: pid)
                }
            }
            usleep(700_000)

            var failures: [String] = []
            for (index, slot) in stale.enumerated() {
                let name = self.launcher.slotName(slot: slot) ?? "Slot \(slot)"
                self.preparationPanel.updateStatus("Rebuilding \(name) (\(index + 1) of \(stale.count))…")
                switch self.launcher.refreshClone(slot: slot, progress: { stage in
                    self.preparationPanel.updateStatus("\(name): \(stage)")
                }) {
                case .ready: break
                case .sourceMissing:
                    failures.append("Slot \(slot): WeChat.app missing")
                case .failed(let reason):
                    failures.append("Slot \(slot): \(reason)")
                }
            }

            DispatchQueue.main.async {
                self.preparationPanel.hide()
                self.isPreparing = false
                self.setIdleStatusIcon()
                if !failures.isEmpty {
                    self.showAlert(title: "Some Clones Could Not Be Refreshed",
                                   message: failures.joined(separator: "\n"))
                }
                self.appState.refresh()
            }
        }
    }

    // MARK: - Helpers

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
