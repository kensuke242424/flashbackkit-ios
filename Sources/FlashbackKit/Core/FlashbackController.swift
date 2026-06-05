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

        // シミュレータでは既定で起動しない（ReplayKit 実録画が不可なため）。
        // 使えない FAB の常駐やオンボーディングの煩わしさを避ける。SDK の UI をシムで
        // 確認したい場合のみ `runsOnSimulator = true`（Example アプリは true）。
        #if targetEnvironment(simulator)
        guard configuration.runsOnSimulator else {
            FlashbackLog.lifecycle.info("Simulator では起動しません（runsOnSimulator=false）。実機でお試しください。")
            return
        }
        #endif

        // 保持秒数も設定の永続値があれば採用（retentionOptions 外の不正値は無視して config 既定へ）。
        // 起動時バッファ・Store 初期値・以降の ring（setRetention / retry）をこの値で揃える。
        let bufferSeconds: TimeInterval = {
            if let saved = UserDefaults.standard.object(forKey: FlashbackSettingsStore.retentionSecondsKey) as? Int,
               FlashbackSettingsStore.retentionOptions.contains(saved) {
                return TimeInterval(saved)
            }
            return configuration.bufferSeconds
        }()
        self.configuration.bufferSeconds = bufferSeconds

        // 起動時録画は既定オフ（OS ダイアログを起動時に出さない）。設定トグルの永続値が
        // あればそれを、無ければ config 既定（既定 false）を採用。オンの時だけ起動時バッファ開始。
        let promptOnLaunch = (UserDefaults.standard.object(forKey: FlashbackSettingsStore.promptOnLaunchKey) as? Bool)
            ?? configuration.promptOnLaunch
        if promptOnLaunch {
            recorder.startBuffering(seconds: bufferSeconds)
        }
        // overlay 設置がシーン未接続で保留された場合、シーン接続後に triggerHost 依存の FAB を
        // 改めて載せる（SceneDelegate アプリで didFinishLaunching から start() を呼んでも UI が出る）。
        presenter.onDeferredInstall = { [weak self] in self?.handleDeferredOverlayInstall() }
        presenter.install()

        settingsStore = FlashbackSettingsStore(
            floatingButtonVisible: configuration.triggers.contains(.floatingButton),
            retentionSeconds: Int(bufferSeconds),
            promptOnLaunch: promptOnLaunch,
            isRecordingActive: recorder.isRecording,
            isRecordingAvailable: { [weak self] in self?.recorder.isAvailable ?? false },
            onFloatingButtonVisibleChanged: { [weak self] in self?.setFloatingButton($0) },
            onRetentionChanged: { [weak self] in self?.setRetention($0) },
            onRetryRecording: { [weak self] in self?.retryRecording() },
            onStopRecording: { [weak self] in self?.recorder.stopBuffering() },
            onPromptOnLaunchChanged: { [weak self] in self?.setPromptOnLaunch($0) }
        )
        // 録画の確定状態（許可後だけ true）を設定ストアへ常駐反映。UI が自動更新される。
        recorder.onRecordingStateChanged = { [weak self] active in
            guard let store = self?.settingsStore else { return }
            store.isRecordingActive = active
            // 録画オフに確定したら「録画オン直後（justEnabled）」も解除（停止後に
            // ReportView が「録画をオンにしました」のまま残らないように）。
            if !active { store.recordingJustEnabled = false }
            // FAB の色を録画状態へ反映（録画中＝オレンジ／停止中＝グレー）。
            #if canImport(UIKit)
            self?.floatingButtonTrigger?.setRecordingEnabled(active)
            #endif
        }
        // 外部キャプチャ（画面収録/ミラーリング等）での中断・自動再開を、専用トーストで知らせる。
        recorder.onExternalCaptureInterrupt = { [weak self] interrupted in
            self?.presenter.showInfo(interrupted ? "画面収録のため録画を中断しました" : "録画を再開しました")
        }

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

    /// overlay 設置が（シーン未接続で）保留→シーン接続後に完了した時に呼ばれる。
    /// triggerHost 依存の FAB を（構成に含まれ・未設置なら）改めて設置する。
    /// シェイクは CoreMotion ベースで window 非依存のため、ここでの再設置は不要。
    private func handleDeferredOverlayInstall() {
        #if canImport(UIKit)
        if configuration.triggers.contains(.floatingButton) {
            installFloatingButton()
        }
        #endif
    }

    // MARK: - 設定の適用

    /// フローティングボタンの表示/非表示を切り替える（設定トグル）。
    private func setFloatingButton(_ visible: Bool) {
        #if canImport(UIKit)
        if visible {
            installFloatingButton()
        } else {
            removeFloatingButton()
            maybeShowShakeHint()
        }
        #endif
    }

    /// FAB を OFF にした直後、「2回シェイクで起動」ヒントを端末1回だけ提示する。
    /// シェイク導線が無い構成では起動手段の案内にならないため出さない。既読（hasSeenShakeHint）でも出さない。
    /// 設定トグルの更新中に提示すると遷移が競合し得るため、次の run loop へ送ってから提示する。
    private func maybeShowShakeHint() {
        guard let store = settingsStore else { return }
        guard configuration.triggers.contains(.shake) else { return }
        guard !store.hasSeenShakeHint else { return }
        store.hasSeenShakeHint = true
        Task { @MainActor in self.presenter.presentShakeHint() }
    }

    /// 起動時録画確認トグルの反映。ON にしたら今すぐバッファ開始（冪等）も行い、以降の起動でも
    /// 効くよう永続値は Store 側で保存済み。OFF は現在の録画を止めない（「起動時に確認するか」の設定）。
    private func setPromptOnLaunch(_ on: Bool) {
        if on { recorder.startBuffering(seconds: configuration.bufferSeconds) }
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
            if started {
                self.settingsStore?.recordingJustEnabled = true
                // 開始のフィードバック。FAB 起こし時はトーストが見え、ReportView「録画をオンにする」
                // 経由ではシート裏（justEnabled の表示が前面）に出るので二重感は出ない。
                self.presenter.showInfo("録画を開始しました")
            }
        }
        FlashbackLog.lifecycle.info("retryRecording 実行（再ダイアログ可否は iOS 版依存）")
        recorder.startBuffering(seconds: configuration.bufferSeconds)
    }

    #if canImport(UIKit)
    /// FAB のグレー（録画オフ）タップから録画をオンにする。端末で初回はプライミング（事前説明）を
    /// 挟んでから OS 確認へ、2回目以降は直接 `retryRecording`（OS 確認）。レポートを開かない FAB
    /// 導線でも ReportView の「録画をオンにする」と同じ初回プライミング体験を保つ。
    private func wakeRecordingFromFloatingButton() {
        guard let settingsStore else { return }
        guard !settingsStore.hasPrimedScreenRecording else {
            retryRecording()
            return
        }
        presenter.presentPriming(
            onProceed: { [weak self] in
                self?.settingsStore?.hasPrimedScreenRecording = true
                self?.presenter.dismissReport()
                self?.retryRecording()
            },
            onLater: { [weak self] in self?.presenter.dismissReport() }
        )
    }

    /// FAB トリガを生成・配線・設置する（トースト早出し含む）。
    private func installFloatingButton() {
        guard floatingButtonTrigger == nil, let host = presenter.triggerHost else { return }
        // 初期色は実録画状態に合わせる（起動時録画 既定オフなら最初はグレー）。
        let fab = FloatingButtonTrigger(host: host, corner: configuration.floatingButtonCorner,
                                        recordingEnabled: recorder.isRecording)
        fab.onTrigger = { [weak self] in self?.handleTrigger() }
        // 進行中トーストは長押し開始時点で早出し（発火直後はモーダルで一瞬になり見えないため）。
        // ただし**録画OFF時は出さない**（書き出すものが無く、おやすみ案内へ直行するため・README 準拠）。
        // 未発火で中断（早離し / ドラッグ）したら消す。
        fab.onPressStart = { [weak self] in
            guard let self, self.recorder.isRecording else { return }
            self.presenter.showProgress("記憶を辿っています…")
        }
        // 早出しした「進行中」トーストだけを取り消す（info ヒントは消さない）。短タップ時は
        // handleTap が先に出した「長押しでレポート起動」ヒントを、直後の指離れで消さないため。
        fab.onPressCancel = { [weak self] in self?.presenter.hideProgressToast() }
        // 録画オフ（グレー）でのタップ＝録画オン（起こす）。初見でも長押しを思いつかずに済む導線。
        // 端末で初回はプライミング（事前説明）を挟んでから OS 確認へ。
        fab.onWake = { [weak self] in self?.wakeRecordingFromFloatingButton() }
        // 録画オン（オレンジ）での短タップ＝無反応で終わらせず長押しを促すヒント。
        fab.onShortTapHint = { [weak self] in self?.presenter.showInfo("長押しでレポート起動") }
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
            promptOnLaunch: false,
            isRecordingActive: false,
            isRecordingAvailable: { false },
            onFloatingButtonVisibleChanged: { _ in },
            onRetentionChanged: { _ in },
            onRetryRecording: {},
            onStopRecording: {},
            onPromptOnLaunchChanged: { _ in }
        )
        presenter.presentReport(clipURL: nil, onShare: { _, _ in nil }, settings: stub)
    }

    /// DEBUG 専用: 許可プライミングのシートを単体提示する（見た目確認用）。
    func debugPresentPriming() {
        presenter.presentPriming(
            onProceed: { [weak self] in
                self?.settingsStore?.hasPrimedScreenRecording = true
                self?.presenter.dismissReport()
                self?.settingsStore?.retryRecording()
            },
            onLater: { [weak self] in self?.presenter.dismissReport() }
        )
    }

    /// DEBUG 専用: プライミング既読フラグ（hasPrimed）をリセットする（実機での再テスト用）。
    func debugResetPriming() {
        settingsStore?.hasPrimedScreenRecording = false
    }

    /// DEBUG 専用: 「2回シェイクで起動」ヒントを最前面へ提示する（見た目確認用）。
    /// 既読フラグは立てない（何度でも確認できる）。事前に `Flashback.start()` で overlay window が必要。
    func debugPresentShakeHint() {
        presenter.presentShakeHint()
    }

    /// DEBUG 専用: シェイクヒント既読フラグ（hasSeenShakeHint）をリセットする（実機での再テスト用）。
    func debugResetShakeHint() {
        settingsStore?.hasSeenShakeHint = false
    }

    /// DEBUG 専用: 録画状態の一行ステータス（割り込み検知の挙動を実機で観察する用）。
    func debugRecordingStatusLine() -> String {
        let age = recorder.debugFrameAge.map { String(format: "%.1f", $0) } ?? "—"
        let marks = recorder.debugInAppMarksCaptured.map { $0 ? "YES" : "no" } ?? "?"
        let sysRec = recorder.debugSystemIsRecording ? "ON" : "off"
        return "rec=\(recorder.isRecording ? "ON" : "off")  sysRec=\(sysRec)  age=\(age)s  isCaptured=\(recorder.debugScreenIsCaptured ? "YES" : "no")  marks=\(marks)  errs=\(recorder.debugCaptureErrorCount)\nwake=[\(recorder.debugWakeSnapshot)]"
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
