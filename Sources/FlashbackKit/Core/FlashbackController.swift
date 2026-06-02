import Foundation

/// 各責務（録画 / トリガ検知 / レポート / 送信）を束ねる調整役。
@MainActor
final class FlashbackController {
    static let shared = FlashbackController()

    private var configuration = FlashbackConfiguration()
    private let recorder = ScreenRecorder()
    private let presenter = FlashbackPresenter()
    private var detectors: [TriggerDetecting] = []
    /// 成果物 `FlashbackReport` をホストへ手渡すコールバック（唯一の拡張点）。
    private var onReport: (@MainActor (FlashbackReport) -> Void)?
    /// 1 回の提示につき onReport を一度だけ発火させるためのフラグ
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
    /// `clipURL` が nil なら「おやすみ（録画オフ）」状態を確認できる。
    func debugPresentReport(clipURL: URL?) {
        present(rawClip: clipURL)
    }

    /// DEBUG 専用: 進行中トーストを表示する（見た目確認用）。
    func debugShowProgressToast() {
        presenter.showProgress("記憶を辿っています…")
    }

    /// DEBUG 専用: 失敗トーストを表示する（再試行はトーストを閉じるだけ）。
    func debugShowFailureToast() {
        presenter.showFailure("記憶の書き出しに失敗しました") { [weak self] in
            self?.presenter.hideToast()
        }
    }
    #endif

    /// トリガー（シェイク / フローティングボタン）→ 進行中トーストを出して直前クリップを
    /// 書き出し → プレビュー＋トリミング付きのレポート UI を提示。
    ///
    /// トースト方針（README 準拠・成功トーストは出さない）:
    /// - 書き出し中: 「記憶を辿っています…」（オレンジのスピナー）。
    /// - 成功: トーストを消して ReportView（クリップ有）。
    /// - 録画不可/オフ（`recordingUnavailable`）: トースト無しで おやすみ ReportView へ。
    /// - その他の書き出し失敗: 「記憶の書き出しに失敗しました」＋再試行（自動では閉じない）。
    private func handleTrigger() {
        presenter.showProgress("記憶を辿っています…")
        Task {
            do {
                let clipURL = try await recorder.exportBufferedClip()
                presenter.hideToast()
                present(rawClip: clipURL)
            } catch FlashbackError.recordingUnavailable {
                // 録画オフ / Simulator / 直前バッファ無し: 罰を与えず おやすみ案内へ（トースト無し）。
                presenter.hideToast()
                present(rawClip: nil)
            } catch {
                FlashbackLog.report.error("クリップ書き出しに失敗: \(error.localizedDescription, privacy: .public)")
                presenter.showFailure("記憶の書き出しに失敗しました") { [weak self] in
                    self?.handleTrigger()                      // 再試行 = 書き出しからやり直す。
                }
            }
        }
    }

    /// レポート UI を提示する。共有 / 設定 の 2 アクションを配線する。
    /// おやすみ（クリップ無し）状態では成果物を確定しない（onReport を発火しない）。
    private func present(rawClip: URL?) {
        hasCommitted = false
        presenter.presentReport(
            clipURL: rawClip,
            onShare: { [weak self] title, range in
                await self?.handleShare(rawClip: rawClip, title: title, range: range)
            },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
    }

    /// 設定を開く（歯車 / おやすみ状態の「録画をオンにする」）。
    /// TODO: Settings 画面（次タスク）を push する。現状はプレースホルダ（ログのみ）。
    private func openSettings() {
        FlashbackLog.report.info("設定を開く（Settings 画面は次タスクで実装予定）")
    }

    /// 共有: 選択範囲を切り出し（メタデータ焼き込み）→ commit → 共有シート用の URL を返す。
    /// 端末保存（写真）・AirDrop 等は OS 標準シート（`UIActivityViewController`）側で選ぶ。
    private func handleShare(rawClip: URL?, title: String, range: ClosedRange<Double>?) async -> URL? {
        let device = DeviceInfo.current()
        let finalClip = await Self.finalizedClip(rawClip, range: range, title: title, device: device)
        commit(title: title, clip: finalClip, device: device)
        return finalClip
    }

    /// 成果物 `FlashbackReport` をホストへ手渡す（onReport）。提示ごとに一度だけ実行する。
    /// AI 要約・Slack 送信・自社連携はホスト側の責務（onReport が唯一の拡張点）。
    private func commit(title: String, clip: URL?, device: DeviceInfo) {
        guard !hasCommitted else { return }
        hasCommitted = true
        onReport?(FlashbackReport(title: title, device: device, clipURL: clip))
    }

    /// 選択範囲（秒）で切り出し、タイトル/説明=端末情報のメタデータを焼き込み、
    /// ファイル名をタイトル由来にした最終クリップを返す。範囲・クリップが無い、または
    /// 処理失敗時は元のクリップをそのまま返す（処理は止めない）。
    private static func finalizedClip(
        _ clipURL: URL?,
        range: ClosedRange<Double>?,
        title: String,
        device: DeviceInfo
    ) async -> URL? {
        guard let clipURL, let range else { return clipURL }
        #if canImport(AVFoundation)
        do {
            let metadata = ClipTrimmer.metadata(
                title: title,
                description: "\(device.displayModel) / \(device.systemName) \(device.systemVersion)"
            )
            let outputName = title.isEmpty ? nil : ClipTrimmer.sanitizedFileName(title)
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
}
