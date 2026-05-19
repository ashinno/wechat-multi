import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Transferable payload for drag-to-reorder. Wrapping in a struct lets us
/// register a custom UTType-style identifier instead of conflicting with
/// arbitrary text/int drops from outside the app.
struct AccountDragID: Codable, Transferable {
    let slot: Int
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .wechatMultiAccountID)
    }
}

extension UTType {
    static var wechatMultiAccountID: UTType {
        UTType(exportedAs: "com.wechatmulti.account-id")
    }
}

/// Popover content matching the Stack/Jade menubar dropdown in the design canvas.
/// Refined typography rhythm, animated hover states, status dots with inner
/// highlight, and tighter footer treatment than the v1.4 first cut.
struct MenuPanelView: View {
    @ObservedObject var state: AppState

    @State private var dropTargetSlot: Int? = nil
    @State private var draggingSlot: Int? = nil
    @State private var deleteBridgeInstalled = false

    private let panelWidth: CGFloat = 280

    private func installDeleteBridge() {
        guard !deleteBridgeInstalled else { return }
        deleteBridgeInstalled = true
        // Keyboard Delete pressed → AppState calls this back with the focused
        // account; route it through the same modal prompt the right-click
        // path uses. Weak capture of state to avoid a retain cycle (the
        // closure is stored on state itself).
        state.onRequestDelete = { [weak state] account in
            guard let state else { return }
            DispatchQueue.main.async {
                MenuPanelDeletePrompt.show(for: account, state: state)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            accountList
            if !state.healthIssues.isEmpty {
                healthPrompt
            }
            if state.staleCount > 0 {
                stalePrompt
            }
            divider
            footer
        }
        .padding(6)
        .frame(width: panelWidth)
        .animation(Motion.entry, value: state.accounts.map(\.id))
        .onAppear { installDeleteBridge() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: MenubarIcon.template(size: 18))
                .renderingMode(.template)
                .foregroundColor(.primary)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text("WeChat Multi")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
            }

            Spacer()

            // Account count in a refined pill instead of plain text — adds a
            // beat of color that ties the popover to the brand without being
            // loud. Jade tint on hover-ready states.
            Text(accountCountLabel)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Brand.jadeDeep)
                .padding(.horizontal, 7)
                .padding(.vertical, 1.5)
                .background(
                    Capsule().fill(Brand.jade.opacity(0.16))
                )
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .padding(.bottom, 8)
    }

    private var accountCountLabel: String {
        let n = state.accounts.count
        return n == 1 ? "1 account" : "\(n) accounts"
    }

    // MARK: - Account list

    @ViewBuilder
    private var accountList: some View {
        if state.accounts.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                    Text("No accounts yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 16)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(state.accounts) { account in
                    AccountRow(account: account,
                               canQuitAll: state.hasRunningInstances,
                               isDropTarget: dropTargetSlot == account.id,
                               isBeingDragged: draggingSlot == account.id,
                               isKeyboardFocused: state.focusedSlotID == account.id) {
                        state.handleRowClick(account)
                    } onQuit: {
                        state.quitAccount(account)
                    } onRename: {
                        promptRename(for: account)
                    } onQuitAll: {
                        state.onCloseMenu()
                        state.onQuitAllInstances()
                    } onDelete: {
                        promptDelete(for: account)
                    }
                    .draggable(AccountDragID(slot: account.id)) {
                        // Custom drag preview — solid surface so the drag feels weighty
                        AccountRow(account: account, canQuitAll: false,
                                   isDropTarget: false, isBeingDragged: false,
                                   onTap: {}, onQuit: {}, onRename: {},
                                   onQuitAll: {}, onDelete: {})
                            .frame(width: 250)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .windowBackgroundColor))
                            )
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                            .onAppear {
                                withAnimation(Motion.hover) { draggingSlot = account.id }
                            }
                    }
                    .dropDestination(for: AccountDragID.self) { items, _ in
                        defer {
                            withAnimation(Motion.hover) {
                                dropTargetSlot = nil
                                draggingSlot = nil
                            }
                        }
                        guard let dragged = items.first, dragged.slot != account.id else { return false }
                        state.moveAccount(dragged.slot, before: account.id)
                        return true
                    } isTargeted: { targeted in
                        withAnimation(Motion.hover) {
                            dropTargetSlot = targeted ? account.id : (dropTargetSlot == account.id ? nil : dropTargetSlot)
                        }
                    }
                }

                // End-of-list drop zone — lets users move a slot to the bottom
                // by dragging past the last row. Invisible until something is
                // actually being dragged over it.
                Color.clear
                    .frame(height: 10)
                    .contentShape(Rectangle())
                    .dropDestination(for: AccountDragID.self) { items, _ in
                        defer {
                            withAnimation(Motion.hover) {
                                dropTargetSlot = nil
                                draggingSlot = nil
                            }
                        }
                        guard let dragged = items.first else { return false }
                        state.moveAccount(dragged.slot, before: nil)
                        return true
                    } isTargeted: { _ in /* end-zone needs no highlight */ }
            }
            .padding(.vertical, 2)
        }
    }

    private func promptDelete(for account: Account) {
        MenuPanelDeletePrompt.show(for: account, state: state)
    }

    private func promptRename(for account: Account) {
        guard account.id > 0 else { return }
        state.onCloseMenu()
        // Defer so the popover dismisses before the modal alert appears —
        // otherwise the popover steals focus back when the alert closes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let alert = NSAlert()
            alert.messageText = "Rename Slot \(account.id)"
            alert.informativeText = "Cmd+Tab and the Dock will pick up the new name the next time you launch this instance."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")

            let currentName = state.launcher.slotName(slot: account.id)
            if currentName != nil { alert.addButton(withTitle: "Reset") }

            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            field.placeholderString = "WeChat \(account.id)"
            field.stringValue = currentName ?? ""
            alert.accessoryView = field
            alert.window.initialFirstResponder = field

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                state.renameAccount(account, to: trimmed.isEmpty ? nil : trimmed)
            case .alertThirdButtonReturn:
                state.renameAccount(account, to: nil)
            default: break
            }
        }
    }

    // MARK: - Health prompt

    private var healthPrompt: some View {
        Button {
            state.onCloseMenu()
            state.onRepairUnhealthy()
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(Brand.badgeRed.opacity(0.18))
                        .frame(width: 18, height: 18)
                    Image(systemName: "wrench.adjustable.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Brand.badgeRed)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(state.healthIssues.count) clone\(state.healthIssues.count == 1 ? "" : "s") need repair")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("Signature or bundle integrity issues detected")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.badgeRed)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Health check found signature or bundle integrity issues. Click to rebuild each affected clone from /Applications/WeChat.app — signed-in sessions are preserved.")
    }

    // MARK: - Stale prompt

    private var stalePrompt: some View {
        Button {
            state.onCloseMenu()
            state.onRefreshStale()
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 18, height: 18)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(state.staleCount) clone\(state.staleCount == 1 ? "" : "s") out of date")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("Click to refresh from latest WeChat.app")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("WeChat.app has updated since these clones were created. Click to rebuild them while preserving each clone's signed-in session.")
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 1) {
            FooterItem(icon: "plus.circle.fill",
                       title: "Add account…",
                       shortcut: "⌘N",
                       tintIcon: true,
                       tooltip: state.wechatInstalled
                            ? "Launch a new isolated WeChat instance with its own login"
                            : "Install WeChat first, then come back",
                       enabled: state.wechatInstalled) {
                state.onCloseMenu()
                state.onLaunchNew()
            }
            FooterItem(icon: "slider.horizontal.3",
                       title: "Preferences…",
                       tooltip: "WeChat path, clones, launch-at-login, backup, etc.") {
                state.onCloseMenu()
                state.onOpenPreferences()
            }
            FooterItem(icon: "info.circle",
                       title: "About WeChat Multi",
                       tooltip: "Version, credits, license, and links") {
                state.onCloseMenu()
                state.onOpenAbout()
            }
            FooterItem(icon: "power",
                       title: "Quit WeChat Multi",
                       shortcut: "⌘Q",
                       tooltip: "Quit this menubar app — does not close running WeChat windows") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 2)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
    }
}

