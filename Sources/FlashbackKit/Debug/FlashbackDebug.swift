#if DEBUG
import Foundation

public extension Flashback {

    /// DEBUG-only: present the report UI (preview + trimming) immediately with a synthetic
    /// sample clip.
    ///
    /// Debug entry point for checking the trimming UX on the Simulator, where real ReplayKit
    /// recording doesn't run. Requires `Flashback.start()` to have installed the overlay
    /// window first. Not included in Release builds.
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

    /// DEBUG-only: present the report UI in the off (recording disabled) state immediately.
    ///
    /// Debug entry point for checking the guidance UI when there's no clip (Simulator /
    /// recording off). Requires `Flashback.start()` to have installed the overlay window.
    @MainActor
    static func debugPresentEmptyReport() {
        FlashbackController.shared.debugPresentReport(clipURL: nil)
    }

    /// DEBUG-only: present the report UI in the "recording just enabled" (justEnabled) state.
    ///
    /// Debug entry point for checking the follow-up state (orange mark + "recording") right
    /// after "turn on recording" succeeds from the off state. Requires `Flashback.start()`
    /// for the overlay window.
    @MainActor
    static func debugPresentRecordingJustEnabled() {
        FlashbackController.shared.debugPresentReportJustEnabled()
    }

    /// DEBUG-only: present the report UI in the "recording unavailable" state.
    ///
    /// Debug entry point for checking the guidance UI with the CTA hidden on
    /// Simulator / unsupported devices (`isRecordingAvailable() == false`). Requires
    /// `Flashback.start()` for the overlay window.
    @MainActor
    static func debugPresentReportUnavailable() {
        FlashbackController.shared.debugPresentReportUnavailable()
    }

    /// DEBUG-only: present the screen-recording permission priming sheet (visual check).
    /// Requires `Flashback.start()` for the overlay window.
    @MainActor
    static func debugPresentPriming() {
        FlashbackController.shared.debugPresentPriming()
    }

    /// DEBUG-only: reset the priming-seen flag (to re-test the first-run flow on a device).
    @MainActor
    static func debugResetPriming() {
        FlashbackController.shared.debugResetPriming()
    }

    /// DEBUG-only: present the "shake twice to launch" hint (centered alert-style card)
    /// (visual check).
    ///
    /// In production it's shown automatically once per device, right after the FAB
    /// visibility toggle is turned off. Requires `Flashback.start()` for the overlay window.
    @MainActor
    static func debugPresentShakeHint() {
        FlashbackController.shared.debugPresentShakeHint()
    }

    /// DEBUG-only: reset the shake-hint-seen flag (to re-test the first presentation on a device).
    @MainActor
    static func debugResetShakeHint() {
        FlashbackController.shared.debugResetShakeHint()
    }

    /// DEBUG-only: one-line recording status (rec / frame elapsed seconds / isCaptured / probe).
    /// Used for a lightweight HUD to observe interruption-detection behavior on a device.
    @MainActor
    static func debugRecordingStatusLine() -> String {
        FlashbackController.shared.debugRecordingStatusLine()
    }

    /// DEBUG-only: present a toast (in-progress / failure) (visual check).
    /// - Parameter kind: `"failure"` for the failure toast, otherwise the in-progress toast.
    @MainActor
    static func debugShowToast(_ kind: String) {
        if kind == "failure" {
            FlashbackController.shared.debugShowFailureToast()
        } else {
            FlashbackController.shared.debugShowProgressToast()
        }
    }

    /// DEBUG-only: present the settings screen immediately (visual check).
    @MainActor
    static func debugPresentSettings() {
        FlashbackController.shared.debugPresentSettings()
    }

    /// DEBUG-only: expand the currently-presented report sheet to `.large` (visual check of the
    /// `.large` window backdrop). Present a report first (e.g. `debugPresentEmptyReport()`).
    @MainActor
    static func debugExpandReport() {
        FlashbackController.shared.debugExpandReport()
    }
}
#endif
