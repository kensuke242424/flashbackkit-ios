#if canImport(SwiftUI)
import SwiftUI

/// 設定画面の状態と適用処理を束ねるストア（SDK 内部・ホスト非依存）。
///
/// `@Published` の変更はそのまま SDK へ適用される（フローティングボタンの表示切替・
/// 保持秒数の反映）。権限表示はクロージャで最新の可用性を読む。Controller が生成・保持し、
/// ReportView → SettingsView へ渡す。
@MainActor
final class FlashbackSettingsStore: ObservableObject {
    /// フローティングボタンを表示するか。
    @Published var floatingButtonVisible: Bool {
        didSet { onFloatingButtonVisibleChanged(floatingButtonVisible) }
    }
    /// 保持する録画秒数（`retentionOptions` のいずれか）。
    @Published var retentionSeconds: Int {
        didSet { onRetentionChanged(retentionSeconds) }
    }
    /// 画面録画が利用可能か（権限表示用・呼ぶたびに最新を返す）。
    let isRecordingAvailable: () -> Bool

    /// 「録画をオンにする」での再試行が成立した直後か。`true` の間、ReportView の空状態は
    /// おやすみ（録画オフ）ではなく「録画オン直後（justEnabled）」を表示する。
    /// 提示のたびに Controller がリセットする（次回の空状態が誤って justEnabled にならないため）。
    @Published var recordingJustEnabled = false

    /// 保持秒数の選択肢。
    static let retentionOptions = [10, 20, 30, 60]

    private let onFloatingButtonVisibleChanged: (Bool) -> Void
    private let onRetentionChanged: (Int) -> Void
    private let onRetryRecording: () -> Void

    init(
        floatingButtonVisible: Bool,
        retentionSeconds: Int,
        isRecordingAvailable: @escaping () -> Bool,
        onFloatingButtonVisibleChanged: @escaping (Bool) -> Void,
        onRetentionChanged: @escaping (Int) -> Void,
        onRetryRecording: @escaping () -> Void
    ) {
        self.floatingButtonVisible = floatingButtonVisible
        self.retentionSeconds = retentionSeconds
        self.isRecordingAvailable = isRecordingAvailable
        self.onFloatingButtonVisibleChanged = onFloatingButtonVisibleChanged
        self.onRetentionChanged = onRetentionChanged
        self.onRetryRecording = onRetryRecording
    }

    /// 録画（`startCapture`）を再試行する。拒否後の後付け許可 / おやすみ状態の「録画をオンにする」用。
    /// iOS の仕様上、許可ダイアログはアプリ起動時に出る。再試行で再度出る場合もある（版依存）。
    func retryRecording() {
        onRetryRecording()
    }
}
#endif
