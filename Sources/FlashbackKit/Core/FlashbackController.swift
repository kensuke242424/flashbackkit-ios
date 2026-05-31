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
    func debugPresentReport(clipURL: URL) {
        present(rawClip: clipURL)
    }
    #endif

    /// トリガー（シェイク / フローティングボタン）→ 直前クリップを書き出してから
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

    /// レポート UI を提示する。完了（クリップ無し時）/ 共有 の 2 アクションを配線する。
    private func present(rawClip: URL?) {
        hasCommitted = false
        presenter.presentReport(
            clipURL: rawClip,
            onComplete: { [weak self] title in
                await self?.handleComplete(title: title)
            },
            onShare: { [weak self] title, range in
                await self?.handleShare(rawClip: rawClip, title: title, range: range)
            }
        )
    }

    /// 完了: クリップが無い（録画不可 / Simulator）場合の確定。成果物を commit して閉じる。
    private func handleComplete(title: String) async {
        commit(title: title, clip: nil, device: DeviceInfo.current())
        presenter.dismissReport()
        flashStatus("完了しました ✅")
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

    /// 一時的なステータス文言を出して数秒後に消す。
    private func flashStatus(_ message: String) {
        presenter.showStatus(message)
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            presenter.showStatus("")
        }
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
