import XCTest
@testable import FlashbackKit

/// `FlashbackTrigger`（OptionSet）の意味論と前方互換性の検証。
final class FlashbackTriggerTests: XCTestCase {

    func testRawValuesAreStable() {
        // ビット割り当てが変わると保存値や既存呼び出しを壊すため固定であることを担保。
        XCTAssertEqual(FlashbackTrigger.shake.rawValue, 1 << 0)
        XCTAssertEqual(FlashbackTrigger.floatingButton.rawValue, 1 << 1)
    }

    func testDefaultContainsShakeAndButton() {
        let d = FlashbackTrigger.default
        XCTAssertTrue(d.contains(.shake))
        XCTAssertTrue(d.contains(.floatingButton))
    }

    func testSubsetContainsSemantics() {
        let handheld: FlashbackTrigger = [.shake]
        XCTAssertTrue(handheld.contains(.shake))
        XCTAssertFalse(handheld.contains(.floatingButton))
    }

    func testUnionAndInsert() {
        var t: FlashbackTrigger = [.shake]
        t.insert(.floatingButton)
        XCTAssertEqual(t, [.shake, .floatingButton])
    }

    func testConfigurationDefaultsToDefaultTriggers() {
        let config = FlashbackConfiguration()
        XCTAssertEqual(config.triggers, .default)
        XCTAssertEqual(config.floatingButtonCorner, .bottomTrailing)
    }
}