// MARK: - Account row

private struct AccountRow: View {
    let account: Account
    let canQuitAll: Bool
    var isDropTarget: Bool = false
    var isBeingDragged: Bool = false
    var isKeyboardFocused: Bool = false
    let onTap: () -> Void
    let onQuit: () -> Void
    let onRename: () -> Void
    let onQuitAll: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        // Jade hairline shown above the row when it's the active drop target.
        // Sits in the small vertical gap between rows so it doesn't bump
        // anything around as it appears.
        VStack(spacing: 0) {
            Rectangle()
                .fill(Brand.jadeDeep)
                .frame(height: isDropTarget ? 2 : 0)
                .padding(.horizontal, 6)
                .opacity(isDropTarget ? 1 : 0)
            rowButton
        }
        .opacity(isBeingDragged ? 0.45 : 1)
        .help(account.isRunning
              ? "\(account.displayName) is running — click to bring its window to the front"
              : "\(account.displayName) is stopped — click to launch this slot")
    }

    private var rowButton: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                statusDot
                VStack(alignment: .leading, spacing: 0) {
                    Text(account.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(account.subtitle)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(account.isRunning ? Brand.jadeDeep : Color.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Motion.hover) { isHovered = hovering }
        }
        .contextMenu {
            if account.isRunning {
                Button("Bring to Front", action: onTap)
                Button("Quit This Instance", action: onQuit)
            } else {
                Button("Launch", action: onTap)
            }
            if account.id > 0 {
                Divider()
                Button("Rename…", action: onRename)
                // Only allow delete when stopped — running clones must be quit
                // first (deleting a live bundle is unsafe). The Quit option
                // above is the path for "quit then delete".
                if !account.isRunning {
                    Button("Delete Slot…", role: .destructive, action: onDelete)
                }
            }
            if canQuitAll {
                Divider()
                Button("Quit All Running Instances", role: .destructive, action: onQuitAll)
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        let active = isHovered || isKeyboardFocused
        if active {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Brand.jade.opacity(isKeyboardFocused ? 0.24 : 0.18),
                            Brand.jade.opacity(isKeyboardFocused ? 0.14 : 0.10)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Brand.jade.opacity(isKeyboardFocused ? 0.36 : 0.18),
                                      lineWidth: isKeyboardFocused ? 1 : 0.5)
                )
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        ZStack {
            if account.isRunning {
                // Outer glow ring — very subtle, telegraphs "alive"
                Circle()
                    .fill(account.dotColor.opacity(0.18))
                    .frame(width: 14, height: 14)
                // Filled dot with an inner highlight gradient for depth
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                account.dotColor,
                                account.dotColor.opacity(0.78)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 8, height: 8)
                    .overlay(
                        // Tiny white speckle at top-left for a glossy hint
                        Circle()
                            .fill(Color.white.opacity(0.45))
                            .frame(width: 2, height: 2)
                            .offset(x: -1.3, y: -1.3)
                    )
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.55), lineWidth: 1)
                    .frame(width: 9, height: 9)
            }
        }
        .frame(width: 14, height: 14)
        .animation(Motion.state, value: account.isRunning)
    }
}

