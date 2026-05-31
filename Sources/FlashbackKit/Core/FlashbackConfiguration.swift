import Foundation

public struct FlashbackConfiguration: Sendable {
    /// リングバッファに保持する直前秒数。
    public var bufferSeconds: TimeInterval

    /// 有効フラグ。Release ビルドでは原則 false 運用を想定。
    public var isEnabled: Bool

    /// レポート UI を起動するトリガ手段の集合（`OptionSet`、複数同時有効）。
    /// 既定は手持ち=シェイク / 据え置き=フローティングボタン の両対応。
    /// 環境に応じて `.init(triggers: [.shake])` のように絞れる。
    public var triggers: FlashbackTrigger

    /// `.floatingButton` の初期表示位置（四隅）。既定は右下。
    /// 表示後は QA がドラッグで動かせる。
    public var floatingButtonCorner: FloatingButtonCorner

    public init(
        bufferSeconds: TimeInterval = 30,
        isEnabled: Bool = true,
        triggers: FlashbackTrigger = .default,
        floatingButtonCorner: FloatingButtonCorner = .bottomTrailing
    ) {
        self.bufferSeconds = bufferSeconds
        self.isEnabled = isEnabled
        self.triggers = triggers
        self.floatingButtonCorner = floatingButtonCorner
    }
}

/// フローティングボタンの初期表示位置（四隅）。
public enum FloatingButtonCorner: Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}
