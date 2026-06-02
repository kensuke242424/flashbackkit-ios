import Foundation

/// 各責務（録画 / トリガ検知 / レポート / 送信）を束ねる調整役。
@MainActor
final class FlashbackController {
    static let shared = FlashbackController()

    private var configuration = FlashbackConfiguration()
    private let recorder = ScreenRecorder()
    private let presenter = FlashbackPresenter()
    private var detectors: [TriggerDetecting] = []
    /// 設定画面のストア（表示トグル / 保持秒数 / 権限）。start() で生成し提示時に渡す。
    private var settingsStore: FlashbackSettingsStore?
    #if canImport(UIKit)
    /// 動的に追加 / 撤去するため FAB トリガへの参照を保持する。
    private var floatingButtonTrigger: FloatingButtonTrigger?
    #endif
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

        settingsStore = FlashbackSettingsStore(
            floatingButtonVisible: configuration.triggers.contains(.floatingButton),
            retentionSeconds: Int(configuration.bufferSeconds),
            isRecordingAvailable: { [weak self] in self?.recorder.isAvailable ?? false },
            isRecording: { [weak self] in self?.recorder.isRecording ?? false },
            onFloatingButtonVisibleChanged: { [weak self] in self?.setFloatingButton($0) },
            onRetentionChanged: { [weak self] in self?.setRetention($0) },
            onRetryRecording: { [weak self] in self?.retryRecording() }
        )

        // シェイクは即時に配線。FAB は動的 add/remove のため別管理。
        var detectors: [TriggerDetecting] = []
        if configuration.triggers.contains(.shake) {
            let shake = ShakeTrigger()
            shake.onTrigger = { [weak self] in self?.handleTrigger() }
            shake.start()
            detectors.append(shake)
        }
        self.detectors = detectors