// MARK: - Footer item

private struct FooterItem: View {
    let icon: String
    let title: String
    var shortcut: String? = nil
    var tintIcon: Bool = false
    var tooltip: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(iconStyle)
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(enabled ? .primary : .tertiary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .opacity(isHovered && enabled ? 1 : 0.7)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered && enabled ? Brand.hoverTint : .clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering in
            withAnimation(Motion.hover) { isHovered = hovering }
        }
        .help(tooltip ?? title)
    }

    private var iconStyle: AnyShapeStyle {
        if !enabled { return AnyShapeStyle(Color.secondary.opacity(0.5)) }
        if tintIcon { return AnyShapeStyle(Brand.jade) }
        return AnyShapeStyle(.secondary)
    }
}

// MARK: - Delete prompt helper

/// Confirmation flow for "Delete Slot…". Lives outside MenuPanelView as a
/// static helper so it can be invoked from both the row's mouse context
/// menu and the keyboard Delete handler bridged through AppState.
enum MenuPanelDeletePrompt {
    static func show(for account: Account, state: AppState) {
        guard account.id > 0 else { return }
        state.onCloseMenu()
        // Defer so the popover dismisses before the modal alert appears —
        // otherwise the popover steals focus back when the alert closes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let hasSandbox = state.launcher.sandboxContainerExists(slot: account.id)

            let alert = NSAlert()
            alert.messageText = "Delete \(account.displayName)?"
            alert.informativeText = hasSandbox
                ? "This removes the cloned WeChat bundle from ~/Applications/WeChat Multi/. Your signed-in session in the sandbox container is preserved by default — check the box below to fully reset this account."
                : "This removes the cloned WeChat bundle from ~/Applications/WeChat Multi/. No sandbox container exists for this slot, so nothing else needs cleanup."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")

            var sandboxCheckbox: NSButton?
            if hasSandbox {
                let checkbox = NSButton(
                    checkboxWithTitle: "Also delete signed-in session and chat history",
                    target: nil, action: nil
                )
                checkbox.state = .off
                checkbox.frame = NSRect(x: 0, y: 0, width: 320, height: 22)
                alert.accessoryView = checkbox
                sandboxCheckbox = checkbox
            }

            guard alert.runModal() == .alertFirstButtonReturn else { return }

            let removeSandbox = sandboxCheckbox?.state == .on
            if let err = state.launcher.deleteClone(slot: account.id,
                                                    removeSandboxContainer: removeSandbox) {
                let errAlert = NSAlert()
                errAlert.messageText = "Could Not Delete"
                errAlert.informativeText = err
                errAlert.alertStyle = .warning
                errAlert.addButton(withTitle: "OK")
                errAlert.runModal()
            }
            state.refresh()
        }
    }
}
