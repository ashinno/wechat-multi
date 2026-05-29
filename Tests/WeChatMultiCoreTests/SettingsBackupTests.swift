import XCTest
@testable import WeChatMultiCore

final class SettingsBackupTests: XCTestCase {

    private func populatedStore() -> InMemoryKeyValueStore {
        let store = InMemoryKeyValueStore()
        store.set(["1": "Work", "2": "Personal"], forKey: DefaultsKey.slotNames)
        store.set([2, 1], forKey: DefaultsKey.slotDisplayOrder)
        store.set("/Applications/WeChat.app", forKey: DefaultsKey.customWeChatPath)
        store.set(true, forKey: DefaultsKey.didShowOnboarding)
        return store
    }

    func testExportImportRoundTrip() throws {
        let source = populatedStore()
        let data = try SettingsBackup.exportData(store: source, appVersion: "2.0.0")

        let dest = InMemoryKeyValueStore()
        try SettingsBackup.restore(from: data, to: dest, pathExists: { _ in true })

        XCTAssertEqual(dest.dictionary(forKey: DefaultsKey.slotNames) as? [String: String],
                       ["1": "Work", "2": "Personal"])
        XCTAssertEqual(dest.array(forKey: DefaultsKey.slotDisplayOrder) as? [Int], [2, 1])
        XCTAssertEqual(dest.string(forKey: DefaultsKey.customWeChatPath), "/Applications/WeChat.app")
        XCTAssertTrue(dest.bool(forKey: DefaultsKey.didShowOnboarding))
    }

    func testExportIsDeterministicAndPretty() throws {
        let store = populatedStore()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let data = try SettingsBackup.exportData(store: store, appVersion: "2.0.0", now: fixedDate)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\n"))                       // pretty-printed
        XCTAssertTrue(json.contains("\"version\" : 1"))
        XCTAssertTrue(json.contains("\"appVersion\" : \"2.0.0\""))
        // sortedKeys → appVersion appears before slotNames.
        let appVersionIdx = json.range(of: "appVersion")!.lowerBound
        let slotNamesIdx = json.range(of: "slotNames")!.lowerBound
        XCTAssertLessThan(appVersionIdx, slotNamesIdx)
    }

    func testStaleCustomPathDroppedOnImport() throws {
        let data = try SettingsBackup.exportData(store: populatedStore(), appVersion: "2.0.0")
        let dest = InMemoryKeyValueStore()
        // Simulate a new Mac where the old path doesn't exist.
        try SettingsBackup.restore(from: data, to: dest, pathExists: { _ in false })
        XCTAssertNil(dest.string(forKey: DefaultsKey.customWeChatPath))
        // Other settings still restored.
        XCTAssertEqual(dest.array(forKey: DefaultsKey.slotDisplayOrder) as? [Int], [2, 1])
    }

    func testRejectsUnsupportedSchema() throws {
        let json = """
        {"version": 99, "exportedAt": "2026-01-01T00:00:00Z", "appVersion": "9.9",
         "slotNames": {}, "slotOrder": [], "wechatAppPath": null, "didShowOnboarding": false}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try SettingsBackup.decode(json)) { error in
            XCTAssertEqual(error as? SettingsBackup.ImportError,
                           .unsupportedSchema(found: 99, expected: 1))
        }
    }

    func testRejectsMalformedJSON() {
        let junk = "not json at all".data(using: .utf8)!
        XCTAssertThrowsError(try SettingsBackup.decode(junk)) { error in
            guard case .malformed? = (error as? SettingsBackup.ImportError) else {
                return XCTFail("expected .malformed, got \(error)")
            }
        }
    }

    func testRejectsNonNumericSlotKeys() {
        let json = """
        {"version": 1, "exportedAt": "2026-01-01T00:00:00Z", "appVersion": "2.0.0",
         "slotNames": {"work": "Work"}, "slotOrder": [], "wechatAppPath": null,
         "didShowOnboarding": true}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try SettingsBackup.decode(json)) { error in
            guard case .malformed? = (error as? SettingsBackup.ImportError) else {
                return XCTFail("expected .malformed, got \(error)")
            }
        }
    }

    func testNilCustomPathExportsAsNull() throws {
        let store = InMemoryKeyValueStore()   // no custom path set
        let data = try SettingsBackup.exportData(store: store, appVersion: "2.0.0")
        let payload = try SettingsBackup.decode(data)
        XCTAssertNil(payload.wechatAppPath)
        XCTAssertEqual(payload.slotNames, [:])
        XCTAssertEqual(payload.slotOrder, [])
    }
}
