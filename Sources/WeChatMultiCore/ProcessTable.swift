import Foundation

/// Pure parser for `ps -axo pid=,lstart=,comm=` output. Extracted from
/// WeChatLauncher.runningInstances so the trickiest, most bug-prone logic in
/// the app can be unit-tested against fixture strings.
///
/// Robustness note: the old code assumed `lstart` is exactly 5 whitespace
/// tokens ("Sat May 17 10:42:03 2026"). That's true under the C locale but
/// fragile. This parser instead anchors on the first token that begins with
/// "/" — neither the PID nor any `lstart` token contains a slash, but the
/// command (an absolute executable path) always does. The start-time is
/// whatever sits between the PID and the command, rejoined verbatim.
public enum ProcessTable {
    public struct Instance: Equatable {
        public let slot: Int          // 0 = the original /Applications/WeChat.app
        public let pid: Int32
        public let startTime: String
        public let bundlePath: String

        public init(slot: Int, pid: Int32, startTime: String, bundlePath: String) {
            self.slot = slot
            self.pid = pid
            self.startTime = startTime
            self.bundlePath = bundlePath
        }
    }

    /// Parse every WeChat *main* process out of `ps` output. `cloneRootPath` is
    /// the absolute path of `~/Applications/WeChat Multi` so we can classify a
    /// process as a clone (and recover its slot) vs. the original install.
    /// Results are sorted by slot ascending.
    public static func parseInstances(psOutput: String, cloneRootPath: String) -> [Instance] {
        var results: [Instance] = []

        for rawLine in psOutput.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
            guard tokens.count >= 3, let pid = Int32(tokens[0]) else { continue }

            // Command begins at the first token starting with "/".
            guard let cmdStart = tokens.firstIndex(where: { $0.hasPrefix("/") }),
                  cmdStart >= 2 else { continue }   // need ≥1 lstart token between

            let startTime = tokens[1..<cmdStart].joined(separator: " ")
            let command = tokens[cmdStart...].joined(separator: " ")

            // Must be the main WeChat executable. WeChat ships helper binaries
            // (WeChatAppEx, WeChatPlugin, crashpad_handler) inside nested .app
            // bundles, none named exactly "WeChat"/"微信", so this excludes them.
            let isWeChatBinary = command.hasSuffix("/Contents/MacOS/WeChat")
                              || command.hasSuffix("/Contents/MacOS/微信")
            guard isWeChatBinary else { continue }

            let bundle = command
                .replacingOccurrences(of: "/Contents/MacOS/WeChat", with: "")
                .replacingOccurrences(of: "/Contents/MacOS/微信", with: "")

            let bundleName = (bundle as NSString).lastPathComponent
            guard bundleName.hasSuffix(".app") else { continue }

            if bundle.hasPrefix(cloneRootPath) {
                // A clone: recover its slot from the folder name.
                guard let slot = CloneNaming.parseSlot(fromFolderName: bundleName) else { continue }
                results.append(Instance(slot: slot, pid: pid,
                                        startTime: startTime, bundlePath: bundle))
            } else if bundleName == "WeChat.app" || bundleName == "微信.app" {
                results.append(Instance(slot: 0, pid: pid,
                                        startTime: startTime, bundlePath: bundle))
            }
            // Anything else (a WeChat binary in some unexpected location) is ignored.
        }

        return results.sorted { $0.slot < $1.slot }
    }
}
