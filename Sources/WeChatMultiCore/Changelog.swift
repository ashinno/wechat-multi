import Foundation

/// Per-version changelog entries shown by the What's New panel the first time
/// the user launches a new bundle version. Newest-first.
///
/// When shipping a release: prepend a new `Entry`. Bullets stay short — full
/// prose belongs on the GitHub release page (linked from the panel footer).
public enum Changelog {
    public struct Entry: Identifiable, Equatable {
        public let version: String
        public let highlight: String     // one-line summary shown as panel title
        public let bullets: [String]     // 3–6 bullets max
        public var id: String { version }

        public init(version: String, highlight: String, bullets: [String]) {
            self.version = version
            self.highlight = highlight
            self.bullets = bullets
        }
    }

    public static let entries: [Entry] = [
        Entry(
            version: "2.0.0",
            highlight: "Rebuilt on a tested foundation",
            bullets: [
                "Extracted a pure WeChatMultiCore library with a full unit-test suite — the clone engine, ps parser, ordering, and backup logic are now verified on every CI run",
                "Hardened cloning: prepared atomically in a temp location so a failure never leaves a half-configured bundle",
                "Fixed a race on slot names/order across background queues; settings access is now serialized",
                "More robust running-instance detection (locale-independent ps parsing)",
                "Centralized all stored settings keys; safer backup import with validation"
            ]
        ),
        Entry(
            version: "1.8.0",
            highlight: "Friendlier & more discoverable",
            bullets: [
                "Keyboard navigation in the popover — ↑/↓ to move, Return to launch/focus, Delete to remove a slot",
                "System notifications when a new instance finishes preparing — no more wondering if it worked",
                "Jade dot overlay on the menubar icon when something's running",
                "Tooltips on every button across the popover, Preferences, and About",
                "This very panel — shows changes automatically when the app updates"
            ]
        ),
        Entry(
            version: "1.7.0",
            highlight: "Drag-to-reorder, health check, backup & restore",
            bullets: [
                "Drag rows in the popover to reorder; slot numbers stay tied to your sandbox",
                "Health check runs every 5 minutes; offers Repair if a clone drifts",
                "Export / import preferences as JSON for new-Mac migration"
            ]
        )
    ]

    /// Entries strictly newer than `version`, newest-first, capped at `limit`.
    /// Pure replacement for the filtering AppDelegate used to do inline.
    public static func entriesNewer(than version: String, limit: Int = 3) -> [Entry] {
        let base = SemVer(version)
        return entries
            .filter { SemVer($0.version) > base }
            .prefix(limit)
            .map { $0 }
    }
}
