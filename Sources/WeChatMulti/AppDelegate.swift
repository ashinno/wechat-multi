import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let launcher = WeChatLauncher()
    private var refreshTimer: Timer?
    private var isPreparing = false

    private let idleSymbolName = "bubble.left.and.bubble.right.fill"
    private let busySymbolName = "arrow.triangle.2.circlepath"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        startRefreshTimer()
        showFirstLaunchHintIfNeeded()
    }

    private func showFirstLaunchHintIfNeeded() {
        let key = "DidShowFirstLaunchHint"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        // Brief activation so the user notices the new app, then drop back to
        // accessory mode. The alert points at the menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "WeChat Multi is running"
        alert.informativeText = """
        Look for “WC” in the right side of your menu bar (next to the clock and \
        Control Center). Click it, then choose “Launch New Instance” to open a \
        second WeChat.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it")
        alert.runModal()

        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    // MARK: - Status bar setup

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusImage(named: idleSymbolName)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        rebuildMenu()
    }

    private func setStatusImage(named symbolName: String) {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: symbolName,
                            accessibilityDescription: "WeChat Multi")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        // The actual instance count is filled in by rebuildMenu(); we set a
        // placeholder here so the icon never appears empty.
        if button.title.isEmpty {
            button.title = " WC"
        }
        button.toolTip = "WeChat Multi — click to launch additional accounts"
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    // MARK: - Menu delegate

    // menuNeedsUpdate is Apple's recommended hook for dynamic menus — it's called
    // before display and lets us populate items without the empty-flash you get
    // from mutating inside menuWillOpen.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    // MARK: - Menu

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let installed = launcher.wechatAppPath != nil
        let instances = launcher.runningInstances()

        // Update the menu bar title with the current instance count so the
        // icon stays informative without opening the menu.
        if let button = statusItem.button, !isPreparing {
            button.title = instances.isEmpty ? " WC" : " WC \(instances.count)"
        }

        // ── Header ──────────────────────────────────────────────────────────
        let headerTitle: String
        if isPreparing {
            headerTitle = "Preparing new instance…"
        } else if !installed {
            headerTitle = "WeChat not found"
        } else if instances.isEmpty {
            headerTitle = "No WeChat instances running"
        } else if instances.count == 1 {
            headerTitle = "1 WeChat instance running"
        } else {
            headerTitle = "\(instances.count) WeChat instances running"
        }
        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(NSMenuItem.separator())

        // ── Stale clone warning ─────────────────────────────────────────────
        // If /Applications/WeChat.app has been updated, the clones still hold
        // the old binary and will probably misbehave on next launch.
        let stale = installed ? launcher.staleClones() : []
        if !stale.isEmpty {
            let warning = NSMenuItem(title: "⚠️ \(stale.count) clone\(stale.count == 1 ? "" : "s") out of date",
                                     action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)

            let refreshItem = NSMenuItem(title: "Refresh Outdated Clones…",
                                         action: #selector(refreshStaleAction),
                                         keyEquivalent: "")
            refreshItem.target = self
            refreshItem.isEnabled = !isPreparing
            menu.addItem(refreshItem)

            menu.addItem(NSMenuItem.separator())
        }

        // ── Launch new ──────────────────────────────────────────────────────
        let launchItem = NSMenuItem(title: "Launch New Instance",
                                    action: #selector(launchNewInstance),
                                    keyEquivalent: "n")
        launchItem.target = self
        launchItem.isEnabled = installed && !isPreparing
        menu.addItem(launchItem)

        // ── Running instances ───────────────────────────────────────────────
        if !instances.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let runningHeader = NSMenuItem(title: "Running", action: nil, keyEquivalent: "")
            runningHeader.isEnabled = false
            menu.addItem(runningHeader)

            for info in instances {
                let label = displayLabel(for: info)
                let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                let sub = NSMenu()

                let revealItem = NSMenuItem(title: "Bring to Front",
                                            action: #selector(revealInstanceAction(_:)),
                                            keyEquivalent: "")
                revealItem.target = self
                revealItem.representedObject = info.pid
                sub.addItem(revealItem)

                let quitItem = NSMenuItem(title: "Quit This Instance",
                                          action: #selector(quitInstanceAction(_:)),
                                          keyEquivalent: "")
                quitItem.target = self
                quitItem.representedObject = info.pid
                sub.addItem(quitItem)

                // Renaming only makes sense for clones, not the original.
                if info.slot > 0 {
                    sub.addItem(NSMenuItem.separator())
                    let renameItem = NSMenuItem(title: "Rename…",
                                                action: #selector(renameSlotAction(_:)),
                                                keyEquivalent: "")
                    renameItem.target = self
                    renameItem.representedObject = info.slot
                    sub.addItem(renameItem)
                }

                if !info.startTime.isEmpty {
                    sub.addItem(NSMenuItem.separator())
                    let startItem = NSMenuItem(title: "Started: \(info.startTime)",
                                               action: nil, keyEquivalent: "")
                    startItem.isEnabled = false
                    sub.addItem(startItem)
                }

                item.submenu = sub
                menu.addItem(item)
            }

            let quitAllItem = NSMenuItem(title: "Quit All Instances",
                                         action: #selector(quitAllAction),
                                         keyEquivalent: "k")
            quitAllItem.target = self
            menu.addItem(quitAllItem)
        }

        // ── Settings ────────────────────────────────────────────────────────
        menu.addItem(NSMenuItem.separator())

        let chooseItem = NSMenuItem(title: "Choose WeChat.app Location…",
                                    action: #selector(chooseWeChatLocation),
                                    keyEquivalent: "")
        chooseItem.target = self
        menu.addItem(chooseItem)

        if let path = launcher.wechatAppPath {
            let pathItem = NSMenuItem(title: "  ↳ \(path)", action: nil, keyEquivalent: "")
            pathItem.isEnabled = false
            menu.addItem(pathItem)
        }

        let revealClonesItem = NSMenuItem(title: "Open Clones Folder",
                                          action: #selector(revealClonesFolder),
                                          keyEquivalent: "")
        revealClonesItem.target = self
        menu.addItem(revealClonesItem)

        let existingClones = launcher.existingCloneSlots()
        if !existingClones.isEmpty {
            let resetItem = NSMenuItem(title: "Reset All Clones (\(existingClones.count))…",
                                       action: #selector(resetClonesAction),
                                       keyEquivalent: "")
            resetItem.target = self
            menu.addItem(resetItem)
        }

        // ── About / Quit ────────────────────────────────────────────────────
        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About WeChat Multi",
                                   action: #selector(showAbout),
                                   keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitAppItem = NSMenuItem(title: "Quit WeChat Multi",
                                     action: #selector(NSApplication.terminate(_:)),
                                     keyEquivalent: "q")
        menu.addItem(quitAppItem)
    }

    // MARK: - Actions

    @objc private func launchNewInstance() {
        guard !isPreparing else { return }
        isPreparing = true
        setStatusImage(named: busySymbolName)
        rebuildMenu()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.launcher.launchNextAvailableInstance()

            DispatchQueue.main.async {
                self.isPreparing = false
                self.setStatusImage(named: self.idleSymbolName)
                switch result {
                case .launched:
                    // Give the OS a beat to register the new process before refreshing.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.rebuildMenu()
                    }
                case .sourceMissing:
                    self.showAlert(title: "WeChat Not Found",
                                   message: "Install WeChat in /Applications or choose its location from the menu.")
                    self.rebuildMenu()
                case .failed(let reason):
                    self.showAlert(title: "Could Not Launch a New Instance", message: reason)
                    self.rebuildMenu()
                }
            }
        }
    }

    @objc private func quitInstanceAction(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int32 else { return }
        launcher.quitInstance(pid: pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.rebuildMenu()
        }
    }

    @objc private func revealInstanceAction(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int32 else { return }
        launcher.revealInstance(pid: pid)
    }

    @objc private func quitAllAction() {
        let alert = NSAlert()
        alert.messageText = "Quit all WeChat instances?"
        alert.informativeText = "Every running WeChat window will close. Unsent messages may be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit All")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            launcher.quitAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.rebuildMenu()
            }
        }
    }

    @objc private func chooseWeChatLocation() {
        let panel = NSOpenPanel()
        panel.title = "Select WeChat.app"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            let hasMain = FileManager.default.fileExists(atPath: "\(path)/Contents/MacOS/WeChat") ||
                          FileManager.default.fileExists(atPath: "\(path)/Contents/MacOS/微信")
            if hasMain {
                launcher.setCustomPath(path)
                rebuildMenu()
            } else {
                showAlert(title: "Not a WeChat App",
                          message: "The selected bundle does not contain a WeChat executable.")
            }
        }
    }

    @objc private func revealClonesFolder() {
        let root = launcher.cloneRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    @objc private func resetClonesAction() {
        let alert = NSAlert()
        alert.messageText = "Reset all WeChat clones?"
        alert.informativeText = """
        This deletes every cloned WeChat bundle under ~/Applications/WeChat Multi/.
        Each instance's local cache is removed; signed-in sessions stored in macOS \
        sandbox containers may also be reset on next launch. Clones are recreated \
        automatically the next time you launch a new instance.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            // Stop any running clones first so files can be removed cleanly.
            launcher.quitAll()
            usleep(500_000)
            do {
                try launcher.resetAllClones()
            } catch {
                showAlert(title: "Reset Failed", message: error.localizedDescription)
            }
            rebuildMenu()
        }
    }

    @objc private func renameSlotAction(_ sender: NSMenuItem) {
        guard let slot = sender.representedObject as? Int, slot > 0 else { return }

        let currentName = launcher.slotName(slot: slot)
        let placeholder = "WeChat \(slot)"

        let alert = NSAlert()
        alert.messageText = "Rename Slot \(slot)"
        alert.informativeText = "Give this instance a memorable name like \"Work\" or \"Personal\". Cmd+Tab and the Dock will pick up the new name the next time you launch it."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if currentName != nil {
            alert.addButton(withTitle: "Reset")
        }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = placeholder
        field.stringValue = currentName ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // Save
            let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let err = launcher.renameClone(slot: slot, newName: trimmed.isEmpty ? nil : trimmed) {
                showAlert(title: "Rename Failed", message: err)
            }
        case .alertThirdButtonReturn: // Reset to default
            if let err = launcher.renameClone(slot: slot, newName: nil) {
                showAlert(title: "Rename Failed", message: err)
            }
        default:
            return
        }
        rebuildMenu()
    }

    @objc private func refreshStaleAction() {
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
        setStatusImage(named: busySymbolName)
        rebuildMenu()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Quit anything that needs to be replaced.
            for slot in running {
                if let pid = self.launcher.runningInstances().first(where: { $0.slot == slot })?.pid {
                    self.launcher.quitInstance(pid: pid)
                }
            }
            usleep(700_000)

            var failures: [String] = []
            for slot in stale {
                switch self.launcher.refreshClone(slot: slot) {
                case .ready: break
                case .sourceMissing:
                    failures.append("Slot \(slot): WeChat.app missing")
                case .failed(let reason):
                    failures.append("Slot \(slot): \(reason)")
                }
            }

            DispatchQueue.main.async {
                self.isPreparing = false
                self.setStatusImage(named: self.idleSymbolName)
                if !failures.isEmpty {
                    self.showAlert(title: "Some Clones Could Not Be Refreshed",
                                   message: failures.joined(separator: "\n"))
                }
                self.rebuildMenu()
            }
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "WeChat Multi"
        alert.informativeText = """
        Run multiple WeChat accounts side by side on macOS.

        Each new instance is a copy of /Applications/WeChat.app with a unique \
        bundle ID, kept under ~/Applications/WeChat Multi/. Because every clone \
        has its own sandbox container, WeChat's built-in singleton check is \
        bypassed and each instance has its own login state.

        Version 1.1.1
        """
        alert.alertStyle = .informational
        // Force the app-icon for the About panel. NSAlert normally inherits
        // NSApp.applicationIconImage, but LSUIElement apps can fall back to the
        // generic app icon on first launch before LaunchServices has cached it.
        if let icon = NSImage(named: "AppIcon")
            ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath) as NSImage? {
            alert.icon = icon
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func displayLabel(for info: WeChatLauncher.InstanceInfo) -> String {
        if info.slot == 0 {
            return "Main account — PID \(info.pid)"
        }
        if info.slot < 0 {
            return "Clone — PID \(info.pid)"
        }
        if let name = launcher.slotName(slot: info.slot) {
            return "\(name) (Slot \(info.slot)) — PID \(info.pid)"
        }
        return "Slot \(info.slot) — PID \(info.pid)"
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
