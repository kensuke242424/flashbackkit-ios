import Foundation

/// FlashbackKit public entry point.
///
/// > Recall the moment before the bug.
public enum Flashback {

    /// FlashbackKit を起動する。
    /// バッファ録画を開始し、有効なトリガ（既定: シェイク / 多指ホールド / フローティング
    /// ボタン）でレポート UI を出す。`configuration.triggers` で手段を絞れる。
    ///
    /// アプリ起動直後（App init / didFinishLaunching）で一度だけ呼ぶ。
    ///
    /// - Parameter onReport: 録画→トリム→（任意の写真保存）まで終えた成果物
    ///   `FlashbackReport`（クリップ URL・端末情報・コメント）をホストへ手渡すコールバック。
    ///   AI 要約・Slack 送信・自社バックエンド送信などホスト固有の処理はここで行う
    ///   （SDK の役割は成果物を渡すところまで）。MainActor で呼ばれる。
    ///   注意: `report.clipURL` は一時ファイル。残すならこの中でコピー/アップロードすること。
    @MainActor
    public static func start(
        configuration: FlashbackConfiguration = .init(),
        onReport: (@MainActor (FlashbackReport) -> Void)? = nil
    ) {
        FlashbackController.shared.start(configuration: configuration, onReport: onReport)
    }

    /// 録画とリスナーを停止する。
    @MainActor
    public static func stop() {
        FlashbackController.shared.stop()
    }
}
