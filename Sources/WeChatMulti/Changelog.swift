import Foundation

/// Per-version changelog entries shown by `WhatsNewView` the first time the
/// user launches a new bundle version. Entries are listed newest-first.
///
/// When you ship a new release: prepend a new `Entry` here. Bullets are
/// short — full prose belongs on the GitHub release page (linked from the
/// panel's footer).
enum Changelog {
    struct Entry: Identifiable {
        let version: String
        let highlight: String        // one-line summary shown as panel title
        let bullets: [String]        // 3-6 bullets max
        var id: String { version }
    }

    /// Newest version is at index 0. Show every entry whose version is newer
    /// than the user's last-seen version, capped at 3 entries.
    static let entries: [Entry] = [
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
}
