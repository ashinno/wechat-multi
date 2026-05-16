import SwiftUI
import AppKit

/// Preferences window — the "crafted Mac utility" surface. Hero card at the
/// top establishes brand and orientation; grouped settings cards below carry
/// the actual controls. Section labels are tracked uppercase to signal
/// craft without being loud.
struct PreferencesView: View {
    @ObservedObject var state: AppState

    @State private var sourceVersion: String = ""
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var launchAtLoginNeedsApproval: Bool = LaunchAtLogin.requiresApproval
    @State private var hasMounted: Bool = false

    private var launcher: WeChatLauncher { state.launcher }
    private let windowWidth: CGFloat = 560

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            hero
                .opacity(hasMounted ? 1 : 0)
                .offset(y: hasMounted ? 0 : 6)
                .animation(Motion.entry.delay(0.02), value: hasMounted)

            startupCard
                .opacity(hasMounted ? 1 : 0)
                .offset(y: hasMounted ? 0 : 6)
                .animation(Motion.entry.delay(0.06), value: hasMounted)

            wechatSourceCard
                .opacity(hasMounted ? 1 : 0)
                .offset(y: hasMounted ? 0 : 6)
                .animation(Motion.entry.delay(0.10), value: hasMounted)

            clonesCard
                .opacity(hasMounted ? 1 : 0)
                .offset(y: hasMounted ? 0 : 6)
                .animation(Motion.entry.delay(0.14), value: hasMounted)

            footer
                .opacity(hasMounted ? 0.85 : 0)
                .animation(Motion.entry.delay(0.18), value: hasMounted)
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .frame(width: windowWidth, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refresh()
            DispatchQueue.main.async { hasMounted = true }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 18) {
            appIcon
                .frame(width: 60, height: 60)
                .shadow(color: Brand.jadeDeep.opacity(0.30), radius: 10, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 5) {
                Text("WeChat Multi")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .tracking(-0.2)

                HStack(spacing: 6) {
                    Text("Version \(bundleVersion)")
                        .font(.system(size: 11, design: .monospaced))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("Universal · macOS 13+")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)

                Text("Run multiple WeChat accounts side by side on your Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            // Atmospheric jade-tinted gradient — feels like the icon's color
            // is leaking onto the surface behind it. Very subtle in light
            // mode, slightly more present in dark.
            ZStack {
                LinearGradient(
                    colors: [
                        Brand.jade.opacity(0.16),
                        Brand.jadeDeep.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // A second wash anchored to the icon side creates depth.
                RadialGradient(
                    colors: [Brand.jade.opacity(0.18), Color.clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 220
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var appIcon: some View {
        // Use the bundled .icns at full fidelity; falls back to a generated
        // jade square if we're somehow run outside the .app (e.g. dev).
        Group {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.jade, Brand.jadeDeep],
                                         startPoint: .top, endPoint: .bottom))
            }
        }
    }

    // MARK: - Startup

    private var startupCard: some View {
        SettingsCard {
            SectionLabel(title: "Startup")
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Launch at login")
                        .font(.system(size: 13, weight: .medium))
                    Text(launchAtLoginNeedsApproval
                         ? "Approval needed in System Settings."
                         : "Start WeChat Multi automatically when you log in.")
                        .font(.system(size: 11))
                        .foregroundStyle(launchAtLoginNeedsApproval ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .labelsHidden()
                    .tint(Brand.jade)
                    .onChange(of: launchAtLogin) { newValue in
                        applyLaunchAtLogin(newValue)
                    }
            }
            if launchAtLoginNeedsApproval {
                Button("Open Login Items in System Settings") { openLoginItemsSettings() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        }
    }

    // MARK: - WeChat source

    private var wechatSourceCard: some View {
        SettingsCard {
            HStack {
                SectionLabel(title: "WeChat Source")
                Spacer()
                if !sourceVersion.isEmpty {
                    Text("v\(sourceVersion)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Brand.jade.opacity(0.14))
                        )
                }
            }

            // Path in a subtle monospace panel — feels like a terminal output,
            // matches the technical authority of a developer-feeling utility.
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(launcher.wechatAppPath == nil ? Brand.badgeRed : Brand.jadeDeep)
                Text(launcher.wechatAppPath ?? "WeChat.app not found")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(launcher.wechatAppPath == nil ? Brand.badgeRed : .primary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )

            HStack(spacing: 8) {
                Button("Choose…") { chooseWeChat() }
                Button("Reset to Default") {
                    launcher.clearCustomPath()
                    refresh()
                }
                .disabled(UserDefaults.standard.string(forKey: "WeChatAppPath") == nil)
                Spacer()
            }
            .controlSize(.small)
        }
    }

    // MARK: - Clones

    private var clonesCard: some View {
        let cloneCount = launcher.existingCloneSlots().count
        let stale = state.staleCount
        return SettingsCard {
            HStack {
                SectionLabel(title: "Clones")
                Spacer()
                cloneCountBadge(cloneCount)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(cloneCount == 0
                     ? "No clone bundles yet — launching a new instance creates one."
                     : "\(cloneCount) bundle\(cloneCount == 1 ? "" : "s") under ~/Applications/WeChat Multi/")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if stale > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 11))
                        Text("\(stale) out of date — refresh recommended")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Open Folder") { openClonesFolder() }
                if stale > 0 {
                    Button("Refresh Outdated…") {
                        NSApp.keyWindow?.close()
                        state.onRefreshStale()
                    }
                }
                Spacer()
                Button("Reset All…") { resetClones() }
                    .disabled(cloneCount == 0)
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func cloneCountBadge(_ count: Int) -> some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Brand.jadeDeep)
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, 4)
                .background(Capsule().fill(Brand.jade.opacity(0.16)))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Link("github.com/ashinno/wechat-multi",
                 destination: URL(string: "https://github.com/ashinno/wechat-multi")!)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Brand.jadeDeep)
            Spacer()
            Text("Crafted for macOS")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    // MARK: - Logic

    private var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private func refresh() {
        sourceVersion = launcher.wechatAppVersion() ?? ""
        launchAtLogin = LaunchAtLogin.isEnabled
        launchAtLoginNeedsApproval = LaunchAtLogin.requiresApproval
        state.refresh()
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginNeedsApproval = LaunchAtLogin.requiresApproval
            launchAtLogin = LaunchAtLogin.isEnabled
        } catch {
            let alert = NSAlert()
            alert.messageText = enabled
                ? "Could Not Enable Launch at Login"
                : "Could Not Disable Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
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
