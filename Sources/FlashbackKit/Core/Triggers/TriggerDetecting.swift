/// レポート起動トリガを検知する各実装の共通インターフェース。
///
/// `FlashbackController` は有効な `FlashbackTrigger` ごとに対応する detector を生成し、
/// どれが発火しても `onTrigger` 経由で単一の処理へ集約する。
///
/// UI / 検知に触れるため `@MainActor`。
@MainActor
protocol TriggerDetecting: AnyObject {
    /// トリガ成立時に呼ばれるコールバック。`start()` の前に設定する。
    var onTrigger: (() -> Void)? { get set }

    /// 検知を開始する。利用不可な環境では何もしない。
    func start()

    /// 検知を停止し、コールバックを解除する。
    func stop()
}
