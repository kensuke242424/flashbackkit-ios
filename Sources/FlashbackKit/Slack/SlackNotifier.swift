import Foundation

/// Slack Incoming Webhook にテキストレポートを投稿する。
///
/// 重要: Incoming Webhook はテキスト / Block Kit のみ。ファイル・動画は
/// 送れない。クリップを添えたいなら別所にホストしてリンクを貼るか、
/// Bot トークン + files.getUploadURLExternal / files.completeUploadExternal を使う。
struct SlackNotifier {
    let webhookURL: URL

    func post(report: FlashbackReport) async throws {
        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let text = """
        *\(report.title)*
        \(report.comment)

        Device: \(report.device.displayModel) / \(report.device.systemName) \(report.device.systemVersion)
        App: \(report.device.appVersion) (\(report.device.buildNumber))
        """
        let payload = ["text": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw FlashbackError.slackPostFailed
        }
    }
}
