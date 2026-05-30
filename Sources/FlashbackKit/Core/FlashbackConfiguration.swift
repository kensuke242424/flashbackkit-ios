import Foundation

public struct FlashbackConfiguration {
    /// リングバッファに保持する直前秒数。
    public var bufferSeconds: TimeInterval

    /// テキストレポート投稿先の Slack Incoming Webhook URL。
    /// 注意: Webhook は動画を送れない（SlackNotifier 参照）。
    public var slackWebhookURL: URL?

    /// 有効フラグ。Release ビルドでは原則 false 運用を想定。
    public var isEnabled: Bool

    public init(
        bufferSeconds: TimeInterval = 30,
        slackWebhookURL: URL? = nil,
        isEnabled: Bool = true
    ) {
        self.bufferSeconds = bufferSeconds
        self.slackWebhookURL = slackWebhookURL
        self.isEnabled = isEnabled
    }
}
