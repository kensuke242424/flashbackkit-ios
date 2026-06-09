import Foundation

/// Coordinator that ties together recording, trigger detection, reporting, and sending.
@MainActor
final class FlashbackController {
    static let shared = FlashbackController()

    private var configuration = FlashbackConfiguration()
    private let recorder = ScreenRecorder()
    private let presenter = FlashbackPresenter()
    private var detectors: [TriggerDetecting] = []
    /// Settings store (visibility toggles / retention seconds / permissions).
    /// Created in start() and handed to the settings UI on presentation.
    private var settingsStore: FlashbackSettingsStore?
    #if canImport(UIKit)
    /// Reference to the FAB trigger, kept so it can be added/removed dynamically.
    private var floatingButtonTrigger: FloatingButtonTrigger?
    #endif
    /// Callback that hands the finished `FlashbackReport` to the host (the only extension point).
    private var onReport: (@MainActor (FlashbackReport) -> Void)?
    /// Fires onReport at most once per presentation, so saving and sharing don't double-commit.
    private var hasCommitted = false

    private init() {}

    func start(
        configuration: FlashbackConfiguration,
        onReport: (@MainActor (FlashbackReport) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.onReport = onReport
        guard configuration.isEnabled else { return }

        // Don't start on the Simulator by default (ReplayKit can't actually record there),
        // which avoids a dead FAB and onboarding noise. Set `runsOnSimulator = true` only to
        // check the SDK's UI on the Simulator (the Example app sets it true).
        #if targetEnvironment(simulator)
        guard configuration.runsOnSimulator else {
            FlashbackLog.lifecycle.info("Simulator では起動しません（runsOnSimulator=false）。実機でお試しください。")
            return
        }
        #endif

        // Prefer the persisted retention value if present (ignore values outside
        // retentionOptions and fall back to the config default). This value drives the
        // launch buffer, the store's initial value, and later rings (setRetention / retry).
        let bufferSeconds: TimeInterval = {
            if let saved = UserDefaults.standard.object(forKey: FlashbackSettingsStore.retentionSecondsKey) as? Int,
               FlashbackSettingsStore.retentionOptions.contains(saved) {
                return TimeInterval(saved)
            }
            return configuration.bufferSeconds
        }()
        self.configuration.bufferSeconds = bufferSeconds

        // Recording at launch is off by default (no OS dialog on launch). Prefer the
        // persisted toggle, else the config default (false). Only start the launch buffer when on.
        let promptOnLaunch = (UserDefaults.standard.object(forKey: FlashbackSettingsStore.promptOnLaunchKey) as? Bool)
            ?? configuration.promptOnLaunch
        if promptOnLaunch {
            recorder.startBuffering(seconds: bufferSeconds)
        }
        // Whether to exclude the launch button/toast from OS capture. Default true (not captured).
        // Prefer the persisted toggle. Passing it to the presenter before install applies it via
        // finishInstall (including the deferred-install path).
        let excludesButtonFromCapture = (UserDefaults.standard.object(forKey: FlashbackSettingsStore.excludesButtonFromCaptureKey) as? Bool)
            ?? true
        presenter.setExcludesContentFromCapture(excludesButtonFromCapture)

        // If overlay install was deferred (no scene connected yet), re-add the
        // triggerHost-dependent FAB once a scene connects, so the UI still appears even when a
        // SceneDelegate app calls start() from didFinishLaunching.
        presenter.onDeferredInstall = { [weak self] in self?.handleDeferredOverlayInstall() }
        presenter.install()

        settingsStore = FlashbackSettingsStore(
            floatingButtonVisible: configuration.triggers.contains(.floatingButton),
            retentionSeconds: Int(bufferSeconds),
            promptOnLaunch: promptOnLaunch,
            excludesButtonFromCapture: excludesButtonFromCapture,
            isRecordingActive: recorder.isRecording,
            isRecordingAvailable: { [weak self] in self?.recorder.isAvailable ?? false },
            onFloatingButtonVisibleChanged: { [weak self] in self?.setFloatingButton($0) },
            onRetentionChanged: { [weak self] in self?.setRetention($0) },
            onRetryRecording: { [weak self] in self?.retryRecording() },
            onStopRecording: { [weak self] in self?.recorder.stopBuffering() },
            onPromptOnLaunchChanged: { [weak self] in self?.setPromptOnLaunch($0) },
            onExcludesButtonFromCaptureChanged: { [weak self] in self?.presenter.setExcludesContentFromCapture($0) }
        )
        // Mirror the confirmed recording state (true only after permission) into the store,
        // so the UI updates automatically.
        recorder.onRecordingStateChanged = { [weak self] active in
            guard let store = self?.settingsStore else { return }
            store.isRecordingActive = active
            // Once recording is confirmed off, clear justEnabled too, so the ReportView
            // doesn't stay showing the just-enabled state after a stop.
            if !active { store.recordingJustEnabled = false }
            // Reflect recording state in the FAB color (recording = orange / stopped = gray).
            #if canImport(UIKit)
            self?.floatingButtonTrigger?.setRecordingEnabled(active)
            #endif
        }
        // Notify, via a dedicated toast, of interruption/auto-resume from external capture
        // (screen recording, mirroring, etc.).
        recorder.onExternalCaptureInterrupt = { [weak self] interrupted in
            self?.presenter.showInfo(interrupted ? "画面収録のため録画を中断しました" : "録画を再開しました")
        }

        // Wire up shake immediately. The FAB is managed separately for dynamic add/remove.
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

    /// Called when a deferred overlay install (no scene connected) completes after a scene
    /// connects. Re-installs the triggerHost-dependent FAB if it's in the config and not yet
    /// installed. Shake is CoreMotion-based and window-independent, so it needs no re-install here.
    private func handleDeferredOverlayInstall() {
        #if canImport(UIKit)
        if configuration.triggers.contains(.floatingButton) {
            installFloatingButton()
        }
        #endif
    }

    // MARK: - Applying settings

    /// Shows/hides the floating button (settings toggle).
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

    /// Right after turning the FAB off, show the shake-to-launch hint once per device. Skipped
    /// when shake isn't in the config (it wouldn't point to a usable launch path) or already seen
    /// (hasSeenShakeHint). Deferred to the next run loop to avoid colliding with the toggle update.
    private func maybeShowShakeHint() {
        guard let store = settingsStore else { return }
        guard configuration.triggers.contains(.shake) else { return }
        guard !store.hasSeenShakeHint else { return }
        store.hasSeenShakeHint = true
        Task { @MainActor in self.presenter.presentShakeHint() }
    }

    /// Applies the prompt-on-launch toggle. When turned on, also starts the buffer now
    /// (idempotent); the persisted value is saved by the store so it sticks across launches.
    /// Turning it off does not stop current recording (it's a "prompt on launch?" setting).
    private func setPromptOnLaunch(_ on: Bool) {
        if on { recorder.startBuffering(seconds: configuration.bufferSeconds) }
    }

    /// Applies the selected retention seconds. Swaps the ring without stopping ReplayKit, since
    /// a stop→immediate-start churn crashes due to ReplayKit's async stop.
    private func setRetention(_ seconds: Int) {
        configuration.bufferSeconds = TimeInterval(seconds)
        recorder.changeBufferSeconds(configuration.bufferSeconds)
    }

    /// Retries recording (late permission after a denial / "turn recording on" from the idle state).
    /// `startBuffering` is idempotent; `startCapture` is re-run only when recording is stopped
    /// (denied / not started), aiming to re-show the iOS permission dialog (on OS versions that
    /// don't re-show it, an app restart is needed).
    ///
    /// On a successful capture start, optimistically switch the ReportView to the just-enabled
    /// state. If the dialog isn't re-shown it won't start and stays idle (the "please restart the
    /// app" guidance is a separate task, untested on device).
    private func retryRecording() {
        recorder.onCaptureStarted = { [weak self] started in
            guard let self else { return }
            self.recorder.onCaptureStarted = nil          // One-shot
            FlashbackLog.lifecycle.info("retryRecording 結果: \(started ? "成功（justEnabled へ遷移）" : "失敗（おやすみ維持）", privacy: .public)")
            if started {
                self.settingsStore?.recordingJustEnabled = true
                // Start feedback. From an FAB wake the toast is visible; via the ReportView's
                // "turn recording on" it appears behind the sheet (justEnabled is in front), so it
                // doesn't feel duplicated.
                self.presenter.showInfo("録画を開始しました")
            }
        }
        FlashbackLog.lifecycle.info("retryRecording 実行（再ダイアログ可否は iOS 版依存）")
        recorder.startBuffering(seconds: configuration.bufferSeconds)
    }

    #if canImport(UIKit)
    /// Turns recording on from a gray (recording-off) FAB tap. On the first time per device,
    /// show priming first, then the OS prompt; afterwards go straight to `retryRecording` (OS
    /// prompt). Keeps the same first-time priming experience as the ReportView's "turn recording
    /// on", even on the FAB path that doesn't open a report.
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

    /// Creates, wires, and installs the FAB trigger (including the early toast).
    private func installFloatingButton() {
        guard floatingButtonTrigger == nil, let host = presenter.triggerHost else { return }
        // Initial color matches the real recording state (gray at first if launch recording is off).
        let fab = FloatingButtonTrigger(host: host, corner: configuration.floatingButtonCorner,
                                        recordingEnabled: recorder.isRecording)
        fab.onTrigger = { [weak self] in self?.handleTrigger() }
        // Show the in-progress toast early, at press start (right after firing it's covered by the
        // modal and only flashes). But **not while recording is off** (nothing to export; we go
        // straight to the idle guidance). Hidden if the press is interrupted (early release / drag).
        fab.onPressStart = { [weak self] in
            guard let self, self.recorder.isRecording else { return }
            self.presenter.showProgress("記憶を辿っています…")
        }
        // Cancel only the early in-progress toast (not the info hint), so a short tap's
        // "long-press to launch a report" hint isn't dismissed by the immediate finger lift.
        fab.onPressCancel = { [weak self] in self?.presenter.hideProgressToast() }
        // Tap while recording is off (gray) = turn recording on (wake). A path that works even if
        // the user doesn't think to long-press. First time per device, priming precedes the OS prompt.
        fab.onWake = { [weak self] in self?.wakeRecordingFromFloatingButton() }
        // Short tap while recording is on (orange) = hint to long-press instead of a dead no-op.
        fab.onShortTapHint = { [weak self] in self?.presenter.showInfo("長押しでレポート起動") }
        fab.start()
        floatingButtonTrigger = fab
        detectors.append(fab)
    }

    /// Removes the FAB trigger.
    private func removeFloatingButton() {
        floatingButtonTrigger?.stop()
        if let fab = floatingButtonTrigger {
            detectors.removeAll { $0 === fab }
        }
        floatingButtonTrigger = nil
    }
    #endif

    #if DEBUG
    /// DEBUG only: presents the report UI directly with an arbitrary clip (to check the trim UX).
    /// Pass nil for `clipURL` to inspect the idle (recording-off) state.
    func debugPresentReport(clipURL: URL?) {
        present(rawClip: clipURL)
    }

    /// DEBUG only: immediately shows the report UI in the just-enabled state.
    /// Presents without a clip, then sets the justEnabled flag to check the orange mark + "recording".
    func debugPresentReportJustEnabled() {
        present(rawClip: nil)                              // present() resets it to false first, so…
        settingsStore?.recordingJustEnabled = true         // …set it after presenting to show justEnabled
    }

    /// DEBUG only: presents the report UI in the recording-unavailable (not available on this
    /// device) state. Uses a throwaway store with isAvailable=false to check the no-CTA guidance.
    func debugPresentReportUnavailable() {
        let stub = FlashbackSettingsStore(
            floatingButtonVisible: settingsStore?.floatingButtonVisible ?? true,
            retentionSeconds: settingsStore?.retentionSeconds ?? 20,
            promptOnLaunch: false,
            excludesButtonFromCapture: settingsStore?.excludesButtonFromCapture ?? true,
            isRecordingActive: false,
            isRecordingAvailable: { false },
            onFloatingButtonVisibleChanged: { _ in },
            onRetentionChanged: { _ in },
            onRetryRecording: {},
            onStopRecording: {},
            onPromptOnLaunchChanged: { _ in },
            onExcludesButtonFromCaptureChanged: { _ in }
        )
        presenter.presentReport(clipURL: nil, onShare: { _, _ in nil }, settings: stub)
    }

    /// DEBUG only: presents the permission-priming sheet on its own (to check its appearance).
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

    /// DEBUG only: resets the priming-seen flag (hasPrimed) for re-testing on a device.
    func debugResetPriming() {
        settingsStore?.hasPrimedScreenRecording = false
    }

    /// DEBUG only: presents the shake-to-launch hint at the front (to check its appearance).
    /// Doesn't set the seen flag (can be checked repeatedly). Requires the overlay window from a
    /// prior `Flashback.start()`.
    func debugPresentShakeHint() {
        presenter.presentShakeHint()
    }

    /// DEBUG only: resets the shake-hint-seen flag (hasSeenShakeHint) for re-testing on a device.
    func debugResetShakeHint() {
        settingsStore?.hasSeenShakeHint = false
    }

    /// DEBUG only: one-line recording status (to observe interrupt-detection behavior on a device).
    func debugRecordingStatusLine() -> String {
        let age = recorder.debugFrameAge.map { String(format: "%.1f", $0) } ?? "—"
        let marks = recorder.debugInAppMarksCaptured.map { $0 ? "YES" : "no" } ?? "?"
        let sysRec = recorder.debugSystemIsRecording ? "ON" : "off"
        return "rec=\(recorder.isRecording ? "ON" : "off")  sysRec=\(sysRec)  age=\(age)s  isCaptured=\(recorder.debugScreenIsCaptured ? "YES" : "no")  marks=\(marks)  errs=\(recorder.debugCaptureErrorCount)\nwake=[\(recorder.debugWakeSnapshot)]"
    }

    /// DEBUG only: shows the in-progress toast (to check its appearance).
    func debugShowProgressToast() {
        presenter.showProgress("記憶を辿っています…")
    }

    /// DEBUG only: shows the failure toast (retry just closes the toast).
    func debugShowFailureToast() {
        presenter.showFailure("記憶の書き出しに失敗しました") { [weak self] in
            self?.presenter.hideToast()
        }
    }

    /// DEBUG only: presents the settings screen on its own (to check its appearance). Call after start().
    func debugPresentSettings() {
        guard let settingsStore else { return }
        presenter.debugPresentSettings(store: settingsStore)
    }
    #endif

    /// Trigger (shake / floating button) → show the in-progress toast, export the most recent
    /// clip → present the report UI with preview and trimming.
    ///
    /// Toast policy (no success toast):
    /// - Exporting: in-progress toast (orange spinner).
    /// - Success: hide the toast and show the ReportView (with clip).
    /// - Recording unavailable/off (`recordingUnavailable`): no toast, go to the idle ReportView.
    /// - Other export failures: failure toast + retry (doesn't auto-dismiss).
    private func handleTrigger() {
        // Recording off: nothing to export. No toast (clear any early one) and go straight to idle.
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
                // Recording off / Simulator / no recent buffer: go to idle guidance without penalty (no toast).
                presenter.hideToast()
                present(rawClip: nil)
            } catch {
                FlashbackLog.report.error("クリップ書き出しに失敗: \(error.localizedDescription, privacy: .public)")
                presenter.showFailure("記憶の書き出しに失敗しました") { [weak self] in
                    self?.handleTrigger()                      // Retry = redo from the export.
                }
            }
        }
    }

