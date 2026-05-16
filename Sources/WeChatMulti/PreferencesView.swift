import SwiftUI
import AppKit

/// Preferences window content — the spillover from the popover's "Preferences…"
/// row. Holds the WeChat.app path picker plus the maintenance actions that
/// used to live as menu items (open clones folder, reset clones, etc.).
struct PreferencesView: View {
    @ObservedObject var state: AppState
    @State private var sourceVersion: String = ""

    private var launcher: WeChatLauncher { state.launcher }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("WeChat.app:")
                        .frame(width: 110, alignment: .trailing)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(launcher.wechatAppPath ?? "Not found")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(launcher.wechatAppPath == nil ? .red : .primary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !sourceVersion.isEmpty {
                            Text("Version \(sourceVersion)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Button("Choose…") { chooseWeChat() }
                            Button("Reset to default") {
                                launcher.clearCustomPath()
                                refresh()
                            }
                            .disabled(UserDefaults.standard.string(forKey: "WeChatAppPath") == nil)
                        }
                    }
                }
            }

            Divider().padding(.vertical, 6)

            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("Clones:")
                        .frame(width: 110, alignment: .trailing)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(launcher.existingCloneSlots().count) clone bundle\(launcher.existingCloneSlots().count == 1 ? "" : "s") under ~/Applications/WeChat Multi/")
                            .font(.system(size: 12))
                        if state.staleCount > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("\(state.staleCount) out of date")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                            }
                        }
                        HStack {
                            Button("Open Clones Folder") { openClonesFolder() }
                            if state.staleCount > 0 {
                                Button("Refresh Outdated…") {
                                    NSApp.keyWindow?.close()
                                    state.onRefreshStale()
                                }
                            }
                            Button("Reset All…") { resetClones() }
                                .disabled(launcher.existingCloneSlots().isEmpty)
                        }
                    }
                }
            }

            Divider().padding(.vertical, 6)

            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("About:")
                        .frame(width: 110, alignment: .trailing)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WeChat Multi \(bundleVersion)")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Run multiple WeChat accounts side by side on macOS.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Link("github.com/ashinno/wechat-multi",
                             destination: URL(string: "https://github.com/ashinno/wechat-multi")!)
                            .font(.system(size: 11))
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { refresh() }
    }

    private var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private func refresh() {
        sourceVersion = launcher.wechatAppVersion() ?? ""
        state.refresh()
    }

    private func chooseWeChat() {
        let panel = NSOpenPanel()
        panel.title = "Select WeChat.app"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        if panel.runModal() == .OK, let url = panel.url {
            let p = url.path
            let valid = FileManager.default.fileExists(atPath: "\(p)/Contents/MacOS/WeChat") ||
                        FileManager.default.fileExists(atPath: "\(p)/Contents/MacOS/微信")
            if valid {
                launcher.setCustomPath(p)
                refresh()
            } else {
                let alert = NSAlert()
                alert.messageText = "Not a WeChat App"
                alert.informativeText = "The selected bundle does not contain a WeChat executable."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private func openClonesFolder() {
        try? FileManager.default.createDirectory(at: launcher.cloneRoot,
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.open(launcher.cloneRoot)
    }

    private func resetClones() {
        let alert = NSAlert()
        alert.messageText = "Reset all WeChat clones?"
        alert.informativeText = """
        This deletes every cloned WeChat bundle under ~/Applications/WeChat Multi/.
        Sandbox containers (signed-in sessions, chat history) are preserved and \
        will reattach when the clones are rebuilt on next launch.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        launcher.quitAll()
        usleep(500_000)
        do {
            try launcher.resetAllClones()
        } catch {
            let err = NSAlert()
            err.messageText = "Reset Failed"
            err.informativeText = error.localizedDescription
            err.alertStyle = .warning
            err.addButton(withTitle: "OK")
            err.runModal()
        }
        refresh()
    }
}
