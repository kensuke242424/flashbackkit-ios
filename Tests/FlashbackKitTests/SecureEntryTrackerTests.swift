#if canImport(UIKit)
import XCTest
import UIKit
@testable import FlashbackKit

/// セキュア入力プライバシーガードの簿記（`SecureEntryTracker`）の検証。
///
/// SDK のクリップは in-app capture＝アプリが描画する全てを録る（OS の secure field
/// ブランク化は外部キャプチャ専用・実機実測）。そのため「secure field の編集中は
/// キャプチャを一時停止」するのがガードの趣旨で、本テストはその判定エッジ
/// （0→1 で停止・空集合化で再開・identity ベースの解除）を実フィールドで担保する。
/// キャプチャの停止/再開そのものは ReplayKit 依存のため対象外（ScreenRecorder 側）。
@MainActor
final class SecureEntryTrackerTests: XCTestCase {

    private func makeSecureField() -> UITextField {
        let field = UITextField()
        field.isSecureTextEntry = true
        return field
    }

    /// secure field の begin で 0→1 エッジ（true）、end で空集合エッジ（true）。
    func testSecureFieldBeginPausesAndEndResumes() {
        let tracker = SecureEntryTracker()
        let field = makeSecureField()

        XCTAssertTrue(tracker.noteBeginEditing(field), "0→1 の begin は停止エッジを返す")
        XCTAssertTrue(tracker.isEditingSecure)
        XCTAssertTrue(tracker.noteEndEditing(field), "最後の end は再開エッジを返す")
        XCTAssertFalse(tracker.isEditingSecure)
    }

    /// 非 secure のフィールドは追跡しない（begin/end とも false・状態も変わらない）。
    func testPlainFieldIsIgnored() {
        let tracker = SecureEntryTracker()
        let field = UITextField()                       // isSecureTextEntry = false

        XCTAssertFalse(tracker.noteBeginEditing(field))
        XCTAssertFalse(tracker.isEditingSecure)
        XCTAssertFalse(tracker.noteEndEditing(field), "未追跡オブジェクトの end は何も起こさない")
    }

    /// secure field 間のフォーカス移動（新フィールドの begin が旧フィールドの end より
    /// 先に届く重なり）でも、全フィールドの編集が終わるまで再開エッジを出さない。
    func testOverlappingSecureFieldsHoldThePause() {
        let tracker = SecureEntryTracker()
        let a = makeSecureField()
        let b = makeSecureField()

        XCTAssertTrue(tracker.noteBeginEditing(a))
        XCTAssertFalse(tracker.noteBeginEditing(b), "2 枚目の begin は停止エッジを重複発火しない")
        XCTAssertFalse(tracker.noteEndEditing(a), "b が編集中なので再開しない")
        XCTAssertTrue(tracker.noteEndEditing(b), "最後の end で再開")
    }

    /// 編集中に目玉トグルで isSecureTextEntry が false へ変わっても、end は identity で
    /// 解除される（trait の現在値に依存すると永久に停止が残る）。
    func testRevealToggleMidEditStillReleasesOnEnd() {
        let tracker = SecureEntryTracker()
        let field = makeSecureField()

        XCTAssertTrue(tracker.noteBeginEditing(field))
        field.isSecureTextEntry = false                 // 目玉トグル相当
        XCTAssertTrue(tracker.noteEndEditing(field), "trait が変わっても identity で解除")
        XCTAssertFalse(tracker.isEditingSecure)
    }

    /// secure な UITextView も対象（稀だが UITextInputTraits は持っている）。
    func testSecureTextViewIsTracked() {
        let tracker = SecureEntryTracker()
        let view = UITextView()
        view.isSecureTextEntry = true

        XCTAssertTrue(tracker.noteBeginEditing(view))
        XCTAssertTrue(tracker.noteEndEditing(view))
    }
}
#endif
