import Foundation
import AppKit
import WeChatMultiCore

/// Manages cloned WeChat.app bundles so multiple WeChat instances can run side
/// by side. WeChat on macOS enforces a singleton via its CFBundleIdentifier;
/// each clone gets a unique bundle ID (hence its own sandbox container), which
/// bypasses the check.
///
/// As of v2.0 this is a thin orchestrator: the bug-prone *pure* logic (ps
/// parsing, slot ordering, naming, versioning, backup) lives in the tested
/// `WeChatMultiCore` library. This type owns the filesystem + process side.
final class WeChatLauncher {

    // MARK: - Configuration

    private let store: KeyValueStore
    private let slots: SlotSettings
    private let snapshots: SnapshotStore

    private let defaultPaths = [
        "/Applications/WeChat.app",
        "/Applications/微信.app",
        "\(NSHomeDirectory())/Applications/WeChat.app"
    ]

    /// Directory that holds the cloned bundles.
    let cloneRoot: URL

    init(store: KeyValueStore = UserDefaults.standard,
         cloneRoot: URL? = nil,
         snapshotStore: SnapshotStore? = nil) {
        self.store = store
        self.slots = SlotSettings(store: store)
        self.snapshots = snapshotStore ?? DirectorySnapshotStore()
        self.cloneRoot = cloneRoot ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/WeChat Multi", isDirectory: true)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var wechatAppPath: String? {
        if let custom = store.string(forKey: DefaultsKey.customWeChatPath),
           FileManager.default.fileExists(atPath: custom) {
            return custom
        }
        return defaultPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Sets a custom WeChat.app location. Returns false (and does nothing) if
    /// the path doesn't contain a WeChat executable — defense in depth on top
    /// of the Preferences picker's own validation.
    @discardableResult
    func setCustomPath(_ path: String) -> Bool {
        guard Self.isWeChatBundle(path) else { return false }
        store.set(path, forKey: DefaultsKey.customWeChatPath)
        return true
    }

    func clearCustomPath() {
        store.removeObject(forKey: DefaultsKey.customWeChatPath)
    }

    static func isWeChatBundle(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: "\(path)/Contents/MacOS/WeChat") ||
        FileManager.default.fileExists(atPath: "\(path)/Contents/MacOS/微信")
    }

    // MARK: - Custom slot names (delegated to thread-safe SlotSettings)

    func slotName(slot: Int) -> String? { slots.name(forSlot: slot) }
    func setSlotName(slot: Int, name: String?) { slots.setName(name, forSlot: slot) }
    func cloneDisplayName(slot: Int) -> String { slots.displayName(forSlot: slot) }

    // MARK: - Per-slot colors

    func slotColor(slot: Int) -> NSColor {
        if slot == 0 {
            return NSColor(srgbRed: 0.027, green: 0.757, blue: 0.376, alpha: 1.0)
        }
        let palette: [NSColor] = [
            .systemBlue, .systemPurple, .systemOrange, .systemPink,
            .systemTeal, .systemIndigo, .systemRed, .systemYellow
        ]
        return palette[(abs(slot) - 1) % palette.count]
    }

    func slotDotImage(slot: Int, size: CGFloat = 14) -> NSImage {
        let color = slotColor(slot: slot)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    // MARK: - Version detection

    func wechatAppVersion() -> String? {
        guard let appPath = wechatAppPath else { return nil }
        return readPlistString(at: "\(appPath)/Contents/Info.plist",
                               key: "CFBundleShortVersionString")
    }

    func cloneVersion(slot: Int) -> String? {
        let plist = cloneURL(for: slot).appendingPathComponent("Contents/Info.plist").path
        return readPlistString(at: plist, key: "CFBundleShortVersionString")
    }

    /// Slots whose on-disk clone version differs from the current WeChat.app.
    func staleClones() -> [Int] {
        guard let sourceVersion = wechatAppVersion() else { return [] }
        return existingCloneSlots().filter { slot in
            guard let cloneVer = cloneVersion(slot: slot) else { return true }
            return SemVer(cloneVer) != SemVer(sourceVersion)
        }
    }

    func runningSlotsBlocking(_ slots: [Int]) -> [Int] {
        let running = Set(runningInstances().map(\.slot))
        return slots.filter { running.contains($0) }
    }

    private func readPlistString(at path: String, key: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist[key] as? String
    }

    // MARK: - Clone management

    enum PrepareResult {
        case ready(URL)
        case sourceMissing
        case failed(String)
    }

    typealias ProgressCallback = (_ stage: String) -> Void

    func cloneURL(for slot: Int) -> URL {
        cloneRoot.appendingPathComponent(CloneNaming.folderName(forSlot: slot), isDirectory: true)
    }

    func cloneBundleID(for slot: Int) -> String {
        CloneNaming.bundleID(forSlot: slot)
    }

    func cloneExists(slot: Int) -> Bool {
        FileManager.default.fileExists(atPath: cloneURL(for: slot).path)
    }

    /// Materializes a clone if it doesn't already exist. **Atomic**: the bundle
    /// is copied + configured in a temporary location and only moved into its
    /// final path once fully ready. A failure anywhere cleans up the temp and
    /// leaves no half-configured bundle behind (the old code could leave a
    /// broken bundle that `cloneExists` reported as ready).
    func prepareClone(slot: Int, progress: ProgressCallback? = nil) -> PrepareResult {
        guard let source = wechatAppPath else { return .sourceMissing }
        let target = cloneURL(for: slot)

        if FileManager.default.fileExists(atPath: target.path) {
            return .ready(target)
        }

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: cloneRoot, withIntermediateDirectories: true)
        } catch {
            return .failed("Could not create clones directory: \(error.localizedDescription)")
        }

