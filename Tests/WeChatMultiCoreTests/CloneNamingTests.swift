import XCTest
@testable import WeChatMultiCore

final class CloneNamingTests: XCTestCase {

    func testBundleIDFormat() {
        XCTAssertEqual(CloneNaming.bundleID(forSlot: 1), "com.wechatmulti.clone1")
        XCTAssertEqual(CloneNaming.bundleID(forSlot: 42), "com.wechatmulti.clone42")
    }

    func testFolderNameFormat() {
        XCTAssertEqual(CloneNaming.folderName(forSlot: 1), "WeChat 1.app")
        XCTAssertEqual(CloneNaming.folderName(forSlot: 10), "WeChat 10.app")
    }

    func testRoundTripFolderNameToSlot() {
        for slot in [1, 2, 7, 10, 99, 1000] {
            let name = CloneNaming.folderName(forSlot: slot)
            XCTAssertEqual(CloneNaming.parseSlot(fromFolderName: name), slot)
        }
    }

    func testParseRejectsNonMatching() {
        XCTAssertNil(CloneNaming.parseSlot(fromFolderName: "WeChat.app"))
        XCTAssertNil(CloneNaming.parseSlot(fromFolderName: "WeChat backup.app"))
        XCTAssertNil(CloneNaming.parseSlot(fromFolderName: "WeChat 1"))            // no .app
        XCTAssertNil(CloneNaming.parseSlot(fromFolderName: "wechat 1.app"))        // wrong case
        XCTAssertNil(CloneNaming.parseSlot(fromFolderName: "WeChat 1.app.bak"))    // trailing junk
        XCTAssertNil(CloneNaming.parseSlot(fromFolderName: "WeChat 0.app"))        // slot 0 invalid
        XCTAssertNil(CloneNaming.parseSlot(fromFolderName: "WeChatAppEx.app"))
        XCTAssertNil(CloneNaming.parseSlot(fromFolderName: ".WeChat 1.app.tmp-abc")) // temp build dir
    }

    func testBundleIDStabilityContract() {
        // This scheme is permanent — changing it would orphan sandbox
        // containers. Pin it so a refactor can't silently alter it.
        XCTAssertEqual(CloneNaming.bundleID(forSlot: 3), "com.wechatmulti.clone3")
    }
}
