import XCTest
@testable import WeChatMultiCore

final class ProcessTableTests: XCTestCase {

    private let cloneRoot = "/Users/ashinno/Applications/WeChat Multi"

    func testParsesMainAndClone() {
        let ps = """
        34810 Sat May 17 10:42:03 2026 /Applications/WeChat.app/Contents/MacOS/WeChat
        40853 Sat May 17 10:45:00 2026 /Users/ashinno/Applications/WeChat Multi/WeChat 1.app/Contents/MacOS/WeChat
        """
        let result = ProcessTable.parseInstances(psOutput: ps, cloneRootPath: cloneRoot)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].slot, 0)
        XCTAssertEqual(result[0].pid, 34810)
        XCTAssertEqual(result[0].startTime, "Sat May 17 10:42:03 2026")
        XCTAssertEqual(result[0].bundlePath, "/Applications/WeChat.app")
        XCTAssertEqual(result[1].slot, 1)
        XCTAssertEqual(result[1].pid, 40853)
        XCTAssertEqual(result[1].bundlePath,
                       "/Users/ashinno/Applications/WeChat Multi/WeChat 1.app")
    }

    func testExcludesHelperBinaries() {
        // WeChat's nested helper bundles and frameworks must NOT be counted.
        let ps = """
        34810 Sat May 17 10:42:03 2026 /Applications/WeChat.app/Contents/MacOS/WeChat
        34821 Sat May 17 10:42:10 2026 /Applications/WeChat.app/Contents/MacOS/WeChatAppEx.app/Contents/MacOS/WeChatAppEx
        34817 Sat May 17 10:42:11 2026 /Applications/WeChat.app/Contents/Frameworks/crashpad_handler
        34833 Sat May 17 10:42:37 2026 /Applications/WeChat.app/Contents/Frameworks/wxocr
        34824 Sat May 17 10:42:12 2026 /Applications/WeChat.app/Contents/MacOS/WeChatAppEx.app/Contents/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeChatAppEx Helper.app/Contents/MacOS/WeChatAppEx Helper
        """
        let result = ProcessTable.parseInstances(psOutput: ps, cloneRootPath: cloneRoot)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].slot, 0)
    }

    func testChineseBundleNames() {
        let ps = """
        34810 Sat May 17 10:42:03 2026 /Applications/微信.app/Contents/MacOS/微信
        50000 Sat May 17 10:42:03 2026 /Applications/微信.app/Contents/MacOS/WeChat
        """
        let result = ProcessTable.parseInstances(psOutput: ps, cloneRootPath: cloneRoot)
        // Both map to slot 0 (the original), via either executable name.
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.slot == 0 })
    }

    func testSortedBySlot() {
        let ps = """
        3 Sat May 17 10:00:00 2026 /Users/ashinno/Applications/WeChat Multi/WeChat 3.app/Contents/MacOS/WeChat
        1 Sat May 17 10:00:00 2026 /Users/ashinno/Applications/WeChat Multi/WeChat 1.app/Contents/MacOS/WeChat
        9 Sat May 17 10:00:00 2026 /Applications/WeChat.app/Contents/MacOS/WeChat
        2 Sat May 17 10:00:00 2026 /Users/ashinno/Applications/WeChat Multi/WeChat 2.app/Contents/MacOS/WeChat
        """
        let result = ProcessTable.parseInstances(psOutput: ps, cloneRootPath: cloneRoot)
        XCTAssertEqual(result.map(\.slot), [0, 1, 2, 3])
    }

    func testLocaleIndependentStartTime() {
        // A non-C locale lstart with a *different token count* must still parse:
        // the parser anchors on the first "/"-prefixed token, not a fixed offset.
        let ps = "123 lun. 17 mai 2026 à 10:42 /Applications/WeChat.app/Contents/MacOS/WeChat"
        let result = ProcessTable.parseInstances(psOutput: ps, cloneRootPath: cloneRoot)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].slot, 0)
        XCTAssertEqual(result[0].startTime, "lun. 17 mai 2026 à 10:42")
    }

    func testSkipsStrayBundlesInCloneRoot() {
        // A bundle inside cloneRoot that doesn't match "WeChat N.app" is ignored.
        let ps = """
        100 Sat May 17 10:00:00 2026 /Users/ashinno/Applications/WeChat Multi/WeChat.app/Contents/MacOS/WeChat
        101 Sat May 17 10:00:00 2026 /Users/ashinno/Applications/WeChat Multi/WeChat backup.app/Contents/MacOS/WeChat
        102 Sat May 17 10:00:00 2026 /Users/ashinno/Applications/WeChat Multi/WeChat 5.app/Contents/MacOS/WeChat
        """
        let result = ProcessTable.parseInstances(psOutput: ps, cloneRootPath: cloneRoot)
        XCTAssertEqual(result.map(\.slot), [5])
    }

    func testIgnoresWeChatBinaryInUnexpectedLocation() {
        // A WeChat binary neither under cloneRoot nor named WeChat.app/微信.app
        // (e.g. a Downloads copy) is not classified as either main or clone.
        let ps = "200 Sat May 17 10:00:00 2026 /Users/ashinno/Downloads/Old WeChat Copy.app/Contents/MacOS/WeChat"
        let result = ProcessTable.parseInstances(psOutput: ps, cloneRootPath: cloneRoot)
        XCTAssertTrue(result.isEmpty)
    }

    func testGarbageAndHeaderLinesSkipped() {
        let ps = """
        PID LSTART COMM
        not-a-number Sat May 17 10:00:00 2026 /Applications/WeChat.app/Contents/MacOS/WeChat

        34810 Sat May 17 10:42:03 2026 /Applications/WeChat.app/Contents/MacOS/WeChat
        555 no-slash-anywhere-here
        """
        let result = ProcessTable.parseInstances(psOutput: ps, cloneRootPath: cloneRoot)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].pid, 34810)
    }

    func testEmptyInput() {
        XCTAssertTrue(ProcessTable.parseInstances(psOutput: "", cloneRootPath: cloneRoot).isEmpty)
        XCTAssertTrue(ProcessTable.parseInstances(psOutput: "\n\n  \n", cloneRootPath: cloneRoot).isEmpty)
    }
}
