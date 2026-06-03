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
    /// 画面録画が利用可能か（= 端末/環境が録画できるか・RPScreenRecorder.isAvailable）。
    /// 「録画オン/オフ」とは別物（拒否しても true）。CTA の出し分け等の判定に使う。
    let isRecordingAvailable: () -> Bool

    /// 実際に録画が走っている（許可確定済み）か。設定画面の「録画中/停止中」表示用。
    /// Controller が `ScreenRecorder.onRecordingStateChanged` 経由で更新する（@Published＝UI 自動更新）。
    /// 許可ダイアログ応答前は false（楽観的に true にしない）。
    @Published var isRecordingActive: Bool

    /// 「録画をオンにする」での再試行が成立した直後か。`true` の間、ReportView の空状態は
    /// おやすみ（録画オフ）ではなく「録画オン直後（justEnabled）」を表示する。
    /// 提示のたびに Controller がリセットする（次回の空状態が誤って justEnabled にならないため）。
    @Published var recordingJustEnabled = false

    /// アプリ起動時に画面収録の許可を確認する（起動直後に `startCapture`）か。設定トグルで切替。
    /// 変更は UserDefaults へ永続化し、Controller 側で即時反映（ON で即バッファ開始）する。
    @Published var promptOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(promptOnLaunch, forKey: Self.promptOnLaunchKey)
            onPromptOnLaunchChanged(promptOnLaunch)
        }
    }

    /// 画面収録のプライミング（事前説明）を既に一度見せたか（端末1回）。
    /// `true` 以降は「録画をオンにする」でプライミングを挟まず直接 OS 確認（再試行）へ。
    /// SDK 副作用を持たない単純フラグなので UserDefaults を直接読み書きする。
    var hasPrimedScreenRecording: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hasPrimedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hasPrimedKey) }
    }

    /// 保持秒数の選択肢。
    static let retentionOptions = [10, 20, 30, 60]

    /// UserDefaults キー（ホストと衝突しないよう接頭辞付き）。
    static let promptOnLaunchKey = "FlashbackKit.promptOnLaunch"
    static let hasPrimedKey = "FlashbackKit.hasPrimedScreenRecording"

    private let onFloatingButtonVisibleChanged: (Bool) -> Void
    private let onRetentionChanged: (Int) -> Void
    private let onRetryRecording: () -> Void
    private let onStopRecording: () -> Void
    private let onPromptOnLaunchChanged: (Bool) -> Void

    init(
        floatingButtonVisible: Bool,
        retentionSeconds: Int,
        promptOnLaunch: Bool,
        isRecordingActive: Bool,
        isRecordingAvailable: @escaping () -> Bool,
        onFloatingButtonVisibleChanged: @escaping (Bool) -> Void,
        onRetentionChanged: @escaping (Int) -> Void,
        onRetryRecording: @escaping () -> Void,
        onStopRecording: @escaping () -> Void,
        onPromptOnLaunchChanged: @escaping (Bool) -> Void
    ) {
        self.floatingButtonVisible = floatingButtonVisible
        self.retentionSeconds = retentionSeconds
        self.promptOnLaunch = promptOnLaunch            // init 代入では didSet は走らない（永続/副作用は起きない）
        self.isRecordingActive = isRecordingActive
        self.isRecordingAvailable = isRecordingAvailable
        self.onFloatingButtonVisibleChanged = onFloatingButtonVisibleChanged
        self.onRetentionChanged = onRetentionChanged
        self.onRetryRecording = onRetryRecording
        self.onStopRecording = onStopRecording
        self.onPromptOnLaunchChanged = onPromptOnLaunchChanged
    }

    /// 録画（`startCapture`）を再試行する。拒否後の後付け許可 / おやすみ状態の「録画をオンにする」用。
    /// iOS の仕様上、許可ダイアログはアプリ起動時に出る。再試行で再度出る場合もある（版依存）。
    func retryRecording() {
        onRetryRecording()
    }

    /// 録画を停止する（ユーザ操作）。再開は「録画を有効にする」/「録画をオンにする」から。
    func stopRecording() {
        onStopRecording()
    }
}
#endif
