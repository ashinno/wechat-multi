import Foundation

/// The naming conventions that tie a slot number to its on-disk bundle and
/// sandbox identity. Centralized + pure so the round-trip
/// (slot → folder name → slot) is unit-tested and can never silently drift.
public enum CloneNaming {
    /// Bundle identifier written into a clone's Info.plist. This is what gives
    /// each clone its own sandbox container, so it must be stable forever —
    /// changing the scheme would orphan every existing signed-in session.
    public static func bundleID(forSlot slot: Int) -> String {
        "com.wechatmulti.clone\(slot)"
    }

    /// On-disk bundle folder name, e.g. "WeChat 3.app".
    public static func folderName(forSlot slot: Int) -> String {
        "WeChat \(slot).app"
    }

    private static let folderPattern = try! NSRegularExpression(
        pattern: #"^WeChat (\d+)\.app$"#
    )

    /// Parse a slot number out of a clone folder name, or nil if it doesn't
    /// match the convention (strays, the nested WeChatAppEx.app, etc.).
    public static func parseSlot(fromFolderName name: String) -> Int? {
        let range = NSRange(name.startIndex..., in: name)
        guard let match = folderPattern.firstMatch(in: name, range: range),
              match.numberOfRanges == 2,
              let r = Range(match.range(at: 1), in: name),
              let slot = Int(name[r]), slot > 0
        else { return nil }
        return slot
    }
}
