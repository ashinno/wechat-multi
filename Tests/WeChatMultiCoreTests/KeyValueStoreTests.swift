import XCTest
@testable import WeChatMultiCore

final class KeyValueStoreTests: XCTestCase {

    func testSetAndGetTypes() {
        let s = InMemoryKeyValueStore()
        s.set("hello", forKey: "str")
        s.set(true, forKey: "flag")
        s.set(42, forKey: "num")
        s.set([1, 2, 3], forKey: "arr")
        s.set(["a": "b"], forKey: "dict")

        XCTAssertEqual(s.string(forKey: "str"), "hello")
        XCTAssertTrue(s.bool(forKey: "flag"))
        XCTAssertEqual(s.integer(forKey: "num"), 42)
        XCTAssertEqual(s.array(forKey: "arr") as? [Int], [1, 2, 3])
        XCTAssertEqual(s.dictionary(forKey: "dict") as? [String: String], ["a": "b"])
    }

    func testAbsentKeysReturnZeroValues() {
        let s = InMemoryKeyValueStore()
        XCTAssertNil(s.string(forKey: "nope"))
        XCTAssertFalse(s.bool(forKey: "nope"))
        XCTAssertEqual(s.integer(forKey: "nope"), 0)
        XCTAssertNil(s.array(forKey: "nope"))
        XCTAssertNil(s.dictionary(forKey: "nope"))
        XCTAssertNil(s.object(forKey: "nope"))
    }

    func testSetNilRemoves() {
        let s = InMemoryKeyValueStore()
        s.set("x", forKey: "k")
        s.set(nil, forKey: "k")
        XCTAssertNil(s.string(forKey: "k"))
        XCTAssertNil(s.object(forKey: "k"))
    }

    func testRemoveObject() {
        let s = InMemoryKeyValueStore()
        s.set("x", forKey: "k")
        s.removeObject(forKey: "k")
        XCTAssertNil(s.object(forKey: "k"))
    }

    func testSeedFromInitialDictionary() {
        let s = InMemoryKeyValueStore(["seeded": "yes"])
        XCTAssertEqual(s.string(forKey: "seeded"), "yes")
    }

    func testDefaultsKeyCatalogIsComplete() {
        // The `all` list must include every individually-declared key, so
        // backup/restore can never silently miss one.
        let declared = Set([
            DefaultsKey.customWeChatPath, DefaultsKey.slotNames,
            DefaultsKey.slotDisplayOrder, DefaultsKey.didShowOnboarding,
            DefaultsKey.lastSeenVersion
        ])
        XCTAssertEqual(Set(DefaultsKey.all), declared)
    }
}
