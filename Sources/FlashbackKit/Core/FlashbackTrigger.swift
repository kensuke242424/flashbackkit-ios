/// レポート UI を起動するトリガ手段の集合。
///
/// `OptionSet` なので複数手段を同時に有効化できる。利用環境に応じて選ぶ:
/// 手持ち端末ならシェイク、据え置き/固定スタンドならフローティングボタンや多指ホールド。
///
/// ```swift
/// Flashback.start()                                   // 既定: 全手段オン
/// Flashback.start(configuration: .init(triggers: [.shake]))          // 手持ち専用
/// Flashback.start(configuration: .init(triggers: [.floatingButton])) // 据え置き専用（確実）
/// ```
///
/// 将来のトリガ追加は新しいビットを足すだけで、既存の `rawValue` や `.default` を
/// 壊さない（前方互換）。
public struct FlashbackTrigger: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// 端末を振る（シェイク）。手持ち利用向け。加速度センサで検知するため
    /// Simulator では発火しない。
    public static let shake = FlashbackTrigger(rawValue: 1 << 0)

    /// 画面に常駐する小さなフローティングボタン（🐞）。長押しで起動。
    /// 実体のあるボタンなので確実に発火し、ホスト操作も阻害しない。
    /// スタンド固定など据え置き利用での確実な手段。ドラッグで位置を動かせる。
    public static let floatingButton = FlashbackTrigger(rawValue: 1 << 1)

    /// 既定のトリガ集合。手持ち（シェイク）/ 据え置き（フローティングボタン）の双方に対応する。
    public static let `default`: FlashbackTrigger = [.shake, .floatingButton]
}
