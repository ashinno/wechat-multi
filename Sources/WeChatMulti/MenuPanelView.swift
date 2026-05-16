import SwiftUI
import AppKit

/// Popover content matching the Stack/Jade menubar dropdown in the design canvas
/// (logo.jsx → MenubarTemplate). Header + account list + footer actions.
struct MenuPanelView: View {
    @ObservedObject var state: AppState

    // Brand tints — match the jade palette from the design.
    private let activeTint = Color(red: 31/255, green: 197/255, blue: 107/255).opacity(0.18)
    private let panelWidth: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            accountList
            if state.staleCount > 0 {
                divider
                stalePrompt
            }
            divider
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
            Text("WeChat Multi")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(accountCountLabel)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var accountCountLabel: String {
        let n = state.accounts.count
        return n == 1 ? "1 account" : "\(n) accounts"
    }

    // MARK: - Account rows

    @ViewBuilder
    private var accountList: some View {
        if state.accounts.isEmpty {
            HStack {
                Spacer()
                Text("No accounts yet")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 14)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(state.accounts) { account in
                    AccountRow(account: account, activeTint: activeTint) {
                        state.handleRowClick(account)
                    } onQuit: {
                        state.quitAccount(account)
                    } onRename: {
                        promptRename(for: account)
                    }
                }
            }
        }
    }

    private func promptRename(for account: Account) {
        guard account.id > 0 else { return }
        state.onCloseMenu()
        // Defer so the popover dismisses before the modal alert appears —
        // otherwise the popover steals focus back when the alert closes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let alert = NSAlert()
            alert.messageText = "Rename Slot \(account.id)"
            alert.informativeText = "Cmd+Tab and the Dock will pick up the new name the next time you launch it."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")

            let currentName = state.launcher.slotName(slot: account.id)
            if currentName != nil {
                alert.addButton(withTitle: "Reset")
            }

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

    // MARK: - Stale clone prompt

    private var stalePrompt: some View {
        Button {
            state.onCloseMenu()
            state.onRefreshStale()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .frame(width: 14)
                Text("\(state.staleCount) clone\(state.staleCount == 1 ? "" : "s") out of date — refresh")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            FooterItem(title: "Add account…", shortcut: "⌘N", enabled: state.wechatInstalled) {
                state.onCloseMenu()
                state.onLaunchNew()
            }
            FooterItem(title: "Preferences…") {
                state.onCloseMenu()
                state.onOpenPreferences()
            }
            FooterItem(title: "Quit WeChat Multi", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
        }
    }

    private var divider: some View {
        Divider().padding(.vertical, 2)
    }
}

// MARK: - Account row

private struct AccountRow: View {
    let account: Account
    let activeTint: Color
    let onTap: () -> Void
    let onQuit: () -> Void
    let onRename: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                statusDot
                Text(account.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(account.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? activeTint : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            // Right-click on a row: per-instance actions. Mirrors the v1.0–1.2
            // submenu items so power users don't lose those affordances.
            if account.isRunning {
                Button("Bring to Front", action: onTap)
                Button("Quit This Instance", action: onQuit)
            } else {
                Button("Launch", action: onTap)
            }
            if account.id > 0 {
                Divider()
                Button("Rename…", action: onRename)
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        if account.isRunning {
            Circle()
                .fill(account.dotColor)
                .frame(width: 9, height: 9)
        } else {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                .frame(width: 9, height: 9)
        }
    }
}

// MARK: - Footer item

private struct FooterItem: View {
    let title: String
    var shortcut: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(enabled ? .primary : .secondary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered && enabled ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { isHovered = $0 }
    }
}
