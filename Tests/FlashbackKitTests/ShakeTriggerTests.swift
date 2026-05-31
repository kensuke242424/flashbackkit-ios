#if canImport(UIKit) && canImport(CoreMotion)
import XCTest
@testable import FlashbackKit

/// `ShakeEvaluator`（しきい値判定の純粋ロジック）の検証。
/// CoreMotion 実機センサに依存せず、加速度サンプル列を直接与えてテストできる。
final class ShakeTriggerTests: XCTestCase {

    /// 既定パラメータ（peak=2.3g, rearm=1.3g, window=1.0s, cooldown=1.5s, peaks=2）。
    private func makeEvaluator() -> ShakeEvaluator { ShakeEvaluator() }

    /// 軸方向 1 つに大きさ `g` を与えるサンプル（合成加速度 = |g|）。
    @discardableResult
    private func feed(_ e: ShakeEvaluator, g: Double, at t: TimeInterval) -> Bool {
        e.process(x: g, y: 0, z: 0, timestamp: t)
    }

    func testRestDoesNotTrigger() {
        let e = makeEvaluator()
        // 静止＝約 1g が続いてもシェイクにならない。
        for i in 0..<40 {
            XCTAssertFalse(feed(e, g: 1.0, at: Double(i) * 0.05))
        }
    }

    func testSinglePeakDoesNotTrigger() {
        let e = makeEvaluator()
        // 落下/タップ等の単発ピーク 1 回だけでは発火しない（requiredPeaks=2）。
        XCTAssertFalse(feed(e, g: 1.0, at: 0.00))
        XCTAssertFalse(feed(e, g: 3.0, at: 0.05))   // ピーク 1
        XCTAssertFalse(feed(e, g: 1.0, at: 0.10))
        XCTAssertFalse(feed(e, g: 1.0, at: 0.50))
    }

    func testTwoPeaksWithinWindowTrigger() {
        let e = makeEvaluator()
        XCTAssertFalse(feed(e, g: 1.0, at: 0.00))   // 武装
        XCTAssertFalse(feed(e, g: 3.0, at: 0.05))   // ピーク 1
        XCTAssertFalse(feed(e, g: 1.0, at: 0.10))   // 再武装
        XCTAssertTrue(feed(e, g: 3.0, at: 0.15))    // ピーク 2 → 発火
    }

    func testHeldHighDoesNotDoubleCount() {
        let e = makeEvaluator()
        // 再武装（< rearm）を挟まず高加速度が続いても 1 ピーク扱い。発火しない。
        XCTAssertFalse(feed(e, g: 1.0, at: 0.00))
        XCTAssertFalse(feed(e, g: 3.0, at: 0.05))   // ピーク 1
        XCTAssertFalse(feed(e, g: 3.0, at: 0.10))   // 継続（再武装前）→ 数えない
        XCTAssertFalse(feed(e, g: 3.0, at: 0.15))   // 継続 → 数えない
    }

    func testPeaksOutsideWindowResetCount() {
        let e = makeEvaluator()
        XCTAssertFalse(feed(e, g: 1.0, at: 0.00))
        XCTAssertFalse(feed(e, g: 3.0, at: 0.05))   // ピーク 1（firstPeakAt=0.05）
        XCTAssertFalse(feed(e, g: 1.0, at: 0.10))   // 再武装
        // 窓（1.0s）を超えた次ピークは「1 個目」として数え直すので発火しない。
        XCTAssertFalse(feed(e, g: 3.0, at: 1.20))   // ピーク（数え直し→1）
    }

    func testCooldownSuppressesImmediateRetrigger() {
        let e = makeEvaluator()
        // 1 回目のシェイク成立。
        XCTAssertFalse(feed(e, g: 1.0, at: 0.00))
        XCTAssertFalse(feed(e, g: 3.0, at: 0.05))
        XCTAssertFalse(feed(e, g: 1.0, at: 0.10))
        XCTAssertTrue(feed(e, g: 3.0, at: 0.15))    // 発火（lastFireAt=0.15）

        // クールダウン（1.5s）中は、シェイク相当の入力でも一切発火しない。
        XCTAssertFalse(feed(e, g: 1.0, at: 0.50))
        XCTAssertFalse(feed(e, g: 3.0, at: 0.55))
        XCTAssertFalse(feed(e, g: 1.0, at: 0.60))
        XCTAssertFalse(feed(e, g: 3.0, at: 0.65))

        // クールダウン明けは再び 2 ピークで発火できる。
        XCTAssertFalse(feed(e, g: 1.0, at: 1.70))   // 再武装
        XCTAssertFalse(feed(e, g: 3.0, at: 1.75))   // ピーク 1
        XCTAssertFalse(feed(e, g: 1.0, at: 1.80))   // 再武装
        XCTAssertTrue(feed(e, g: 3.0, at: 1.85))    // ピーク 2 → 発火
    }

    func testResetClearsState() {
        let e = makeEvaluator()
        XCTAssertFalse(feed(e, g: 1.0, at: 0.00))
        XCTAssertFalse(feed(e, g: 3.0, at: 0.05))   // ピーク 1 を溜める
        e.reset()
        // reset 後はピーク蓄積が消えるので、次の単発ピークでは発火しない。
        XCTAssertFalse(feed(e, g: 1.0, at: 0.10))
        XCTAssertFalse(feed(e, g: 3.0, at: 0.15))   // これがピーク 1 扱い
    }
}
#endif
