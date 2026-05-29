import XCTest
@testable import WeChatMultiCore

final class SlotOrderingTests: XCTestCase {

    // MARK: - reorder

    func testMoveBeforeTarget() {
        XCTAssertEqual(SlotOrdering.reorder([1, 2, 3], moving: 3, before: 1), [3, 1, 2])
        XCTAssertEqual(SlotOrdering.reorder([1, 2, 3], moving: 1, before: 3), [2, 1, 3])
    }

    func testMoveToEndWhenTargetNil() {
        XCTAssertEqual(SlotOrdering.reorder([1, 2, 3], moving: 1, before: nil), [2, 3, 1])
    }

    func testMoveToEndWhenTargetMissing() {
        // Target not present → append at end.
        XCTAssertEqual(SlotOrdering.reorder([1, 2, 3], moving: 2, before: 99), [1, 3, 2])
    }

    func testNoOpWhenMovingOntoItself() {
        XCTAssertEqual(SlotOrdering.reorder([1, 2, 3], moving: 2, before: 2), [1, 2, 3])
    }

    func testMovingSlotNotInList() {
        // Slot 5 isn't present; it gets inserted before the target.
        XCTAssertEqual(SlotOrdering.reorder([1, 2, 3], moving: 5, before: 2), [1, 5, 2, 3])
    }

    func testReorderDoesNotDuplicate() {
        let result = SlotOrdering.reorder([0, 1, 2], moving: 0, before: 2)
        XCTAssertEqual(result, [1, 0, 2])
        XCTAssertEqual(Set(result).count, result.count)
    }

    // MARK: - resolve

    func testResolveHonorsSavedOrderThenAppendsNew() {
        // Saved order [2, 1]; available also has new slot 3 → appended last.
        XCTAssertEqual(
            SlotOrdering.resolve(displayOrder: [2, 1], available: [0, 1, 2, 3]),
            [2, 1, 0, 3]
        )
    }

    func testResolveFiltersStaleOrderEntries() {
        // Saved order references slot 9 that no longer exists → dropped.
        XCTAssertEqual(
            SlotOrdering.resolve(displayOrder: [9, 2, 1], available: [1, 2]),
            [2, 1]
        )
    }

    func testResolveEmptyOrderIsNaturalSequence() {
        XCTAssertEqual(
            SlotOrdering.resolve(displayOrder: [], available: [0, 1, 2]),
            [0, 1, 2]
        )
    }

    func testResolveDedupesDuplicateOrderEntries() {
        XCTAssertEqual(
            SlotOrdering.resolve(displayOrder: [1, 1, 2], available: [1, 2, 3]),
            [1, 2, 3]
        )
    }

    func testResolveEmptyAvailable() {
        XCTAssertEqual(SlotOrdering.resolve(displayOrder: [1, 2], available: []), [])
    }
}
