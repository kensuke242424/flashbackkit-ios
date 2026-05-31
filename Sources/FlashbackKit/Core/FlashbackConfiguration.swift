import Foundation

public struct FlashbackConfiguration: Sendable {
    /// リングバッファに保持する直前秒数。
    public var bufferSeconds: TimeInterval

    /// テキストレポート投稿先の Slack Incoming Webhook URL。
    /// 注意: Webhook は動画を送れない（SlackNotifier 参照）。
    /// nil の場合はレポート内容をコンソールに出力する（PoC のループ確認用）。
    public var slackWebhookURL: URL?

    /// 有効フラグ。Release ビルドでは原則 false 運用を想定。
    public var isEnabled: Bool

    /// レポート UI を起動するトリガ手段の集合（`OptionSet`、複数同時有効）。
    /// 既定は手持ち=シェイク / 据え置き=フローティングボタン の両対応。
    /// 環境に応じて `.init(triggers: [.shake])` のように絞れる。
    public var triggers: FlashbackTrigger

    /// `.floatingButton` の初期表示位置（四隅）。既定は右下。
    /// 表示後は QA がドラッグで動かせる。
    public var floatingButtonCorner: FloatingButtonCorner

    /// 生コンテキストを構造化レポートへ変換する実装。
    /// 既定は `StubReportGenerator`。Claude / OpenAI / Gemini 実装に差し替える。
    public var reportGenerator: ReportGenerating

    public init(
        bufferSeconds: TimeInterval = 30,
        slackWebhookURL: URL? = nil,
        isEnabled: Bool = true,
        triggers: FlashbackTrigger = .default,
        floatingButtonCorner: FloatingButtonCorner = .bottomTrailing,
        reportGenerator: ReportGenerating = StubReportGenerator()
    ) {
        self.bufferSeconds = bufferSeconds
        self.slackWebhookURL = slackWebhookURL
        self.isEnabled = isEnabled
        self.triggers = triggers
        self.floatingButtonCorner = floatingButtonCorner
        self.reportGenerator = reportGenerator
    }
}

/// フローティングボタンの初期表示位置（四隅）。
public enum FloatingButtonCorner: Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}
