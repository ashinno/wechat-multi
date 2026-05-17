import Foundation
import AppKit

/// Manages cloned WeChat.app bundles so multiple WeChat instances can run side by side.
///
/// WeChat on macOS enforces a singleton via its CFBundleIdentifier. Spawning the binary
/// twice (with `open -n` or `nohup`) does not yield two windows — the second process
/// exits as soon as it sees the existing one. The proven workaround is to clone
/// `/Applications/WeChat.app` into uniquely-identified copies. Each clone gets its own
/// bundle ID, which gives it its own sandbox container and bypasses the singleton check.
final class WeChatLauncher {

    // MARK: - Configuration

    private let defaults = UserDefaults.standard
    private let customPathKey = "WeChatAppPath"
    private let slotNamesKey = "SlotNames"

    private let defaultPaths = [
        "/Applications/WeChat.app",
        "/Applications/微信.app",
        "\(NSHomeDirectory())/Applications/WeChat.app"
    ]

    /// Directory that holds the cloned bundles. Lives under `~/Applications/` so users
    /// can find clones in Finder if they want to pin one to the Dock manually.
    let cloneRoot: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/WeChat Multi", isDirectory: true)
    }()

    var wechatAppPath: String? {
        if let custom = defaults.string(forKey: customPathKey),
           FileManager.default.fileExists(atPath: custom) {
            return custom
        }
        return defaultPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    func setCustomPath(_ path: String) {
        defaults.set(path, forKey: customPathKey)
    }

    func clearCustomPath() {
        defaults.removeObject(forKey: customPathKey)
    }

    // MARK: - Custom slot names

    /// Returns the user-assigned name for the given slot, or nil if it has the
    /// default name. Slot 0 (the original WeChat.app) is intentionally unnamed —
    /// we don't try to manage its display name.
    func slotName(slot: Int) -> String? {
        guard slot > 0 else { return nil }
        let dict = defaults.dictionary(forKey: slotNamesKey) as? [String: String] ?? [:]
        return dict["\(slot)"]
    }

    func setSlotName(slot: Int, name: String?) {
        guard slot > 0 else { return }
        var dict = defaults.dictionary(forKey: slotNamesKey) as? [String: String] ?? [:]
        if let name, !name.isEmpty {
            dict["\(slot)"] = name
        } else {
            dict.removeValue(forKey: "\(slot)")
        }
        defaults.set(dict, forKey: slotNamesKey)
    }

    /// The name we should write into the clone's Info.plist — the user's
    /// custom name if set, otherwise "WeChat <slot>" as a default.
    func cloneDisplayName(slot: Int) -> String {
        return slotName(slot: slot) ?? "WeChat \(slot)"
    }

    // MARK: - Per-slot colors

    /// Returns a stable, distinct color for the given slot so users can tell
    /// instances apart at a glance. Slot 0 (the original WeChat) always uses
    /// the WeChat green; clone slots cycle through a palette that maps well
    /// in both light and dark menu contexts.
    func slotColor(slot: Int) -> NSColor {
        if slot == 0 {
            return NSColor(srgbRed: 0.027, green: 0.757, blue: 0.376, alpha: 1.0)
        }
        let palette: [NSColor] = [
            .systemBlue, .systemPurple, .systemOrange, .systemPink,
            .systemTeal, .systemIndigo, .systemRed, .systemYellow
        ]
        let index = (abs(slot) - 1) % palette.count
        return palette[index]
    }

    /// Renders a small filled circle in the slot's color, ready to be shown as
    /// an NSMenuItem.image. Uses NSImage's deferred draw block so the image
    /// re-renders correctly when the menu opens in a different appearance
    /// (e.g. light → dark mode).
    func slotDotImage(slot: Int, size: CGFloat = 14) -> NSImage {
        let color = slotColor(slot: slot)
        return NSImage(size: NSSize(width: size, height: size),
                       flipped: false) { rect in
            color.setFill()
            // Inset by 1px so the circle has a hairline of breathing room
            // against neighboring menu text.
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            path.fill()
            return true
        }
    }

    // MARK: - Version detection

    /// Reads CFBundleShortVersionString from the source `/Applications/WeChat.app`.
    /// Used to decide which clones are stale and need a refresh.
    func wechatAppVersion() -> String? {
        guard let appPath = wechatAppPath else { return nil }
        return readPlistString(at: "\(appPath)/Contents/Info.plist",
                               key: "CFBundleShortVersionString")
    }

    func cloneVersion(slot: Int) -> String? {
        let plist = cloneURL(for: slot).appendingPathComponent("Contents/Info.plist").path
        return readPlistString(at: plist, key: "CFBundleShortVersionString")
    }

    /// Slots whose on-disk clone version differs from the current WeChat.app version.
    /// If the source version cannot be read, returns an empty array (we can't decide).
    func staleClones() -> [Int] {
        guard let sourceVersion = wechatAppVersion() else { return [] }
        return existingCloneSlots().filter { slot in
            // Treat unreadable clone Info.plist as stale so the user is nudged
            // to rebuild a corrupt bundle.
            guard let cloneVer = cloneVersion(slot: slot) else { return true }
            return cloneVer != sourceVersion
        }
    }

    /// Of the supplied slots, which ones are currently running. Refresh requires
    /// these to be quit first, since we can't replace a live bundle reliably.
    func runningSlotsBlocking(_ slots: [Int]) -> [Int] {
        let running = Set(runningInstances().map(\.slot))
        return slots.filter { running.contains($0) }
    }

    private func readPlistString(at path: String, key: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data,
                                                                       format: nil) as? [String: Any]
        else { return nil }
        return plist[key] as? String
    }

    // MARK: - Clone management

    enum PrepareResult {
        case ready(URL)
        case sourceMissing
        case failed(String)
    }

    /// Stages that prepareClone / refreshClone report so the UI can show a
    /// human-readable status during the otherwise-silent multi-second copy.
    /// Invoked from whatever queue the launcher runs on — callers should
    /// marshal to main themselves.
    typealias ProgressCallback = (_ stage: String) -> Void

    func cloneURL(for slot: Int) -> URL {
        cloneRoot.appendingPathComponent("WeChat \(slot).app", isDirectory: true)
    }

    func cloneBundleID(for slot: Int) -> String {
        "com.wechatmulti.clone\(slot)"
    }

    func cloneExists(slot: Int) -> Bool {
        FileManager.default.fileExists(atPath: cloneURL(for: slot).path)
    }

    /// Materializes a clone for the given slot if it does not already exist.
    /// Performs the bundle copy, bundle-ID rewrite, and ad-hoc re-sign.
    /// Reports stage transitions through the optional `progress` callback.
    func prepareClone(slot: Int, progress: ProgressCallback? = nil) -> PrepareResult {
        guard let source = wechatAppPath else { return .sourceMissing }
        let target = cloneURL(for: slot)

        if FileManager.default.fileExists(atPath: target.path) {
            return .ready(target)
        }

        do {
            try FileManager.default.createDirectory(at: cloneRoot,
                                                    withIntermediateDirectories: true)
        } catch {
            return .failed("Could not create clones directory: \(error.localizedDescription)")
        }

        progress?("Copying WeChat.app (one-time setup)…")
        // APFS supports copy-on-write clones, so `cp -Rc` is nearly instant for the
        // hundreds of MB that WeChat.app weighs in at.
        if let copyError = run("/bin/cp", ["-Rc", source, target.path]) {
            return .failed("Copying WeChat.app failed: \(copyError)")
        }

        progress?("Configuring & re-signing…")
        // Rewrite the bundle identifier and display names so macOS treats this clone
        // as a separate app with its own sandbox container.
        if let writeError = writeIdentityToBundle(at: target, slot: slot) {
            return .failed(writeError)
        }

        return .ready(target)
    }

    /// Renames a clone in-place — updates CFBundleName/CFBundleDisplayName in
    /// the bundle's Info.plist and re-signs ad-hoc. The bundle identifier is
    /// left alone so the sandbox container (and signed-in WeChat session) is
    /// preserved. The change becomes visible in Cmd+Tab/Dock the next time
    /// the clone is launched.
    @discardableResult
    func renameClone(slot: Int, newName: String?) -> String? {
        setSlotName(slot: slot, name: newName)
        guard cloneExists(slot: slot) else { return nil }
        return writeIdentityToBundle(at: cloneURL(for: slot), slot: slot)
    }

    /// Deletes the on-disk clone bundle and recreates it from the current
    /// WeChat.app. The sandbox container lives in a separate path keyed by
    /// bundle ID, so the user's WeChat session survives a refresh.
    func refreshClone(slot: Int, progress: ProgressCallback? = nil) -> PrepareResult {
        let target = cloneURL(for: slot)
        if FileManager.default.fileExists(atPath: target.path) {
            progress?("Removing old bundle…")
            do {
                try FileManager.default.removeItem(at: target)
            } catch {
                return .failed("Could not remove old clone: \(error.localizedDescription)")
            }
        }
        return prepareClone(slot: slot, progress: progress)
    }

    /// Writes our identity (bundle ID + display name) into a clone bundle's
    /// Info.plist, drops the now-invalid Tencent signature, and ad-hoc re-signs.
    /// Called both during initial clone creation and on rename.
    private func writeIdentityToBundle(at target: URL, slot: Int) -> String? {
        let plist = target.appendingPathComponent("Contents/Info.plist").path
        let bundleID = cloneBundleID(for: slot)
        let displayName = cloneDisplayName(slot: slot)
        let plistBuddy = "/usr/libexec/PlistBuddy"

        _ = run(plistBuddy, ["-c", "Set :CFBundleIdentifier \(bundleID)", plist])
        _ = run(plistBuddy, ["-c", "Set :CFBundleName \(displayName)", plist])
        // CFBundleDisplayName may be absent — Set will fail; Add as fallback.
        if run(plistBuddy, ["-c", "Set :CFBundleDisplayName \(displayName)", plist]) != nil {
            _ = run(plistBuddy, ["-c", "Add :CFBundleDisplayName string \(displayName)", plist])
        }

        // Drop the original signature (Info.plist edit invalidates it anyway).
        let signatureDir = target.appendingPathComponent("Contents/_CodeSignature")
        try? FileManager.default.removeItem(at: signatureDir)

        if let signError = run("/usr/bin/codesign",
                               ["--force", "--deep", "--sign", "-", target.path]) {
            NSLog("Ad-hoc sign warning for slot \(slot): \(signError)")
        }
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])

        return nil
    }

    func resetAllClones() throws {
        if FileManager.default.fileExists(atPath: cloneRoot.path) {
            try FileManager.default.removeItem(at: cloneRoot)
        }
    }

    /// Delete a single clone bundle and (optionally) its sandbox container.
    /// Refuses to delete a running clone — caller must quit it first.
    ///
    /// By default the sandbox container at
    /// `~/Library/Containers/com.wechatmulti.cloneN/` is preserved, so if the
    /// user later re-creates the same slot the WeChat session reattaches.
    /// Pass `removeSandboxContainer: true` for a full reset that also wipes
    /// the signed-in login data.
    ///
    /// Returns `nil` on success, an error description otherwise.
    @discardableResult
    func deleteClone(slot: Int, removeSandboxContainer: Bool = false) -> String? {
        guard slot > 0 else {
            return "The main account isn't a clone — it can't be deleted from here."
        }

        if runningInstances().contains(where: { $0.slot == slot }) {
            return "Quit Slot \(slot) before deleting it."
        }

        let target = cloneURL(for: slot)
        if FileManager.default.fileExists(atPath: target.path) {
            do {
                try FileManager.default.removeItem(at: target)
            } catch {
                return "Could not delete the bundle: \(error.localizedDescription)"
            }
        }

        // Drop the user-assigned name so a future slot with the same number
        // starts from the default "WeChat N" name (unless renamed again).
        setSlotName(slot: slot, name: nil)

        if removeSandboxContainer {
            let container = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/\(cloneBundleID(for: slot))")
            try? FileManager.default.removeItem(at: container)
        }

        return nil
    }

    /// True if a sandbox container exists for this slot. Used by the delete
    /// confirmation to decide whether to surface the "also reset login data"
    /// checkbox or hide it (nothing to reset).
    func sandboxContainerExists(slot: Int) -> Bool {
        guard slot > 0 else { return false }
        let container = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(cloneBundleID(for: slot))")
        return FileManager.default.fileExists(atPath: container.path)
    }

    func existingCloneSlots() -> [Int] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: cloneRoot,
                                                                          includingPropertiesForKeys: nil) else {
            return []
        }
        let regex = try? NSRegularExpression(pattern: #"^WeChat (\d+)\.app$"#)
        var slots: [Int] = []
        for url in entries {
            let name = url.lastPathComponent
            let range = NSRange(name.startIndex..., in: name)
            if let match = regex?.firstMatch(in: name, range: range),
               match.numberOfRanges == 2,
               let slotRange = Range(match.range(at: 1), in: name),
               let slot = Int(name[slotRange]) {
                slots.append(slot)
            }
        }
        return slots.sorted()
    }

    // MARK: - Launching

    enum LaunchResult {
        case launched(slot: Int)
        case sourceMissing
        case failed(String)
    }

    /// Picks the lowest free slot, prepares its clone, and launches it.
    func launchNextAvailableInstance(progress: ProgressCallback? = nil) -> LaunchResult {
        let running = Set(runningInstances().map { $0.slot })
        var slot = 1
        while running.contains(slot) {
            slot += 1
        }
        return launchSpecificInstance(slot: slot, progress: progress)
    }

    /// Returns true when launching this slot will require the slow one-time
    /// clone copy. Callers use this to decide whether to surface a progress UI.
    func slotNeedsPreparation(slot: Int) -> Bool {
        !cloneExists(slot: slot)
    }

    func launchSpecificInstance(slot: Int,
                                progress: ProgressCallback? = nil) -> LaunchResult {
        switch prepareClone(slot: slot, progress: progress) {
        case .sourceMissing:
            return .sourceMissing
        case .failed(let reason):
            return .failed(reason)
        case .ready(let url):
            progress?("Launching…")
            if let err = run("/usr/bin/open", ["-na", url.path]) {
                return .failed("open failed: \(err)")
            }
            return .launched(slot: slot)
        }
    }

    // MARK: - Process inspection

    struct InstanceInfo {
        let slot: Int          // 0 means the original /Applications/WeChat.app
        let pid: Int32
        let startTime: String
        let bundlePath: String
    }

    /// Returns one entry per WeChat main process — the original /Applications/WeChat.app
    /// and any running clones under `~/Applications/WeChat Multi/`.
    func runningInstances() -> [InstanceInfo] {
        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,lstart=,comm="]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return []
        }

        // Read BEFORE waitUntilExit: ps output for a full system exceeds the
        // pipe buffer (~16 KB), so the child would block on write and
        // waitUntilExit would never return. Drain first, then wait.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        let cloneRootPath = cloneRoot.path
        var results: [InstanceInfo] = []

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 7, let pid = Int32(parts[0]) else { continue }

            let startTime = parts[1..<6].joined(separator: " ")
            let command = parts[6..<parts.count].joined(separator: " ")

            // First gate: must end with the main WeChat executable. WeChat ships
            // helper binaries (WeChatAppEx, WeChatPlugin, crashpad_handler, etc.)
            // inside nested .app bundles; none of them are named just "WeChat"
            // or "微信" so this check excludes them cleanly.
            let isWeChatBinary = command.hasSuffix("/Contents/MacOS/WeChat") ||
                                 command.hasSuffix("/Contents/MacOS/微信")
            guard isWeChatBinary else { continue }

            let bundle = command
                .replacingOccurrences(of: "/Contents/MacOS/WeChat", with: "")
                .replacingOccurrences(of: "/Contents/MacOS/微信", with: "")

            // Defend against WeChat's nested helper bundle, which technically
            // has the path …/WeChat.app/Contents/MacOS/WeChatAppEx.app — the
            // suffix check above already filters this, but be doubly safe by
            // requiring the bundle to end with a .app component we recognize.
            let bundleName = (bundle as NSString).lastPathComponent
            guard bundleName.hasSuffix(".app") else { continue }

            // Categorize: clone (under our cloneRoot, name "WeChat <N>.app")
            // or the original (anywhere else, typically /Applications/WeChat.app).
            if bundle.hasPrefix(cloneRootPath) {
                // Clone naming convention: "WeChat <N>.app". Anything that
                // matches the prefix+suffix but doesn't have a parseable slot
                // number is treated as a stray and skipped.
                let trimmedName = bundleName
                    .dropFirst("WeChat ".count)
                    .dropLast(".app".count)
                guard bundleName.hasPrefix("WeChat "),
                      let slot = Int(trimmedName), slot > 0 else { continue }
                results.append(InstanceInfo(slot: slot, pid: pid,
                                             startTime: startTime, bundlePath: bundle))
            } else if bundleName == "WeChat.app" || bundleName == "微信.app" {
                // The original /Applications/WeChat.app (slot 0).
                results.append(InstanceInfo(slot: 0, pid: pid,
                                             startTime: startTime, bundlePath: bundle))
            }
        }
        return results.sorted { $0.slot < $1.slot }
    }

    func quitAll() {
        _ = run("/usr/bin/killall", ["WeChat"])
    }

    func quitInstance(pid: Int32) {
        kill(pid, SIGTERM)
    }

    func revealInstance(pid: Int32) {
        let script = """
        tell application "System Events"
            set frontmost of (first process whose unix id is \(pid)) to true
        end tell
        """
        _ = run("/usr/bin/osascript", ["-e", script])
    }

    // MARK: - Helpers

    /// Runs a subprocess synchronously and returns an error description on non-zero exit,
    /// or nil on success.
    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments

        let errPipe = Pipe()
        task.standardOutput = FileHandle.nullDevice
        task.standardError = errPipe

        do {
            try task.run()
        } catch {
            return error.localizedDescription
        }

        // Drain stderr before waitUntilExit to avoid pipe-buffer deadlock.
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let msg = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit code \(task.terminationStatus)"
            return msg.isEmpty ? "exit code \(task.terminationStatus)" : msg
        }
        return nil
    }
}
