import Cocoa
import SwiftUI

/// One row in the popover's account list. Combines a slot (running or just
/// on-disk) into a single user-facing record.
struct Account: Identifiable, Equatable {
    let id: Int                      // slot number; 0 = main /Applications/WeChat.app
    let displayName: String
    let dotColor: Color              // brand color (jade for main, palette for clones)
    let isRunning: Bool
    let pid: Int32?
    let subtitle: String             // "running" or "not running"
}

/// Observable bridge between the WeChatLauncher and the SwiftUI popover/preferences
/// views. AppDelegate owns one of these and refreshes it on a timer + after every
/// user action that might change running state.
final class AppState: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var staleCount: Int = 0
    @Published private(set) var wechatInstalled: Bool = true

    let launcher: WeChatLauncher

    /// Set by AppDelegate so SwiftUI buttons can hand work back to the delegate
    /// (the delegate manages the progress panel + busy-state UI).
    var onLaunchNew: () -> Void = { }
    var onRefreshStale: () -> Void = { }
    var onOpenPreferences: () -> Void = { }
    var onCloseMenu: () -> Void = { }
    var onQuitAllInstances: () -> Void = { }

    var hasRunningInstances: Bool {
        accounts.contains(where: { $0.isRunning })
    }

    init(launcher: WeChatLauncher) {
        self.launcher = launcher
        refresh()
    }

    func refresh() {
        wechatInstalled = launcher.wechatAppPath != nil
        staleCount = launcher.staleClones().count

        let running = launcher.runningInstances()
        let runningSlots = Set(running.map(\.slot))

        var next: [Account] = []

        // Slot 0 — the original /Applications/WeChat.app, only listed when
        // actually running (we don't manage it; we just acknowledge it).
        if let main = running.first(where: { $0.slot == 0 }) {
            next.append(Account(
                id: 0,
                displayName: "Main account",
                dotColor: Color(launcher.slotColor(slot: 0)),
                isRunning: true,
                pid: main.pid,
                subtitle: "running"
            ))
        }

        // All on-disk clone slots, sorted. Each row shows whether it's currently
        // running. Non-running clones can be relaunched with one click (the
        // bundle already exists, so prepareClone returns instantly).
        for slot in launcher.existingCloneSlots() {
            let isRunning = runningSlots.contains(slot)
            let pid = running.first(where: { $0.slot == slot })?.pid
            let name = launcher.slotName(slot: slot) ?? "Slot \(slot)"
            next.append(Account(
                id: slot,
                displayName: name,
                dotColor: Color(launcher.slotColor(slot: slot)),
                isRunning: isRunning,
                pid: pid,
                subtitle: isRunning ? "running" : "not running"
            ))
        }

        if next != accounts {
            accounts = next
        }
    }

    /// Action taken when an account row is clicked. Running → bring its window
    /// to front; not running → launch that specific slot in the background.
    func handleRowClick(_ account: Account) {
        onCloseMenu()
        if account.isRunning, let pid = account.pid {
            launcher.revealInstance(pid: pid)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = self?.launcher.launchSpecificInstance(slot: account.id)
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    func renameAccount(_ account: Account, to newName: String?) {
        _ = launcher.renameClone(slot: account.id, newName: newName)
        refresh()
    }

    func quitAccount(_ account: Account) {
        guard let pid = account.pid else { return }
        launcher.quitInstance(pid: pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }
}
