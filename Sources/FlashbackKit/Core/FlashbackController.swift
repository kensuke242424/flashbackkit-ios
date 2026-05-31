import Foundation

/// 各責務（録画 / トリガ検知 / レポート / 送信）を束ねる調整役。
@MainActor
final class FlashbackController {
    static let shared = FlashbackController()

    private var configuration = FlashbackConfiguration()
    private let recorder = ScreenRecorder()
    private let presenter = FlashbackPresenter()
    private var detectors: [TriggerDetecting] = []
    /// 成果物 `FlashbackReport` をホストへ手渡すコールバック（拡張点）。
    private var onReport: (@MainActor (FlashbackReport) -> Void)?
    /// 1 回の提示につき onReport / Slack を一度だけ発火させるためのフラグ
    /// （保存と共有の両方を行っても二重に commit しない）。
    private var hasCommitted = false

    private init() {}

    func start(
        configuration: FlashbackConfiguration,
        onReport: (@MainActor (FlashbackReport) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.onReport = onReport
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
        present(rawClip: clipURL)
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
            self.present(rawClip: clipURL)
        }
    }

    /// レポート UI を提示する。保存 / 共有の 2 アクションを配線する。
    private func present(rawClip: URL?) {
        hasCommitted = false
        presenter.presentReport(
            clipURL: rawClip,
            onSave: { [weak self] comment, range in
                await self?.handleSave(rawClip: rawClip, comment: comment, range: range)
            },
            onShare: { [weak self] comment, range in
                await self?.handleShare(rawClip: rawClip, comment: comment, range: range)
            }
        )
    }

    /// 保存: 選択範囲を切り出し（メタデータ焼き込み）→ カメラロール保存 → commit → 閉じる。
    private func handleSave(rawClip: URL?, comment: String, range: ClosedRange<Double>?) async {
        let device = DeviceInfo.current()
        let finalClip = await Self.finalizedClip(rawClip, range: range, comment: comment, device: device)
        if let finalClip {
            await Self.saveClipToPhotos(finalClip)
        }
        await commit(comment: comment, clip: finalClip, device: device)
        presenter.dismissReport()
        flashStatus(finalClip != nil ? "保存しました ✅" : "送信しました ✅")
    }

    /// 共有: 選択範囲を切り出し（メタデータ焼き込み）→ commit → 共有シート用の URL を返す。
    /// UI 側が `UIActivityViewController` を提示する（端末保存・AirDrop 等はそちらで選択）。
    private func handleShare(rawClip: URL?, comment: String, range: ClosedRange<Double>?) async -> URL? {
        let device = DeviceInfo.current()
        let finalClip = await Self.finalizedClip(rawClip, range: range, comment: comment, device: device)
        await commit(comment: comment, clip: finalClip, device: device)
        return finalClip
    }

    /// ホストへ成果物を手渡し（onReport）、Slack へ送る。提示ごとに一度だけ実行する。
    private func commit(comment: String, clip: URL?, device: DeviceInfo) async {
        guard !hasCommitted else { return }
        hasCommitted = true
        do {
            let report = try await configuration.reportGenerator.generate(
                comment: comment,
                device: device,
                clipURL: clip
            )
            onReport?(report)
            try await Self.deliver(report: report, webhookURL: configuration.slackWebhookURL)
        } catch {
            FlashbackLog.report.error("レポート処理に失敗: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 一時的なステータス文言を出して数秒後に消す。
    private func flashStatus(_ message: String) {
        presenter.showStatus(message)
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            presenter.showStatus("")
        }
    }

    /// 選択範囲（秒）で切り出し、タイトル=コメント/説明=端末情報のメタデータを焼き込み、
    /// ファイル名をコメント由来にした最終クリップを返す。範囲・クリップが無い、または
    /// 処理失敗時は元のクリップをそのまま返す（送信は止めない）。
    private static func finalizedClip(
        _ clipURL: URL?,
        range: ClosedRange<Double>?,
        comment: String,
        device: DeviceInfo
    ) async -> URL? {
        guard let clipURL, let range else { return clipURL }
        #if canImport(AVFoundation)
        do {
            let metadata = ClipTrimmer.metadata(
                title: comment,
                description: "\(device.displayModel) / \(device.systemName) \(device.systemVersion)"
            )
            let outputName = comment.isEmpty ? nil : ClipTrimmer.sanitizedFileName(comment)
            return try await ClipTrimmer.trim(
                clipURL,
                fromSeconds: range.lowerBound,
                toSeconds: range.upperBound,
                metadata: metadata,
                outputName: outputName
            )
        } catch {
            FlashbackLog.report.error("クリップ書き出しに失敗（フル尺で継続）: \(error.localizedDescription, privacy: .public)")
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
