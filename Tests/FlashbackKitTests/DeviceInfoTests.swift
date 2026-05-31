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

    func testKnownIdentifierMapsToMarketingName() {
        XCTAssertEqual(DeviceModelNames.name(for: "iPhone16,1"), "iPhone 15 Pro")
        XCTAssertEqual(DeviceModelNames.name(for: "iPad14,1"), "iPad mini (6th generation)")
    }

    func testUnknownIdentifierFallsBackToRawValue() {
        // 未登録の新機種は識別子をそのまま返す（壊れない・嘘をつかない）。
        XCTAssertEqual(DeviceModelNames.name(for: "iPhone99,9"), "iPhone99,9")
    }

    func testDisplayModelFormats() {
        let mapped = DeviceInfo(
            model: "iPhone", modelIdentifier: "iPhone16,1", modelName: "iPhone 15 Pro",
            systemName: "iOS", systemVersion: "26.5", appVersion: "1.0", buildNumber: "1", locale: "ja_JP"
        )
        XCTAssertEqual(mapped.displayModel, "iPhone 15 Pro (iPhone16,1)")

        // 未登録（名前＝識別子）は識別子のみ。
        let unmapped = DeviceInfo(
            model: "iPhone", modelIdentifier: "iPhone99,9", modelName: "iPhone99,9",
            systemName: "iOS", systemVersion: "26.5", appVersion: "1.0", buildNumber: "1", locale: "ja_JP"
        )
        XCTAssertEqual(unmapped.displayModel, "iPhone99,9")
    }
}