    /// Presents the report UI, passing the share action and the settings store (gear / recording-on).
    /// In the idle (no-clip) state, no report is committed (onReport doesn't fire).
    private func present(rawClip: URL?) {
        guard let settingsStore else { return }
        hasCommitted = false
        settingsStore.recordingJustEnabled = false        // Start from the idle baseline each time (justEnabled only on a successful retry)
        presenter.presentReport(
            clipURL: rawClip,
            onShare: { [weak self] title, range in
                await self?.handleShare(rawClip: rawClip, title: title, range: range)
            },
            settings: settingsStore
        )
    }

    /// Share: trim the selected range (with metadata baked in) → commit → return the URL for the
    /// share sheet. Saving to the device (Photos), AirDrop, etc. are chosen in the OS share sheet
    /// (`UIActivityViewController`).
    private func handleShare(rawClip: URL?, title: String, range: ClosedRange<Double>?) async -> URL? {
        let device = DeviceInfo.current()
        let finalClip = await Self.finalizedClip(rawClip, range: range, title: title, device: device)
        commit(title: title, clip: finalClip, device: device)
        return finalClip
    }

    /// Hands the finished `FlashbackReport` to the host (onReport), at most once per presentation.
    /// AI summarization, Slack delivery, and in-house integration are the host's responsibility
    /// (onReport is the only extension point).
    private func commit(title: String, clip: URL?, device: DeviceInfo) {
        guard !hasCommitted else { return }
        hasCommitted = true
        onReport?(FlashbackReport(title: title, device: device, clipURL: clip))
    }

    /// Trims to the selected range (seconds), bakes in metadata (title / description = device
    /// info), and returns the final clip with a title-derived filename. If the range or clip is
    /// missing, or processing fails, returns the original clip unchanged (doesn't halt).
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
            let outputName = title.isEmpty
                ? ClipTrimmer.fallbackName(kind: "video")
                : ClipTrimmer.sanitizedFileName(title)
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
