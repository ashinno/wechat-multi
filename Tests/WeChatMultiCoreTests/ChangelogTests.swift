import XCTest
@testable import WeChatMultiCore

final class ChangelogTests: XCTestCase {

    func testEntriesAreNewestFirstAndWellFormed() {
        let entries = Changelog.entries
        XCTAssertFalse(entries.isEmpty)
        // Strictly descending by version.
        for i in 1..<entries.count {
            XCTAssertTrue(SemVer(entries[i - 1].version) > SemVer(entries[i].version),
                          "\(entries[i-1].version) should be newer than \(entries[i].version)")
        }
        // Each entry has a highlight and at least one bullet, none empty.
        for e in entries {
            XCTAssertFalse(e.highlight.isEmpty)
            XCTAssertFalse(e.bullets.isEmpty)
            XCTAssertTrue(e.bullets.allSatisfy { !$0.isEmpty })
        }
    }

    func testNewestEntryMatchesShippingVersion() {
        // The top changelog entry should be the current release (2.0.0).
        XCTAssertEqual(Changelog.entries.first?.version, "2.0.0")
    }

    func testEntriesNewerThanFiltersAndCaps() {
        // From a very old version, capped at 2 → the two newest entries.
        let newer = Changelog.entriesNewer(than: "0.0.0", limit: 2)
        XCTAssertEqual(newer.count, 2)
        XCTAssertEqual(newer.map(\.version), ["2.0.0", "1.8.0"])
    }

    func testEntriesNewerThanCurrentIsEmpty() {
        let top = Changelog.entries.first!.version
        XCTAssertTrue(Changelog.entriesNewer(than: top).isEmpty)
        // And a future version is also empty.
        XCTAssertTrue(Changelog.entriesNewer(than: "99.0.0").isEmpty)
    }

    func testEntriesNewerSkipsSeenVersions() {
        // User last saw 1.8.0 → only strictly-newer entries surface.
        let newer = Changelog.entriesNewer(than: "1.8.0")
        XCTAssertEqual(newer.map(\.version), ["2.0.0"])
    }
}
