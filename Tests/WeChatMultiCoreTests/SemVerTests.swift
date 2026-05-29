import XCTest
@testable import WeChatMultiCore

final class SemVerTests: XCTestCase {

    func testBasicOrdering() {
        XCTAssertTrue(SemVer("2.0.0") > SemVer("1.8.0"))
        XCTAssertTrue(SemVer("1.8.0") > SemVer("1.7.9"))
        XCTAssertTrue(SemVer("1.10.0") > SemVer("1.9.0"))  // numeric, not lexical
        XCTAssertFalse(SemVer("1.8.0") > SemVer("1.8.0"))
        XCTAssertTrue(SemVer("1.8.1") > SemVer("1.8.0"))
    }

    func testMissingComponentsTreatedAsZero() {
        XCTAssertEqual(SemVer("1.8"), SemVer("1.8.0"))
        XCTAssertEqual(SemVer("1"), SemVer("1.0.0"))
        XCTAssertTrue(SemVer("1.8.1") > SemVer("1.8"))
        XCTAssertFalse(SemVer("1.8") > SemVer("1.8.0"))
    }

    func testEquality() {
        XCTAssertEqual(SemVer("2.0.0"), SemVer("2.0.0"))
        XCTAssertEqual(SemVer("2.0"), SemVer("2.0.0.0"))
        XCTAssertNotEqual(SemVer("2.0.0"), SemVer("2.0.1"))
    }

    func testLenientParsingOfSuffixes() {
        // Leading digits of each component are taken; suffixes are dropped.
        XCTAssertEqual(SemVer("1.8.0-beta"), SemVer("1.8.0"))
        XCTAssertEqual(SemVer("2.0.0rc1"), SemVer("2.0.0"))
    }

    func testIsNewerConvenience() {
        XCTAssertTrue(SemVer.isNewer("2.0.0", than: "1.8.0"))
        XCTAssertFalse(SemVer.isNewer("1.8.0", than: "2.0.0"))
        XCTAssertFalse(SemVer.isNewer("1.8.0", than: "1.8.0"))
    }

    func testDescriptionRoundTrips() {
        XCTAssertEqual(SemVer("2.0.0").description, "2.0.0")
        XCTAssertEqual(SemVer("1.10.2").description, "1.10.2")
    }

    func testSortStability() {
        let sorted = ["1.7.0", "2.0.0", "1.8.0", "1.10.0", "1.9.5"]
            .map(SemVer.init).sorted()
        XCTAssertEqual(sorted.map(\.description),
                       ["1.7.0", "1.8.0", "1.9.5", "1.10.0", "2.0.0"])
    }
}
