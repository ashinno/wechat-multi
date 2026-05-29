import XCTest
@testable import WeChatMultiCore

final class SlotSettingsTests: XCTestCase {

    private func makeSettings() -> (SlotSettings, InMemoryKeyValueStore) {
        let store = InMemoryKeyValueStore()
        return (SlotSettings(store: store), store)
    }

    // MARK: - Names

    func testSetGetClearName() {
        let (s, _) = makeSettings()
        XCTAssertNil(s.name(forSlot: 1))
        s.setName("Work", forSlot: 1)
        XCTAssertEqual(s.name(forSlot: 1), "Work")
        s.setName(nil, forSlot: 1)
        XCTAssertNil(s.name(forSlot: 1))
    }

    func testBlankNameClears() {
        let (s, _) = makeSettings()
        s.setName("Work", forSlot: 1)
        s.setName("   ", forSlot: 1)   // whitespace-only → cleared
        XCTAssertNil(s.name(forSlot: 1))
    }

    func testSlotZeroNeverNamed() {
        let (s, _) = makeSettings()
        s.setName("Main", forSlot: 0)
        XCTAssertNil(s.name(forSlot: 0))
        XCTAssertTrue(s.allNames().isEmpty)
    }

    func testDisplayNameFallback() {
        let (s, _) = makeSettings()
        XCTAssertEqual(s.displayName(forSlot: 2), "WeChat 2")
        s.setName("Personal", forSlot: 2)
        XCTAssertEqual(s.displayName(forSlot: 2), "Personal")
    }

    func testNamesPersistAcrossInstancesOfSameStore() {
        let store = InMemoryKeyValueStore()
        SlotSettings(store: store).setName("Work", forSlot: 1)
        // A fresh SlotSettings over the same store sees the value.
        XCTAssertEqual(SlotSettings(store: store).name(forSlot: 1), "Work")
    }

    func testIndependentSlotsDoNotInterfere() {
        let (s, _) = makeSettings()
        s.setName("Work", forSlot: 1)
        s.setName("Personal", forSlot: 2)
        s.setName(nil, forSlot: 1)
        XCTAssertNil(s.name(forSlot: 1))
        XCTAssertEqual(s.name(forSlot: 2), "Personal")
    }

    // MARK: - Display order

    func testOrderRoundTrip() {
        let (s, _) = makeSettings()
        XCTAssertEqual(s.displayOrder(), [])
        s.setDisplayOrder([3, 1, 2])
        XCTAssertEqual(s.displayOrder(), [3, 1, 2])
    }

    func testMoveSlotPersists() {
        let (s, _) = makeSettings()
        s.setDisplayOrder([1, 2, 3])
        s.moveSlot(3, before: 1)
        XCTAssertEqual(s.displayOrder(), [3, 1, 2])
    }

    func testMaterializeAppendsMissingPreservingExisting() {
        let (s, _) = makeSettings()
        s.setDisplayOrder([2])
        let result = s.materialize(present: [0, 1, 2, 3])
        XCTAssertEqual(result, [2, 0, 1, 3])
        XCTAssertEqual(s.displayOrder(), [2, 0, 1, 3])
    }

    func testMaterializeFromEmpty() {
        let (s, _) = makeSettings()
        XCTAssertEqual(s.materialize(present: [0, 1, 2]), [0, 1, 2])
    }

    // MARK: - Concurrency (the race this lock exists to prevent)

    func testConcurrentNameWritesDoNotCorrupt() {
        let (s, _) = makeSettings()
        let group = DispatchGroup()
        // 100 concurrent writes across 10 slots from many queues.
        for i in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                s.setName("name-\(i)", forSlot: (i % 10) + 1)
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        // Every one of the 10 slots must have *some* well-formed value — no
        // torn dictionary, no crash, exactly 10 keys.
        XCTAssertEqual(s.allNames().count, 10)
        for slot in 1...10 {
            XCTAssertTrue(s.name(forSlot: slot)?.hasPrefix("name-") ?? false)
        }
    }
}
