import XCTest
@testable import FlashbackKit

final class FlashbackKitTests: XCTestCase {
    func testConfigurationDefaults() {
        let config = FlashbackConfiguration()
        XCTAssertEqual(config.bufferSeconds, 20)   // 設定画面の選択肢 10/20/30/60 の既定
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.triggers, .default)
    }
}
