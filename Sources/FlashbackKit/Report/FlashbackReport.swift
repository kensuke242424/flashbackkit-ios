import Foundation

/// Flashback がホストへ手渡す成果物。
///
/// コアの責務は「録画→トリム→成果物を渡す」まで。AI による再現手順・推定原因の
/// 生成や Slack 送信は上物（Reporter）= ホスト側の責務で、`onReport` の先で行う。
public struct FlashbackReport: Sendable {
    /// QA が入力した一行タイトル（レポート画面の「タイトル」欄）。
    public var title: String
    /// レポートに同梱される端末情報。
    public var device: DeviceInfo
    /// 切り出し済みクリップの一時ファイル URL（録画不可時は nil）。残すならホストでコピー/アップロードする。
    public var clipURL: URL?

    public init(title: String, device: DeviceInfo, clipURL: URL?) {
        self.title = title
        self.device = device
        self.clipURL = clipURL
    }
}
