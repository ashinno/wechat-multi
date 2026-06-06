import Cocoa
import SwiftUI
import Combine
import WeChatMultiCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let launcher = WeChatLauncher()
    private let preparationPanel = PreparationPanel()
    private var refreshTimer: Timer?
    private var isPreparing = false
    private var cancellables = Set<AnyCancellable>()
    private var keyMonitor: Any?

    private lazy var appState = AppState(launcher: launcher)
    private let popover = NSPopover()
    private var preferencesController: PreferencesWindowController?
    private var onboardingController: OnboardingWindowController?
    private var aboutController: AboutWindowController?
    private var whatsNewController: WhatsNewWindowController?

    // Busy state uses an SF Symbol so the spinning arrow communicates "working";
    // idle uses the design's monochrome Stack glyph (MenubarIcon).
    private let busySymbolName = "arrow.triangle.2.circlepath"

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupPopover()
        setupAppStateCallbacks()
        startRefreshTimer()
        observeAccountsForIconBadge()
        showFirstLaunchHintIfNeeded()
        showWhatsNewIfNeeded()
    }

    /// Watches the accounts list so the menubar icon picks up the running
    /// badge / drops it without waiting on the 5s refresh tick.
    private func observeAccountsForIconBadge() {
        appState.$accounts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshStatusIcon() }
            .store(in: &cancellables)
    }

    private func refreshStatusIcon() {
        guard !isPreparing else { return }   // busy state has priority
        setIdleStatusIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    private func showFirstLaunchHintIfNeeded() {
        let key = DefaultsKey.didShowOnboarding
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        // Mark immediately so closing the window mid-flow still counts as shown.
        UserDefaults.standard.set(true, forKey: key)

        onboardingController = OnboardingWindowController { [weak self] in
            self?.onboardingController = nil
            NSApp.setActivationPolicy(.accessory)
        }
        onboardingController?.showAndFocus()
    }

    /// On the first launch after a version bump, surface the changelog window
    /// so users don't have to visit GitHub to know what changed. Skipped on
    /// the first-ever launch (onboarding handles that) and on downgrades.
    private func showWhatsNewIfNeeded() {
        let key = DefaultsKey.lastSeenVersion
        let defaults = UserDefaults.standard
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        defer { defaults.set(current, forKey: key) }

        guard let lastSeen = defaults.string(forKey: key) else {
            // First-ever launch — onboarding covers introduction, skip changelog.
            return
        }
        guard SemVer.isNewer(current, than: lastSeen) else { return }
        guard defaults.bool(forKey: DefaultsKey.didShowOnboarding) else {
            // User hasn't completed onboarding yet — don't pile a second
            // window on top. Onboarding will set the flag; we'll catch this
            // case on the next launch.
            return
        }

        // Pick entries strictly newer than lastSeen, capped at 3 so the panel
        // doesn't become a wall of text after multiple skipped versions.
        let entries = Changelog.entriesNewer(than: lastSeen, limit: 3)
        guard !entries.isEmpty else { return }

        // Show after a beat so the menubar/Combine wiring above finishes first
        // and the popover icon is positioned correctly under the new window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.whatsNewController = WhatsNewWindowController(
                entries: Array(entries)
            ) { [weak self] in
                self?.whatsNewController = nil
                if self?.preferencesController == nil
                    && self?.onboardingController == nil
                    && self?.aboutController == nil {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
            self.whatsNewController?.showAndFocus()
        }
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
        let hasRunning = appState.hasRunningInstances
        button.image = hasRunning
            ? MenubarIcon.withRunningBadge(size: 18)
            : MenubarIcon.template(size: 18)
        button.imagePosition = .imageOnly
        button.title = ""
        if hasRunning {
            let n = appState.accounts.filter(\.isRunning).count
            button.toolTip = n == 1
                ? "WeChat Multi — 1 instance running"
                : "WeChat Multi — \(n) instances running"
        } else {
            button.toolTip = "WeChat Multi — click to manage accounts"
        }
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
        // Account list refresh — cheap, every 5s
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.appState.refresh()
        }
        // Initial health check 2s after launch so it doesn't compete with
        // first-paint, and then every 5 minutes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.appState.runHealthCheck()
        }
        // Take a throttled settings snapshot off the main thread shortly after
        // launch (deduped + rate-limited inside the launcher).
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.launcher.captureSettingsSnapshotIfDue()
        }
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.appState.runHealthCheck()
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
        appState.onRepairUnhealthy = { [weak self] in self?.repairUnhealthyAction() }
        appState.onOpenPreferences = { [weak self] in self?.openPreferences() }
        appState.onOpenAbout = { [weak self] in self?.openAbout() }
        appState.onCloseMenu = { [weak self] in self?.popover.performClose(nil) }
        appState.onQuitAllInstances = { [weak self] in self?.quitAllAction() }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            appState.refresh()
            appState.focusFirst()
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - NSPopoverDelegate (keyboard monitor lifecycle)

    func popoverDidShow(_ notification: Notification) {
        // Local monitor swallows ↑/↓/Return/Delete while the popover is open
        // so AppState can drive selection. Any unhandled keys pass through.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        appState.clearFocus()
    }

    /// Returns true when the event was consumed (so NSEvent monitor returns
    /// nil and the system doesn't beep). ↑/↓ move selection; Return triggers
    /// the focused row; Delete (forward or backward) deletes the row if it's
    /// an eligible stopped clone.
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Ignore modifier-laden shortcuts so ⌘N etc. still work normally.
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty == false {
            return false
        }
        switch event.keyCode {
        case 125:               // ↓
            appState.focusNext()
            return true
        case 126:               // ↑
            appState.focusPrevious()
            return true
        case 36, 76:            // Return, Enter
            appState.activateFocused()
            return true
        case 51, 117:           // Delete (backspace), Forward delete
            appState.deleteFocused()
            return true
        default:
            return false
        }
    }

    // MARK: - Preferences window

    private func openPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController(state: appState)
        }
        preferencesController?.showAndFocus()
    }

    private func openAbout() {
        if aboutController == nil {
            aboutController = AboutWindowController { [weak self] in
                self?.aboutController = nil
                // Only drop activation policy if no other window is up
                if self?.preferencesController == nil && self?.onboardingController == nil {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
        aboutController?.showAndFocus()
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
        let prepStart = Date()

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
                case .launched(let slot):
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.appState.refresh()
                    }
                    // If prep took long enough that the user might have alt-
                    // tabbed away, fire a banner so they know it finished.
                    let duration = Date().timeIntervalSince(prepStart)
                    if duration > 1.5 {
                        let name = self.launcher.slotName(slot: slot) ?? "Slot \(slot)"
                        AppNotifications.send(
                            title: "WeChat Multi",
                            body: "\(name) is ready",
                            identifier: "ready-\(slot)-\(Int(Date().timeIntervalSince1970))"
                        )
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
                self.appState.runHealthCheck()
            }
        }
    }

    private func repairUnhealthyAction() {
        let issues = appState.healthIssues
        let slots = Array(Set(issues.map(\.slot))).sorted()
        guard !slots.isEmpty else { return }

        let running = Set(launcher.runningSlotsBlocking(slots))
        let alert = NSAlert()
        alert.messageText = "Repair \(slots.count) clone\(slots.count == 1 ? "" : "s")?"
        var detail = """
        Each unhealthy clone will be rebuilt from /Applications/WeChat.app. \
        Signed-in WeChat sessions are preserved (the sandbox container is \
        keyed by bundle ID, which we restore exactly).

        Issues detected:
        """
        for issue in issues.prefix(6) {
            let name = launcher.slotName(slot: issue.slot) ?? "Slot \(issue.slot)"
            detail += "\n • \(name) — \(issue.summary)"
        }
        if issues.count > 6 { detail += "\n • …and \(issues.count - 6) more" }
        if !running.isEmpty {
            let list = running.sorted().map { "Slot \($0)" }.joined(separator: ", ")
            detail += "\n\nThese are running and will be quit first: \(list)."
        }
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Repair")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isPreparing = true
        setBusyStatusIcon()
        preparationPanel.showAfterDelay(title: "Repairing \(slots.count) clone\(slots.count == 1 ? "" : "s")…")

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
            for (index, slot) in slots.enumerated() {
                let name = self.launcher.slotName(slot: slot) ?? "Slot \(slot)"
                self.preparationPanel.updateStatus("Rebuilding \(name) (\(index + 1) of \(slots.count))…")
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
                    self.showAlert(title: "Some Clones Could Not Be Repaired",
                                   message: failures.joined(separator: "\n"))
                }
                self.appState.refresh()
                self.appState.runHealthCheck()
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
