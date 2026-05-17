import SwiftUI
import AppKit

/// Popover content matching the Stack/Jade menubar dropdown in the design canvas.
/// Refined typography rhythm, animated hover states, status dots with inner
/// highlight, and tighter footer treatment than the v1.4 first cut.
struct MenuPanelView: View {
    @ObservedObject var state: AppState

    private let panelWidth: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            accountList
            if state.staleCount > 0 {
                stalePrompt
                divider
            } else {
                divider
            }
            footer
        }
        .padding(6)
        .frame(width: panelWidth)
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
                               canQuitAll: state.hasRunningInstances) {
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
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func promptDelete(for account: Account) {
        guard account.id > 0 else { return }
        state.onCloseMenu()
        // Defer so the popover dismisses before the modal alert appears.
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

            // Checkbox accessory: only show when there's something to reset.
            var sandboxCheckbox: NSButton?
            if hasSandbox {
                let checkbox = NSButton(checkboxWithTitle: "Also delete signed-in session and chat history",
                                        target: nil, action: nil)
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
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 1) {
            FooterItem(icon: "plus.circle.fill",
                       title: "Add account…",
                       shortcut: "⌘N",
                       tintIcon: true,
                       enabled: state.wechatInstalled) {
                state.onCloseMenu()
                state.onLaunchNew()
            }
            FooterItem(icon: "slider.horizontal.3",
                       title: "Preferences…") {
                state.onCloseMenu()
                state.onOpenPreferences()
            }
            FooterItem(icon: "power",
                       title: "Quit WeChat Multi",
                       shortcut: "⌘Q") {
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
    let onTap: () -> Void
    let onQuit: () -> Void
    let onRename: () -> Void
    let onQuitAll: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
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
        if isHovered {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Brand.jade.opacity(0.18),
                            Brand.jade.opacity(0.10)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Brand.jade.opacity(0.18), lineWidth: 0.5)
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
    }

    private var iconStyle: AnyShapeStyle {
        if !enabled { return AnyShapeStyle(Color.secondary.opacity(0.5)) }
        if tintIcon { return AnyShapeStyle(Brand.jade) }
        return AnyShapeStyle(.secondary)
    }
}
