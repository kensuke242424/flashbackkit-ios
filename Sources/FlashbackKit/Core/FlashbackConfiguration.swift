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

    /// 本物のシェイク検知の代わりに、画面上のデバッグ用フローティングボタンで
    /// レポート UI をトリガーする。PoC / Simulator 動作確認向け。
    public var debugTriggerEnabled: Bool

    /// 生コンテキストを構造化レポートへ変換する実装。
    /// 既定は `StubReportGenerator`。Claude / OpenAI / Gemini 実装に差し替える。
    public var reportGenerator: ReportGenerating

    /// 書き出した直前クリップを端末の写真ライブラリ（カメラロール）に保存するか。
    /// 既定 true。有効時はホストアプリの Info.plist に
    /// `NSPhotoLibraryAddUsageDescription` が必須（無いと権限要求でクラッシュする）。
    /// 注意: 画面録画はセンシティブ情報を含みうる。写真ライブラリ/iCloud に乗る点に留意。
    public var savesClipToPhotos: Bool

    public init(
        bufferSeconds: TimeInterval = 30,
        slackWebhookURL: URL? = nil,
        isEnabled: Bool = true,
        debugTriggerEnabled: Bool = true,
        reportGenerator: ReportGenerating = StubReportGenerator(),
        savesClipToPhotos: Bool = true
    ) {
        self.bufferSeconds = bufferSeconds
        self.slackWebhookURL = slackWebhookURL
        self.isEnabled = isEnabled
        self.debugTriggerEnabled = debugTriggerEnabled
        self.reportGenerator = reportGenerator
        self.savesClipToPhotos = savesClipToPhotos
    }
}
