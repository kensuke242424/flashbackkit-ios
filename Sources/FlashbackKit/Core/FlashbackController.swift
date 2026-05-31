import Foundation

/// 各責務（録画 / トリガ検知 / レポート / 送信）を束ねる調整役。
@MainActor
final class FlashbackController {
    static let shared = FlashbackController()

    private var configuration = FlashbackConfiguration()
    private let recorder = ScreenRecorder()
    private let presenter = FlashbackPresenter()
    private var detectors: [TriggerDetecting] = []

    private init() {}

    func start(configuration: FlashbackConfiguration) {
        self.configuration = configuration
        guard configuration.isEnabled else { return }

        recorder.startBuffering(seconds: configuration.bufferSeconds)
        presenter.install()

        // 有効な各トリガに対応する detector を生成し、どれが発火しても handleTrigger() に集約。
        var detectors: [TriggerDetecting] = []
        if configuration.triggers.contains(.shake) {
            detectors.append(ShakeTrigger())
        }
        #if canImport(UIKit)
        if let host = presenter.triggerHost, configuration.triggers.contains(.floatingButton) {
            detectors.append(FloatingButtonTrigger(host: host, corner: configuration.floatingButtonCorner))
        }
        #endif
        for detector in detectors {
            detector.onTrigger = { [weak self] in self?.handleTrigger() }
            detector.start()
        }
        self.detectors = detectors
    }

    func stop() {
        detectors.forEach { $0.stop() }
        detectors.removeAll()
        recorder.stopBuffering()
        presenter.uninstall()
    }

    #if DEBUG
    /// DEBUG 専用: 任意のクリップでレポート UI を直接提示する（トリム UX 確認用）。
    func debugPresentReport(clipURL: URL) {
        presenter.presentReport(clipURL: clipURL) { [weak self] comment, range in
            self?.submit(comment: comment, clipURL: clipURL, range: range)
        }
    }
    #endif

    /// トリガー（シェイク / 多指ホールド / ボタン）→ 直前クリップを書き出してから
    /// プレビュー＋トリミング付きのレポート入力 UI を提示。
    private func handleTrigger() {
        let recorder = self.recorder
        let presenter = self.presenter
        presenter.showStatus("録画を準備中…")

        Task {
            // 書き出せなければ nil（クリップ無し＝コメントのみのフォール）。
            let clipURL = try? await recorder.exportBufferedClip()
            presenter.showStatus("")
            presenter.presentReport(clipURL: clipURL) { [weak self] comment, range in
                self?.submit(comment: comment, clipURL: clipURL, range: range)
            }
        }
    }

    /// 送信 → 選択範囲で切り出し → 写真保存 → レポート生成 → Slack 送信のループ本体。
    private func submit(comment: String, clipURL: URL?, range: ClosedRange<Double>?) {
        presenter.dismissReport()
        presenter.showStatus("レポート送信中…")

        let configuration = self.configuration
        let presenter = self.presenter

        Task {
            do {
                // 選択範囲があれば切り出す。失敗時はフルクリップにフォールバック。
                let finalClip = await Self.trimmedClip(clipURL, range: range)

                // 直前クリップを端末の写真ライブラリに保存（任意）。失敗してもループは継続。
                if let finalClip, configuration.savesClipToPhotos {
                    await Self.saveClipToPhotos(finalClip)
                }

                let report = try await configuration.reportGenerator.generate(
                    comment: comment,
                    device: .current(),
                    clipURL: finalClip
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

    /// 選択範囲（秒）でクリップを切り出す。範囲・クリップが無い、または切り出し失敗時は
    /// 元のクリップをそのまま返す（送信は止めない）。
    private static func trimmedClip(_ clipURL: URL?, range: ClosedRange<Double>?) async -> URL? {
        guard let clipURL, let range else { return clipURL }
        #if canImport(AVFoundation)
        do {
            return try await ClipTrimmer.trim(clipURL, fromSeconds: range.lowerBound, toSeconds: range.upperBound)
        } catch {
            FlashbackLog.report.error("クリップ切り出しに失敗（フル尺で継続）: \(error.localizedDescription, privacy: .public)")
            return clipURL
        }
        #else
        return clipURL
        #endif
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
            device: \(report.device.displayModel, privacy: .public) / \(report.device.systemName, privacy: .public) \(report.device.systemVersion, privacy: .public)
            clip: \(report.clipURL?.absoluteString ?? "なし", privacy: .public)
            """)
            return
        }
        try await SlackNotifier(webhookURL: webhookURL).post(report: report)
    }
}