        purgeStaleTempBundles()

        // Temp lives in the same directory (same APFS volume) so the copy is a
        // cheap copy-on-write clone and the final move is an atomic rename.
        let temp = cloneRoot.appendingPathComponent(
            ".\(CloneNaming.folderName(forSlot: slot)).tmp-\(UUID().uuidString)",
            isDirectory: true
        )

        func cleanup() { try? fm.removeItem(at: temp) }

        progress?("Copying WeChat.app (one-time setup)…")
        if let copyError = run("/bin/cp", ["-Rc", source, temp.path]) {
            cleanup()
            return .failed("Copying WeChat.app failed: \(copyError)")
        }

        progress?("Configuring & re-signing…")
        if let writeError = writeIdentityToBundle(at: temp, slot: slot) {
            cleanup()
            return .failed(writeError)
        }

        // Re-check target right before the move — another launch may have won
        // the race and created it. If so, keep theirs and discard ours.
        if fm.fileExists(atPath: target.path) {
            cleanup()
            return .ready(target)
        }
        do {
            try fm.moveItem(at: temp, to: target)
        } catch {
            cleanup()
            return .failed("Could not finalize clone: \(error.localizedDescription)")
        }
        return .ready(target)
    }

    /// Removes any leftover `.WeChat N.app.tmp-*` dirs from interrupted prepares.
    private func purgeStaleTempBundles() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cloneRoot, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.lastPathComponent.hasPrefix(".WeChat ")
            && url.lastPathComponent.contains(".tmp-") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @discardableResult
    func renameClone(slot: Int, newName: String?) -> String? {
        setSlotName(slot: slot, name: newName)
        guard cloneExists(slot: slot) else { return nil }
        return writeIdentityToBundle(at: cloneURL(for: slot), slot: slot)
    }

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

    /// Writes our identity (bundle ID + display name) into a bundle's Info.plist,
    /// drops the now-invalid signature, and ad-hoc re-signs.
    private func writeIdentityToBundle(at target: URL, slot: Int) -> String? {
        let plist = target.appendingPathComponent("Contents/Info.plist").path
        let bundleID = cloneBundleID(for: slot)
        let displayName = cloneDisplayName(slot: slot)
        let plistBuddy = "/usr/libexec/PlistBuddy"

        _ = run(plistBuddy, ["-c", "Set :CFBundleIdentifier \(bundleID)", plist])
        _ = run(plistBuddy, ["-c", "Set :CFBundleName \(displayName)", plist])
        if run(plistBuddy, ["-c", "Set :CFBundleDisplayName \(displayName)", plist]) != nil {
            _ = run(plistBuddy, ["-c", "Add :CFBundleDisplayName string \(displayName)", plist])
        }

        try? FileManager.default.removeItem(
            at: target.appendingPathComponent("Contents/_CodeSignature"))

        if let signError = run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", target.path]) {
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
        setSlotName(slot: slot, name: nil)
        if removeSandboxContainer {
            try? FileManager.default.removeItem(at: sandboxContainerURL(slot: slot))
        }
        return nil
    }

    func sandboxContainerExists(slot: Int) -> Bool {
        guard slot > 0 else { return false }
        return FileManager.default.fileExists(atPath: sandboxContainerURL(slot: slot).path)
    }

    private func sandboxContainerURL(slot: Int) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(cloneBundleID(for: slot))")
    }

    func existingCloneSlots() -> [Int] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cloneRoot, includingPropertiesForKeys: nil) else { return [] }
        return entries
            .compactMap { CloneNaming.parseSlot(fromFolderName: $0.lastPathComponent) }
            .sorted()
    }

    // MARK: - Launching

    enum LaunchResult {
        case launched(slot: Int)
        case sourceMissing
        case failed(String)
    }

    func launchNextAvailableInstance(progress: ProgressCallback? = nil) -> LaunchResult {
        let running = Set(runningInstances().map { $0.slot })
        var slot = 1
        while running.contains(slot) { slot += 1 }
        return launchSpecificInstance(slot: slot, progress: progress)
    }

    func slotNeedsPreparation(slot: Int) -> Bool { !cloneExists(slot: slot) }

    func launchSpecificInstance(slot: Int, progress: ProgressCallback? = nil) -> LaunchResult {
        switch prepareClone(slot: slot, progress: progress) {
        case .sourceMissing: return .sourceMissing
        case .failed(let reason): return .failed(reason)
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
        let slot: Int
        let pid: Int32
        let startTime: String
        let bundlePath: String
    }

    /// Spawns `ps` and hands its output to the tested `ProcessTable` parser.
    func runningInstances() -> [InstanceInfo] {
        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,lstart=,comm="]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do { try task.run() } catch { return [] }

        // Drain before waitUntilExit to avoid pipe-buffer deadlock.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return ProcessTable
            .parseInstances(psOutput: output, cloneRootPath: cloneRoot.path)
            .map { InstanceInfo(slot: $0.slot, pid: $0.pid,
                                startTime: $0.startTime, bundlePath: $0.bundlePath) }
    }

    func quitAll() { _ = run("/usr/bin/killall", ["WeChat"]) }
    func quitInstance(pid: Int32) { kill(pid, SIGTERM) }

    func revealInstance(pid: Int32) {
        let script = """
        tell application "System Events"
            set frontmost of (first process whose unix id is \(pid)) to true
        end tell
        """
        _ = run("/usr/bin/osascript", ["-e", script])
    }

    // MARK: - Slot display order (delegated to thread-safe SlotSettings)

    func slotDisplayOrder() -> [Int] { slots.displayOrder() }
    func setSlotDisplayOrder(_ order: [Int]) { slots.setDisplayOrder(order) }
    func moveSlot(_ slot: Int, before targetSlot: Int?) { slots.moveSlot(slot, before: targetSlot) }
    @discardableResult
    func materializeDisplayOrder(present: [Int]) -> [Int] { slots.materialize(present: present) }

    // MARK: - Health check

    struct HealthIssue: Equatable {
        let slot: Int
        let summary: String
    }

    /// Confirms each clone is intact: binary present + executable, bundle ID
    /// matches, and `codesign --verify` passes. Synchronous — run off-main.
    func healthCheck() -> [HealthIssue] {
        var issues: [HealthIssue] = []
        for slot in existingCloneSlots() {
            let bundle = cloneURL(for: slot)
            let binary = bundle.appendingPathComponent("Contents/MacOS/WeChat").path

            if !FileManager.default.fileExists(atPath: binary) {
                issues.append(HealthIssue(slot: slot, summary: "Missing main executable")); continue
            }
            if !FileManager.default.isExecutableFile(atPath: binary) {
                issues.append(HealthIssue(slot: slot, summary: "Main executable is not executable")); continue
            }
            let plistPath = bundle.appendingPathComponent("Contents/Info.plist").path
            let actualID = readPlistString(at: plistPath, key: "CFBundleIdentifier")
            let expectedID = cloneBundleID(for: slot)
            if actualID != expectedID {
                issues.append(HealthIssue(
                    slot: slot,
                    summary: actualID == nil ? "Info.plist unreadable"
                                             : "Bundle identifier drifted (\(actualID!) ≠ \(expectedID))"
                )); continue
            }
            if runStatus("/usr/bin/codesign", ["--verify", "--verbose=0", bundle.path]) != 0 {
                issues.append(HealthIssue(slot: slot, summary: "Code signature failed verification"))
            }
        }
        return issues
    }

    // MARK: - Backup / restore (delegated to tested SettingsBackup)

    func exportSettingsData() throws -> Data {
        try SettingsBackup.exportData(store: store, appVersion: appVersion)
    }

    func importSettings(from data: Data) throws {
        // Snapshot the current state first so a regretted import is recoverable.
        try? SettingsSnapshots.capture(from: store, appVersion: appVersion, into: snapshots)
        try SettingsBackup.restore(from: data, to: store)
    }

    // MARK: - Automatic settings snapshots (rotating, tested SettingsSnapshots)

    /// Take a throttled snapshot of the current settings. Safe to call on every
    /// launch — it dedups identical state and rate-limits to one per interval.
    /// Failures are swallowed: a backup that can't be written must never block
    /// the app from starting.
    func captureSettingsSnapshotIfDue() {
        try? SettingsSnapshots.captureIfDue(from: store, appVersion: appVersion, into: snapshots)
    }

    /// Available settings snapshots, newest first.
    func settingsSnapshots() -> [SnapshotInfo] {
        SettingsSnapshots.list(in: snapshots)
    }

    /// Roll the live settings back to a chosen snapshot.
    func restoreSettingsSnapshot(id: String) throws {
        try SettingsSnapshots.restore(id: id, from: snapshots, to: store)
    }

    // MARK: - Process helpers

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        let errPipe = Pipe()
        task.standardOutput = FileHandle.nullDevice
        task.standardError = errPipe
        do { try task.run() } catch { return error.localizedDescription }

        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let msg = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit code \(task.terminationStatus)"
            return msg.isEmpty ? "exit code \(task.terminationStatus)" : msg
        }
        return nil
    }

    private func runStatus(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit(); return task.terminationStatus }
        catch { return -1 }
    }
}
