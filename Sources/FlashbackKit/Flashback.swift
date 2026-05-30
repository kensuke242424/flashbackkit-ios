import Foundation

/// FlashbackKit public entry point.
///
/// > Recall the moment before the bug.
public enum Flashback {

    /// FlashbackKit を起動する。
    /// バッファ録画を開始し、シェイクでレポート UI を出す。
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
