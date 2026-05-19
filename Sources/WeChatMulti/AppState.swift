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
    @Published private(set) var healthIssues: [WeChatLauncher.HealthIssue] = []
    @Published private(set) var wechatInstalled: Bool = true
    /// Keyboard-focused slot ID, or nil when nothing is focused. Set when the
    /// popover opens and updated by ↑/↓ keys.
    @Published var focusedSlotID: Int? = nil

    let launcher: WeChatLauncher

    /// Set by AppDelegate so SwiftUI buttons can hand work back to the delegate
    /// (the delegate manages the progress panel + busy-state UI).
    var onLaunchNew: () -> Void = { }
    var onRefreshStale: () -> Void = { }
    var onRepairUnhealthy: () -> Void = { }
    var onOpenPreferences: () -> Void = { }
    var onOpenAbout: () -> Void = { }
    var onCloseMenu: () -> Void = { }
    var onQuitAllInstances: () -> Void = { }
    /// Bridge from the keyboard monitor (AppDelegate) back to MenuPanelView's
    /// delete prompt — MenuPanelView sets this so the alert renders correctly
    /// with the popover dismissal sequence it already handles for mouse.
    var onRequestDelete: (Account) -> Void = { _ in }

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

        var unordered: [Account] = []

        // Slot 0 — the original /Applications/WeChat.app, only listed when
        // actually running (we don't manage it; we just acknowledge it).
        if let main = running.first(where: { $0.slot == 0 }) {
            unordered.append(Account(
                id: 0,
                displayName: "Main account",
                dotColor: Color(launcher.slotColor(slot: 0)),
                isRunning: true,
                pid: main.pid,
                subtitle: "running"
            ))
        }

        // All on-disk clone slots. Each row shows whether it's currently running.
        for slot in launcher.existingCloneSlots() {
            let isRunning = runningSlots.contains(slot)
            let pid = running.first(where: { $0.slot == slot })?.pid
            let name = launcher.slotName(slot: slot) ?? "Slot \(slot)"
            unordered.append(Account(
                id: slot,
                displayName: name,
                dotColor: Color(launcher.slotColor(slot: slot)),
                isRunning: isRunning,
                pid: pid,
                subtitle: isRunning ? "running" : "not running"
            ))
        }

        // Apply the user's saved display order. Slots present in the order
        // come first (in that order); anything new is appended at the end.
        let savedOrder = launcher.slotDisplayOrder()
        let bySlot = Dictionary(uniqueKeysWithValues: unordered.map { ($0.id, $0) })
        var seen = Set<Int>()
        var next: [Account] = []
        for slotID in savedOrder {
            if let acc = bySlot[slotID] {
                next.append(acc)
                seen.insert(slotID)
            }
        }
        for acc in unordered where !seen.contains(acc.id) {
            next.append(acc)
        }

        if next != accounts {
            accounts = next
        }
    }

    /// Reorders the user-defined display order: place `slot` immediately
    /// before `targetSlot` (or at the end if `targetSlot` is nil). Slot
    /// numbers don't change — they remain tied to their sandbox container.
    func moveAccount(_ slot: Int, before targetSlot: Int?) {
        guard slot != targetSlot else { return }
        // Make sure the current display order is materialized in defaults,
        // not just implicit ("everything in numerical order"). Otherwise the
        // first move would re-order all entries that were never persisted.
        var existing = launcher.slotDisplayOrder()
        for acc in accounts where !existing.contains(acc.id) {
            existing.append(acc.id)
        }
        launcher.setSlotDisplayOrder(existing)
        launcher.moveSlot(slot, before: targetSlot)
        refresh()
    }

    // MARK: - Keyboard focus

    /// Set focus to the first row, or clear it if the list is empty.
    func focusFirst() {
        focusedSlotID = accounts.first?.id
    }

    func clearFocus() {
        focusedSlotID = nil
    }

    func focusNext() {
        guard !accounts.isEmpty else { return }
        if let current = focusedSlotID,
           let idx = accounts.firstIndex(where: { $0.id == current }) {
            focusedSlotID = accounts[min(idx + 1, accounts.count - 1)].id
        } else {
            focusFirst()
        }
    }

    func focusPrevious() {
        guard !accounts.isEmpty else { return }
        if let current = focusedSlotID,
           let idx = accounts.firstIndex(where: { $0.id == current }) {
            focusedSlotID = accounts[max(idx - 1, 0)].id
        } else {
            focusedSlotID = accounts.last?.id
        }
    }

    /// Trigger the focused row's primary action (bring-to-front if running,
    /// otherwise launch). No-op if nothing is focused.
    func activateFocused() {
        guard let id = focusedSlotID,
              let account = accounts.first(where: { $0.id == id }) else { return }
        handleRowClick(account)
    }

    /// Trigger delete on the focused row, but only if it's a stopped clone
    /// (slot > 0, not running). Silently no-ops otherwise so accidental key
    /// presses don't surface confusing errors.
    func deleteFocused() {
        guard let id = focusedSlotID,
              let account = accounts.first(where: { $0.id == id }),
              !account.isRunning, account.id > 0 else { return }
        onRequestDelete(account)
    }

    /// Kick off a health scan on a background queue. Updates `healthIssues`
    /// on main. Cheap (a few process spawns) but not free — don't call from
    /// the hot path.
    func runHealthCheck() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let issues = self.launcher.healthCheck()
            DispatchQueue.main.async {
                if issues != self.healthIssues {
                    self.healthIssues = issues
                }
            }
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
