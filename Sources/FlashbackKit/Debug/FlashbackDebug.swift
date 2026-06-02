#if DEBUG
import Foundation

public extension Flashback {

    /// DEBUG 専用: 合成サンプル動画でレポート（プレビュー＋トリミング）UI を即時表示する。
    ///
    /// ReplayKit 実録画が動かない Simulator でトリミング UX を確認するための入口。
    /// 事前に `Flashback.start()` を呼んで overlay window が設置されている必要がある。
    /// Release ビルドには含まれない。
    @MainActor
    static func debugPresentSampleReport(seconds: Int = 12) {
        Task {
            #if canImport(AVFoundation) && canImport(UIKit)
            guard let url = try? await SampleClipMaker.make(seconds: seconds) else {
                FlashbackLog.report.error("サンプル動画の生成に失敗")
                return
            }
            FlashbackController.shared.debugPresentReport(clipURL: url)
            #endif
        }
    }

    /// DEBUG 専用: 「おやすみ（録画オフ）」状態のレポート UI を即時表示する。
    ///
    /// クリップ無し（Simulator / 録画オフ）時の案内 UI を確認するための入口。
    /// 事前に `Flashback.start()` を呼んで overlay window が設置されている必要がある。
    @MainActor
    static func debugPresentEmptyReport() {
        FlashbackController.shared.debugPresentReport(clipURL: nil)
    }

    /// DEBUG 専用: 「録画オン直後（justEnabled）」状態のレポート UI を即時表示する。
    ///
    /// おやすみ → 「録画をオンにする」成立直後の継続状態（オレンジマーク＋「録画中」）を
    /// 確認するための入口。事前に `Flashback.start()` で overlay window が必要。
    @MainActor
    static func debugPresentRecordingJustEnabled() {
        FlashbackController.shared.debugPresentReportJustEnabled()
    }

    /// DEBUG 専用: 「録画不可（この端末では利用できません）」状態のレポート UI を表示する。
    ///
    /// Simulator / 非対応端末（`isRecordingAvailable()==false`）時の CTA 非表示の案内 UI を
    /// 確認するための入口。事前に `Flashback.start()` で overlay window が必要。
    @MainActor
    static func debugPresentReportUnavailable() {
        FlashbackController.shared.debugPresentReportUnavailable()
    }

    /// DEBUG 専用: トースト（進行中 / 失敗）を表示する（見た目確認用）。
    /// - Parameter kind: `"failure"` で失敗トースト、それ以外は進行中トースト。
    @MainActor
    static func debugShowToast(_ kind: String) {
        if kind == "failure" {
            FlashbackController.shared.debugShowFailureToast()
        } else {
            FlashbackController.shared.debugShowProgressToast()
        }
    }

    /// DEBUG 専用: 設定画面を即時表示する（見た目確認用）。
    @MainActor
    static func debugPresentSettings() {
        FlashbackController.shared.debugPresentSettings()
    }
}
#endif
