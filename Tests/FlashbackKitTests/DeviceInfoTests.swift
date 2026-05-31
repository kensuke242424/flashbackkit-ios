import XCTest
@testable import FlashbackKit

/// `DeviceInfo` の採取検証。
final class DeviceInfoTests: XCTestCase {

    @MainActor
    func testModelIdentifierIsPopulated() {
        // Simulator では SIMULATOR_MODEL_IDENTIFIER（実機相当、例: "iPhone17,1"）が返るため
        // 空でも "unknown" でもないことを担保する。
        let info = DeviceInfo.current()
        XCTAssertFalse(info.modelIdentifier.isEmpty)
        XCTAssertNotEqual(info.modelIdentifier, "unknown")
    }

    @MainActor
    func testModelIdentifierMatchesSimulatorEnvironment() throws {
        // テストは Simulator 上で走る前提。env と一致することを確認する。
        let expected = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        try XCTSkipIf(expected == nil, "Simulator 以外では SIMULATOR_MODEL_IDENTIFIER が無い")
        XCTAssertEqual(DeviceInfo.current().modelIdentifier, expected)
    }
}
