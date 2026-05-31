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
    @MainActor
    public static func start(configuration: FlashbackConfiguration = .init()) {
        FlashbackController.shared.start(configuration: configuration)
    }

    /// 録画とリスナーを停止する。
    @MainActor
    public static func stop() {
        FlashbackController.shared.stop()
    }
}