        #if canImport(UIKit)
        if configuration.triggers.contains(.floatingButton) {
            installFloatingButton()
        }
        #endif
    }

    func stop() {
        detectors.forEach { $0.stop() }
        detectors.removeAll()
        #if canImport(UIKit)
        floatingButtonTrigger = nil
        #endif
        settingsStore = nil
        recorder.stopBuffering()
        presenter.uninstall()
    }

    // MARK: - 設定の適用

    /// フローティングボタンの表示/非表示を切り替える（設定トグル）。
    private func setFloatingButton(_ visible: Bool) {
        #if canImport(UIKit)
        if visible { installFloatingButton() } else { removeFloatingButton() }
        #endif
    }

    /// 保持秒数を反映する（設定の選択）。ReplayKit を止めず ring を差し替えて即時適用する。
    /// 旧実装の stop→即 start は ReplayKit 停止の非同期性でクラッシュしたため変更。
    private func setRetention(_ seconds: Int) {
        configuration.bufferSeconds = TimeInterval(seconds)
        recorder.changeBufferSeconds(configuration.bufferSeconds)
    }

    /// 録画を再試行する（拒否後の後付け許可 / おやすみ状態の「録画をオンにする」）。
    /// `startBuffering` は冪等。録画が止まっている（拒否 / 未開始）時のみ `startCapture` を
    /// 再実行し、iOS の許可ダイアログが再度出ることを狙う（出ない版ではアプリ再起動が必要）。
    ///
    /// 取り込み開始が成立したら（楽観的遷移）ReportView を「録画オン直後（justEnabled）」へ
    /// 切り替える。許可ダイアログが再提示されない版では成立せず、おやすみのまま留まる
    /// （「アプリを再起動してください」案内は別タスク・実機未確認）。
    private func retryRecording() {
        recorder.onCaptureStarted = { [weak self] started in
            guard let self else { return }
            self.recorder.onCaptureStarted = nil          // ワンショット
            FlashbackLog.lifecycle.info("retryRecording 結果: \(started ? "成功（justEnabled へ遷移）" : "失敗（おやすみ維持）", privacy: .public)")
            if started { self.settingsStore?.recordingJustEnabled = true }
        }
        FlashbackLog.lifecycle.info("retryRecording 実行（再ダイアログ可否は iOS 版依存）")
        recorder.startBuffering(seconds: configuration.bufferSeconds)
    }

    #if canImport(UIKit)
    /// FAB トリガを生成・配線・設置する（トースト早出し含む）。
    private func installFloatingButton() {
        guard floatingButtonTrigger == nil, let host = presenter.triggerHost else { return }
        let fab = FloatingButtonTrigger(host: host, corner: configuration.floatingButtonCorner)
        fab.onTrigger = { [weak self] in self?.handleTrigger() }
        // 進行中トーストは長押し開始時点で早出し（発火直後はモーダルで一瞬になり見えないため）。
        // ただし**録画OFF時は出さない**（書き出すものが無く、おやすみ案内へ直行するため・README 準拠）。
        // 未発火で中断（早離し / ドラッグ）したら消す。
        fab.onPressStart = { [weak self] in
            guard let self, self.recorder.isRecording else { return }
            self.presenter.showProgress("記憶を辿っています…")
        }
        fab.onPressCancel = { [weak self] in self?.presenter.hideToast() }
        fab.start()
        floatingButtonTrigger = fab
        detectors.append(fab)
    }

    /// FAB トリガを撤去する。
    private func removeFloatingButton() {
        floatingButtonTrigger?.stop()
        if let fab = floatingButtonTrigger {
            detectors.removeAll { $0 === fab }
        }
        floatingButtonTrigger = nil
    }
    #endif

    #if DEBUG
    /// DEBUG 専用: 任意のクリップでレポート UI を直接提示する（トリム UX 確認用）。
    /// `clipURL` が nil なら「おやすみ（録画オフ）」状態を確認できる。
    func debugPresentReport(clipURL: URL?) {
        present(rawClip: clipURL)
    }

    /// DEBUG 専用: 「録画オン直後（justEnabled）」状態のレポート UI を即時表示する。
    /// クリップ無しで提示してから justEnabled フラグを立て、オレンジマーク＋「録画中」を確認する。
    func debugPresentReportJustEnabled() {
        present(rawClip: nil)                              // present() が一旦 false にリセットするので…
        settingsStore?.recordingJustEnabled = true         // …提示後に立てて justEnabled を表示させる
    }

    /// DEBUG 専用: 「録画不可（この端末では利用できません）」状態のレポート UI を提示する。
    /// isAvailable=false を強制した使い捨てストアで提示し、CTA 非表示の案内を確認する。
    func debugPresentReportUnavailable() {
        let stub = FlashbackSettingsStore(
            floatingButtonVisible: settingsStore?.floatingButtonVisible ?? true,
            retentionSeconds: settingsStore?.retentionSeconds ?? 20,
            isRecordingAvailable: { false },
            isRecording: { false },
            onFloatingButtonVisibleChanged: { _ in },
            onRetentionChanged: { _ in },
            onRetryRecording: {}
        )
        presenter.presentReport(clipURL: nil, onShare: { _, _ in nil }, settings: stub)
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

    /// DEBUG 専用: 設定画面を単体で提示する（見た目確認用）。start() 後に呼ぶ。
    func debugPresentSettings() {
        guard let settingsStore else { return }
        presenter.debugPresentSettings(store: settingsStore)
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
        // 録画OFF: 書き出すものが無い。トーストを出さず（早出し分も消し）おやすみ案内へ直行。
        guard recorder.isRecording else {
            presenter.hideToast()
            present(rawClip: nil)
            return
        }
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

    /// レポート UI を提示する。共有アクションと設定ストア（歯車 / 録画オン）を渡す。
    /// おやすみ（クリップ無し）状態では成果物を確定しない（onReport を発火しない）。
    private func present(rawClip: URL?) {
        guard let settingsStore else { return }
        hasCommitted = false
        settingsStore.recordingJustEnabled = false        // 毎回おやすみ基準で始める（justEnabled は retry 成立時のみ）
        presenter.presentReport(
            clipURL: rawClip,
            onShare: { [weak self] title, range in
                await self?.handleShare(rawClip: rawClip, title: title, range: range)
            },
            settings: settingsStore
        )
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
