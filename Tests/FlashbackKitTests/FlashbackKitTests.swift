import XCTest
@testable import FlashbackKit

final class FlashbackKitTests: XCTestCase {
    func testConfigurationDefaults() {
        let config = FlashbackConfiguration()
        XCTAssertEqual(config.bufferSeconds, 30)
        XCTAssertTrue(config.isEnabled)
        XCTAssertNil(config.slackWebhookURL)
    }
}
