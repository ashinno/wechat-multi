import XCTest
@testable import WeChatMultiCore

/// In-memory `SnapshotStore` for deterministic tests — no disk access.
final class InMemorySnapshotStore: SnapshotStore {
    var files: [String: Data] = [:]

    func writeSnapshot(_ data: Data, id: String) throws { files[id] = data }

    func readSnapshot(id: String) throws -> Data {
        guard let data = files[id] else {
            throw NSError(domain: "InMemorySnapshotStore", code: 404)
        }
        return data
    }

    func snapshotIDs() -> [String] { Array(files.keys) }

    func removeSnapshot(id: String) throws { files.removeValue(forKey: id) }
}

final class SettingsSnapshotsTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let appVersion = "2.0.0"

    private func store(names: [String: String] = ["1": "Work"],
                       order: [Int] = [1]) -> InMemoryKeyValueStore {
        let kv = InMemoryKeyValueStore()
        kv.set(names, forKey: DefaultsKey.slotNames)
        kv.set(order, forKey: DefaultsKey.slotDisplayOrder)
        return kv
    }

    // MARK: - ID ⇄ Date

    func testMakeIDAndParseRoundTrip() {
        let id = SettingsSnapshots.makeID(at: t0)
        XCTAssertTrue(id.hasPrefix("wechatmulti-settings-"))
        XCTAssertTrue(id.hasSuffix(".json"))
        let parsed = SettingsSnapshots.date(fromID: id)
        XCTAssertNotNil(parsed)
        // makeID is second-resolution; t0 is on an integer second.
        XCTAssertEqual(parsed!.timeIntervalSince1970, t0.timeIntervalSince1970, accuracy: 1)
    }

    func testParseRejectsJunkIDs() {
        XCTAssertNil(SettingsSnapshots.date(fromID: "garbage"))
        XCTAssertNil(SettingsSnapshots.date(fromID: "wechatmulti-settings-notadate.json"))
        XCTAssertNil(SettingsSnapshots.date(fromID: "other-prefix-20260101T000000Z.json"))
    }

    // MARK: - Capture

    func testCaptureWritesWhenEmpty() throws {
        let kv = store()
        let snaps = InMemorySnapshotStore()
        let outcome = try SettingsSnapshots.capture(from: kv, appVersion: appVersion, now: t0, into: snaps)
        guard case .wrote = outcome else { return XCTFail("expected .wrote, got \(outcome)") }
        XCTAssertEqual(snaps.files.count, 1)
    }

    func testCaptureDedupsUnchangedSettings() throws {
        let kv = store()
        let snaps = InMemorySnapshotStore()
        _ = try SettingsSnapshots.capture(from: kv, appVersion: appVersion, now: t0, into: snaps)
        // Same settings, much later, no throttle → still a no-op.
        let outcome = try SettingsSnapshots.capture(
            from: kv, appVersion: appVersion, now: t0.addingTimeInterval(100_000), into: snaps)
        XCTAssertEqual(outcome, .skippedUnchanged)
        XCTAssertEqual(snaps.files.count, 1)
    }

    func testCaptureIfDueThrottlesRecentChanges() throws {
        let kv = store()
        let snaps = InMemorySnapshotStore()
        _ = try SettingsSnapshots.capture(from: kv, appVersion: appVersion, now: t0, into: snaps)
        // Change the settings, but only 60s later with a 1h interval.
        kv.set(["1": "Work", "2": "Personal"], forKey: DefaultsKey.slotNames)
        let outcome = try SettingsSnapshots.captureIfDue(
            from: kv, appVersion: appVersion, now: t0.addingTimeInterval(60),
            into: snaps, minInterval: 3600)
        XCTAssertEqual(outcome, .skippedThrottled)
        XCTAssertEqual(snaps.files.count, 1)
    }

    func testCaptureIfDueWritesAfterInterval() throws {
        let kv = store()
        let snaps = InMemorySnapshotStore()
        _ = try SettingsSnapshots.capture(from: kv, appVersion: appVersion, now: t0, into: snaps)
        kv.set(["1": "Work", "2": "Personal"], forKey: DefaultsKey.slotNames)
        let outcome = try SettingsSnapshots.captureIfDue(
            from: kv, appVersion: appVersion, now: t0.addingTimeInterval(7200),
            into: snaps, minInterval: 3600)
        guard case .wrote = outcome else { return XCTFail("expected .wrote, got \(outcome)") }
        XCTAssertEqual(snaps.files.count, 2)
    }

    // MARK: - Listing & pruning

    func testListIsNewestFirst() throws {
        let kv = store()
        let snaps = InMemorySnapshotStore()
        for i in 0..<3 {
            kv.set(["1": "Name\(i)"], forKey: DefaultsKey.slotNames)
            _ = try SettingsSnapshots.capture(
                from: kv, appVersion: appVersion, now: t0.addingTimeInterval(Double(i) * 3600), into: snaps)
        }
        let list = SettingsSnapshots.list(in: snaps)
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list.first?.createdAt, t0.addingTimeInterval(2 * 3600))
        XCTAssertEqual(list.last?.createdAt, t0)
    }

    func testCapturePrunesToMaxSnapshots() throws {
        let kv = store()
        let snaps = InMemorySnapshotStore()
        for i in 0..<20 {
            kv.set(["1": "Name\(i)"], forKey: DefaultsKey.slotNames)   // change each time
            _ = try SettingsSnapshots.capture(
                from: kv, appVersion: appVersion, now: t0.addingTimeInterval(Double(i) * 3600),
                into: snaps, maxSnapshots: 5)
        }
        XCTAssertEqual(snaps.files.count, 5)
        // The five kept are the newest (i = 15…19).
        let list = SettingsSnapshots.list(in: snaps)
        XCTAssertEqual(list.first?.createdAt, t0.addingTimeInterval(19 * 3600))
        XCTAssertEqual(list.last?.createdAt, t0.addingTimeInterval(15 * 3600))
    }

    func testListIgnoresUnparseableFiles() throws {
        let kv = store()
        let snaps = InMemorySnapshotStore()
        _ = try SettingsSnapshots.capture(from: kv, appVersion: appVersion, now: t0, into: snaps)
        snaps.files["not-a-snapshot.txt"] = Data("hi".utf8)
        XCTAssertEqual(SettingsSnapshots.list(in: snaps).count, 1)
    }

    // MARK: - Restore (the headline: recover from a mistake)

    func testRestoreRecoversPreviousState() throws {
        let kv = store(names: ["1": "Work"], order: [1])
        kv.set("/Applications/WeChat.app", forKey: DefaultsKey.customWeChatPath)
        let snaps = InMemorySnapshotStore()

        let outcome = try SettingsSnapshots.capture(from: kv, appVersion: appVersion, now: t0, into: snaps)
        guard case let .wrote(id) = outcome else { return XCTFail("expected .wrote") }

        // Disaster: a bad import wipes the settings.
        kv.set([String: String](), forKey: DefaultsKey.slotNames)
        kv.removeObject(forKey: DefaultsKey.slotDisplayOrder)

        // Roll back from the snapshot.
        try SettingsSnapshots.restore(id: id, from: snaps, to: kv, pathExists: { _ in true })

        XCTAssertEqual(kv.dictionary(forKey: DefaultsKey.slotNames) as? [String: String], ["1": "Work"])
        XCTAssertEqual(kv.array(forKey: DefaultsKey.slotDisplayOrder) as? [Int], [1])
        XCTAssertEqual(kv.string(forKey: DefaultsKey.customWeChatPath), "/Applications/WeChat.app")
    }

    func testRestoreFromMissingIDThrows() {
        let snaps = InMemorySnapshotStore()
        XCTAssertThrowsError(
            try SettingsSnapshots.restore(id: "wechatmulti-settings-20260101T000000Z.json",
                                          from: snaps, to: InMemoryKeyValueStore()))
    }
}
