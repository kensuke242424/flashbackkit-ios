import Foundation

/// 各責務（録画 / シェイク検知 / レポート / 送信）を束ねる調整役。
@MainActor
final class FlashbackController {
    static let shared = FlashbackController()

    private var configuration = FlashbackConfiguration()
    private let recorder = ScreenRecorder()
    private let shakeDetector = ShakeDetector()
    private let presenter = FlashbackPresenter()

    private init() {}

    func start(configuration: FlashbackConfiguration) {
        self.configuration = configuration
        guard configuration.isEnabled else { return }

        recorder.startBuffering(seconds: configuration.bufferSeconds)

        shakeDetector.onShake = { [weak self] in
            self?.handleTrigger()
        }
        shakeDetector.start()

        presenter.install(showsDebugButton: configuration.debugTriggerEnabled) { [weak self] in
            self?.handleTrigger()
        }
    }

    func stop() {
        shakeDetector.stop()
        recorder.stopBuffering()
        presenter.uninstall()
    }

    /// トリガー（シェイク or デバッグボタン）→ レポート入力 UI を提示。
    private func handleTrigger() {
        presenter.presentReport { [weak self] comment in
            self?.submit(comment: comment)
        }
    }

    /// コメント送信 → クリップ書き出し → レポート生成 → Slack 送信のループ本体。
    private func submit(comment: String) {
        presenter.dismissReport()
        presenter.showStatus("レポート送信中…")

        let configuration = self.configuration
        let recorder = self.recorder
        let presenter = self.presenter

        Task {
            do {
                // 書き出せなければ nil（クリップ無しレポート）。
                let clipURL = try? await recorder.exportBufferedClip()

                // 直前クリップを端末の写真ライブラリに保存（任意）。失敗してもループは継続。
                if let clipURL, configuration.savesClipToPhotos {
                    await Self.saveClipToPhotos(clipURL)
                }

                let report = try await configuration.reportGenerator.generate(
                    comment: comment,
                    device: .current(),
                    clipURL: clipURL
                )
                try await Self.deliver(report: report, webhookURL: configuration.slackWebhookURL)
                presenter.showStatus("送信しました ✅")
            } catch {
                FlashbackLog.report.error("レポート送信に失敗: \(error.localizedDescription, privacy: .public)")
                presenter.showStatus("送信に失敗しました ❌")
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            presenter.showStatus("")
        }
    }

    /// 直前クリップを写真ライブラリへ保存する。失敗はログのみ（ループは止めない）。
    private static func saveClipToPhotos(_ url: URL) async {
        #if canImport(Photos)
        do {
            try await PhotoLibrarySaver.save(url)
            FlashbackLog.report.info("クリップを写真ライブラリに保存しました")
        } catch {
            FlashbackLog.report.error("写真ライブラリ保存に失敗: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    /// Slack へ送る。Webhook 未設定なら内容をログ出力（PoC のループ確認用）。
    /// Console.app では `subsystem:FlashbackKit category:report` で追える。
    private static func deliver(report: FlashbackReport, webhookURL: URL?) async throws {
        guard let webhookURL else {
            // Webhook 未設定時の明示的なダンプ経路。レポート本文は Slack へ送る想定の
            // 内容なので .public で出す（録画の生データはここには含めない）。
            FlashbackLog.report.info("""
            Webhook 未設定のためログ出力:
            title: \(report.title, privacy: .public)
            comment: \(report.comment, privacy: .public)
            device: \(report.device.model, privacy: .public) / \(report.device.systemName, privacy: .public) \(report.device.systemVersion, privacy: .public)
            clip: \(report.clipURL?.absoluteString ?? "なし", privacy: .public)
            """)
            return
        }
        try await SlackNotifier(webhookURL: webhookURL).post(report: report)
    }
}
