#if canImport(ReplayKit)
import ReplayKit
import AVFoundation
import UIKit
import ImageIO

/// A ring buffer built on top of ReplayKit's in-app capture.
///
/// Important: ReplayKit cannot record retroactively. To keep the last N seconds,
/// `startBuffering` runs capture continuously, retaining only the most recent N
/// seconds as on-disk segments and discarding older ones. Capture start triggers
/// the system permission prompt once per session.
///
/// Design: this `@MainActor` type owns only the caller contract (driving
/// RPScreenRecorder, the availability gate); the actual encoding runs off the
/// main actor in `SegmentRingWriter` on a dedicated serial queue. The non-Sendable
/// `CMSampleBuffer` never hops to main — the capture background handler passes it
/// straight to the writer's queue.
@MainActor
final class ScreenRecorder: NSObject, RPScreenRecorderDelegate {
    private let recorder = RPScreenRecorder.shared()
    /// The current ring (@MainActor reference, used for export / teardown).
    private var ring: SegmentRingWriter?
    /// Holder for the "current ring" touched by the capture handler (background thread).
    /// The ring is swapped atomically under a lock, so the retention window can change
    /// **without stopping ReplayKit** (avoids stop→start churn).
    private let ringHolder = RingHolder()
    /// Whether a startCapture attempt is in flight (including before the permission
    /// dialog is answered). Internal state for idempotency / ring lifetime.
    private var isCapturing = false
    /// Whether capture is **confirmed** (true only after startCapture succeeds = post-permission).
    /// This drives the UI's "recording/stopped" state.
    private var captureConfirmed = false

    /// Intent to record (does the host/user want recording on?). False on explicit stop.
    /// Used to decide auto-resume after an interruption.
    private var wantsRecording = false
    /// Whether paused by an interruption (OS recording / mirroring etc.). Auto-resume on
    /// recovery only fires while this flag is set.
    private var interruptedBySystem = false
    /// Whether capture was paused because the app entered the background (#21 avoidance).
    /// Deliberately separate from `interruptedBySystem`: the external-capture machinery
    /// (`capturedDidChange` → `attemptResume`) must not consume a background pause while
    /// still backgrounded — `startCapture` fails before the app is active again, and the
    /// path's resume toast would misreport a normal lifecycle round-trip (#22). Cleared by
    /// the didBecomeActive restart.
    private var pausedForBackground = false

    /// Whether the secure-text-entry privacy guard is enabled (config default ⊕ settings
    /// toggle, via `setPausesForSecureTextEntry`). The in-app capture path sees everything
    /// the app renders — iOS's secure-field blanking protects external captures only — so by
    /// default capture pauses while a secure field is being edited, keeping passwords out
    /// of the clip.
    private(set) var pausesForSecureTextEntry = true
    /// Tracks which secure fields are currently being edited (begin/end editing notifications).
    private let secureEntryTracker = SecureEntryTracker()
    /// Whether capture is paused because a secure field is being edited. Separate from the
    /// background/interrupt flags for the same reason they are separate from each other:
    /// each pause has its own resume condition and consuming another path's flag strands
    /// recording off (#22).
    private var pausedForSecureEntry = false
    /// Last requested retention seconds, kept so auto-resume restarts with the same value.
    private var desiredBufferSeconds: TimeInterval = 0

    /// Whether the once-per-launch purge of leftover temp files has run. The purge targets
    /// `flashback-*` leftovers from a *previous* process, but `startBuffering` also runs on
    /// every resume (background round-trip, external-capture end, secure-entry end). Purging
    /// there deletes the already-exported clip backing a presented ReportView — save/share
    /// then operate on a dead file URL — so the purge must fire at most once per process.
    private static var didPurgeStaleTempFiles = false

    /// Watchdog monitoring frame supply. Stops as an interruption if supply stalls
    /// during external capture.
    private var watchdog: Task<Void, Never>?
    /// Idle seconds before a frame stall counts as an "interruption". Safe to keep short
    /// because the check is gated on external capture being present (on-device, a static
    /// screen still yields frames with age≈0; the age only spikes under external capture).
    /// 0.3s balances responsiveness against false triggers / churn from brief frame gaps.
    private static let stallThreshold: Double = 0.3
    /// Whether in-app recording itself sets `UIScreen.isCaptured` (device/iOS dependent).
    /// Probed once right after recording starts. If known `false`, a transition of
    /// `isCaptured` to true definitively means external capture started, so we can interrupt immediately.
    private var inAppMarksCaptured: Bool?

    /// Baseline interface orientation (`CGImagePropertyOrientation`) used by the watchdog to detect
    /// rotation. The watchdog compares the current orientation against this each tick; on a change it
    /// **restarts the capture session** so the new session begins at the new orientation's native
    /// dimensions (upright, correct aspect). Seeded at ring creation (startBuffering /
    /// changeBufferSeconds) and after a rotation restart. nil until the first seed.
    private var lastNotedOrientation: CGImagePropertyOrientation?

    /// Whether a rotation-driven capture-session restart is in flight (stop completion pending).
    /// Guards `restartCaptureForOrientationChange` against re-entry while the async stop→start
    /// hand-off is underway, and tells the watchdog to skip stall checks during the restart gap.
    private var isRestartingForOrientation = false

    /// Whether screen recording is available (false on Simulator, during a call, while
    /// another app is recording, etc.). There is no permission API to query in advance,
    /// so the settings screen's permission display relies on this availability.
    ///
    /// On the Simulator, ReplayKit in-app capture **does not work**. `isAvailable` returns
    /// `true` and `startCapture` reports "success" with `error=nil`, but **not a single
    /// video sample buffer arrives**. The API fakes success without emitting frames, so
    /// trusting it leaves the ring empty and produces empty clips. Letting `RPScreenRecorder`
    /// decide availability makes ReportView wrongly show "recording is off (with CTA)" instead
    /// of "recording unavailable", so on the Sim we pin it to false at compile time.
    /// (This is a different layer from `simctl io recordVideo` / QuickTime, which record the
    /// Sim screen host-side.)
    var isAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        recorder.isAvailable
        #endif
    }

    /// Whether recording is actually running (permission confirmed). Returns the
    /// **confirmed** state, not `isCapturing` (in-flight): false before the permission
    /// dialog is answered (never optimistically true). The source of truth for the UI's
    /// recording indicator and fire-ability.
    var isRecording: Bool { captureConfirmed }

    /// Persistent hook called on `@MainActor` whenever the confirmed recording state
    /// changes (shared by all start paths): true on confirmed success, false on stop/failure.
    /// Used to keep the settings screen's "recording/stopped" display in sync.
    /// (Distinct from the one-shot `onCaptureStarted` retry hook; this one is wired once in
    /// start() and stays resident.)
    var onRecordingStateChanged: ((Bool) -> Void)?

    /// `@MainActor` hook that notifies **only** interruption and auto-resume caused by
    /// external capture (OS screen recording / mirroring / calls). `true`=interrupted
    /// (stopped), `false`=resumed. A separate path from manual on/off, used to show the
    /// interrupt/resume toast.
    var onExternalCaptureInterrupt: ((Bool) -> Void)?

    /// Hook notifying the confirmed result of `startCapture` (for the justEnabled check right
    /// after turning recording on). Called on `@MainActor`. `true` = ingest started, `false` =
    /// failure (permission denied, etc.). Set only via retryRecording, and the caller is
    /// expected to clear it after one successful use.
    /// Note: passing a closure into ReplayKit's `@Sendable` handler risks an over-release
    /// crash, so the handler notifies via this property on `self` instead of boxing a closure.
    var onCaptureStarted: ((Bool) -> Void)?

    override init() {
        super.init()
        // Watch availability changes (calls etc.) and the start/end of external capture
        // (OS screen recording / mirroring).
        recorder.delegate = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenCaptureStateChanged),
            name: UIScreen.capturedDidChangeNotification, object: nil)
        // Stop capture across backgrounding (and resume on return) so ReplayKit never has a
        // session to auto-resume: replayd's resume callback (`shouldResumeSessionType:`) walks
        // `-[RPScreenRecorder applicationWindow]` on an XPC queue, which reads the host's
        // `AppDelegate.window` getter off-main and traps under a `@MainActor`-isolated
        // AppDelegate (Swift 6 dynamic isolation checks). See issue #21.
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        // Restart on didBecomeActive, NOT willEnterForeground: RPScreenRecorder.startCapture
        // needs a foreground-active app. Called between willEnterForeground and active it can
        // fail, leaving recording off despite the intent to resume (#22).
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        // Privacy guard: pause capture while a secure text field is edited. The in-app
        // capture path gets neither the OS's secure-field blanking (external captures only)
        // nor the secure-canvas exclusion — measured on device — so without this, passwords
        // (dots, per-keystroke preview, revealed text) land in the clip. Editing
        // notifications fire app-wide for any UIKit-backed input, including SwiftUI's
        // SecureField (backed by UITextField).
        NotificationCenter.default.addObserver(
            self, selector: #selector(textEditingBegan(_:)),
            name: UITextField.textDidBeginEditingNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(textEditingEnded(_:)),
            name: UITextField.textDidEndEditingNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(textEditingBegan(_:)),
            name: UITextView.textDidBeginEditingNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(textEditingEnded(_:)),
            name: UITextView.textDidEndEditingNotification, object: nil)
        #if DEBUG
        // Diagnostic: snapshot the recording state at the moment of foreground resume
        // after being idle (DEBUG only).
        NotificationCenter.default.addObserver(
            self, selector: #selector(debugCaptureWakeSnapshot),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        #endif
    }

    func startBuffering(seconds: TimeInterval) {
        guard !isCapturing else { return }                 // idempotent
        wantsRecording = true                              // intent to record (for auto-resume decisions)
        desiredBufferSeconds = seconds
        inAppMarksCaptured = nil                            // re-probe device traits this session
        if !Self.didPurgeStaleTempFiles {                  // once per launch: leftovers from the last run
            Self.didPurgeStaleTempFiles = true             // (resume restarts must NOT purge — see flag doc)
            SegmentRingWriter.purgeTempFiles()
        }

        guard isAvailable else {                           // Simulator / unsupported (Sim pinned false above)
            FlashbackLog.lifecycle.info("Screen recording unavailable (Simulator or unsupported environment). Continuing without a clip.")
            onCaptureStarted?(false)                       // couldn't turn recording on
            return                                         // don't throw; export side reports recordingUnavailable
        }

        beginCaptureSession(seconds: seconds)
    }

    /// Create a fresh ring and start a ReplayKit capture session. The session core shared by the
    /// initial `startBuffering` and the rotation restart (`restartCaptureForOrientationChange`).
    /// Assumes the caller has already gated on availability and set the intent flags; it sets up the
    /// ring, seeds the rotation baseline, marks `isCapturing`, and wires the capture handlers.
    ///
    /// Important: this does **not** re-check `isCapturing` — the rotation restart deliberately keeps
    /// `isCapturing == true` across the stop→start gap (so the watchdog loop and the FAB/Controller
    /// state don't flicker), and calls this from the stop completion to begin the new session.
    private func beginCaptureSession(seconds: TimeInterval) {
        recorder.isMicrophoneEnabled = false               // video only (no mic permission)
        let ring = SegmentRingWriter(bufferSeconds: seconds)
        self.ring = ring
        ringHolder.set(ring)
        ringHolder.resetClock()                            // reset frame clock (avoid false triggers)
        // Seed the rotation baseline so the watchdog only restarts on an actual change from here.
        lastNotedOrientation = Self.currentInterfaceOrientation()
        isCapturing = true

        // Bind holder into a local so we don't capture self (holder is Sendable).
        let holder = ringHolder
        recorder.startCapture(handler: { @Sendable sampleBuffer, bufferType, error in
            // Called on a background thread. @Sendable is required to drop main-actor isolation;
            // without it the closure inherits @MainActor isolation and traps with
            // "Block was expected to execute on queue [main-thread]" when ReplayKit invokes it
            // off the main thread. CMSampleBuffer is non-Sendable, so ingest boxes it onto the
            // serial queue. Read the ring via holder (safe across retention swaps and after stop=nil).
            if let error { holder.noteError(error); return }
            holder.ingest(sampleBuffer, type: bufferType)
        }, completionHandler: { @Sendable error in
            // Capture only weak self (don't box a closure); hop to @MainActor and notify via
            // self's properties.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    FlashbackLog.lifecycle.error("startCapture failed: \(error.localizedDescription, privacy: .public)")
                    self.isCapturing = false
                    self.captureConfirmed = false
                    self.ring?.teardown()
                    self.ring = nil
                    self.onCaptureStarted?(false)
                    self.onRecordingStateChanged?(false)   // confirmed: recording off (denied etc.)
                } else {
                    FlashbackLog.lifecycle.info("startCapture started successfully (recording on)")
                    self.captureConfirmed = true           // now confirmed "recording" (post-permission)
                    self.onCaptureStarted?(true)           // one-shot (for justEnabled)
                    self.onRecordingStateChanged?(true)    // confirmed: recording on (UI sync)
                    self.startWatchdog()                   // start watching for frame stalls (interruptions)
                }
            }
        })
    }

    /// Change the retention window. **Does not stop ReplayKit capture** — only swaps the ring.
    /// No-op if not recording (the next `startBuffering` starts with the new value).
    ///
    /// A stop→start approach would crash: stop is async, so the restart can race the
    /// pending stop and an old handler can touch a torn-down ring. Swapping the ring keeps
    /// capture continuous and routes subsequent samples to the new ring (the buffer resets at
    /// the swap point, which is reasonable behavior for a retention-length change).
    func changeBufferSeconds(_ seconds: TimeInterval) {
        guard isCapturing else { return }
        let old = ring
        let newRing = SegmentRingWriter(bufferSeconds: seconds)
        ring = newRing
        ringHolder.set(newRing)                            // route subsequent samples to the new ring (atomic)
        // Re-seed the rotation baseline against the fresh ring so the watchdog measures rotation from
        // the current orientation (the new ring starts empty; the next sample sets its dimensions).
        lastNotedOrientation = Self.currentInterfaceOrientation()
        old?.teardown()                                    // finalize/discard the old ring (don't stop capture)
    }

    func stopBuffering() {
        // Explicit stop: no auto-resume even after an interruption recovers.
        wantsRecording = false
        interruptedBySystem = false
        teardownCapture(notify: true)
    }

    /// Stop capture and discard the ring (with confirmed recording-off notification).
    /// Shared by explicit stop and interruption pause. Does not touch `wantsRecording` /
    /// `interruptedBySystem` — the caller sets those per use.
    private func teardownCapture(notify: Bool) {
        guard isCapturing else { return }                  // idempotent
        watchdog?.cancel(); watchdog = nil                 // stop frame monitoring
        isCapturing = false
        isRestartingForOrientation = false                 // abandon any in-flight rotation restart (its start guard then bails)
        let wasConfirmed = captureConfirmed
        captureConfirmed = false
        ringHolder.set(nil)                                // drop further samples (don't touch the torn-down ring)
        // completion is called on a background thread. @Sendable is required (without it the
        // closure inherits @MainActor isolation and traps with
        // "Block was expected to execute on queue [main-thread]" when run off main).
        recorder.stopCapture { @Sendable _ in }
        ring?.teardown()
        ring = nil
        if notify && wasConfirmed { onRecordingStateChanged?(false) }  // confirmed: recording off
    }

    /// Export the current buffer to a temp .mp4 and return its URL.
    func exportBufferedClip() async throws -> URL {
        guard let ring, isCapturing else { throw FlashbackError.recordingUnavailable }
        return try await ring.export()
    }

    #if DEBUG
    /// DEBUG: seconds since the last video frame (nil = none received). For tuning the
    /// interruption-detection threshold.
    var debugFrameAge: Double? { ringHolder.secondsSinceLastVideo() }
    /// DEBUG: whether the screen is under external capture (`UIScreen.isCaptured`).
    var debugScreenIsCaptured: Bool { Self.screenIsCaptured() }
    /// DEBUG: format of the segments currently in the ring ("WxH@o", or "-" when empty). The "@o" tag
    /// is the orientation from an RPVideoSampleOrientationKey attachment (`u/r/l/d`), or `-` when no
    /// attachment has ever arrived. On a content-only-rotation device (`@-`), rotation is handled by
    /// restarting the capture session, so the **`WxH` flipping clip-to-clip** is the visible
    /// confirmation that rotation handling fired (each clip uses the new orientation's native size).
    var debugRingDimensions: String { ring?.debugDimensionsText ?? "-" }
    /// DEBUG: whether in-app recording itself set isCaptured this session (probe result; nil = undetermined).
    var debugInAppMarksCaptured: Bool? { inAppMarksCaptured }
    /// DEBUG: system-side `RPScreenRecorder.isRecording` (distinct from in-app `captureConfirmed`).
    /// A window to observe on-device whether it drops to false when Control Center screen
    /// recording takes over.
    var debugSystemIsRecording: Bool { recorder.isRecording }
    /// DEBUG: number of errors received by the capture handler.
    var debugCaptureErrorCount: Int { ringHolder.errorSnapshot().count }
    /// DEBUG: snapshot of the recording state at the last didBecomeActive (foreground resume).
    /// Captures the "moment of return" state before the watchdog rewrites it.
    private(set) var debugWakeSnapshot = "—"

    /// Called on didBecomeActive; samples the resume-moment state synchronously (before the
    /// watchdog's async correction).
    @objc private func debugCaptureWakeSnapshot() {
        let age = ringHolder.secondsSinceLastVideo().map { String(format: "%.1f", $0) } ?? "—"
        debugWakeSnapshot = "rec=\(captureConfirmed ? "ON" : "off") sysRec=\(recorder.isRecording ? "ON" : "off") age=\(age) errs=\(ringHolder.errorSnapshot().count)"
    }
    #endif

    // MARK: - Conflict with external capture (OS screen recording / mirroring / calls)

    /// In-app capture and OS screen recording/mirroring are mutually exclusive: when external
    /// capture starts, the in-app frame supply stops (the buffer freezes), and neither the
    /// completion handler fires nor the session recovers. So we **treat a frame stall during
    /// external capture as an interruption and fully stop** (off, discard the frozen buffer),
    /// then **auto-resume when external capture ends**.
    ///
    /// Detection = frame-supply watchdog + `UIScreen.isCaptured` gate (interrupt only when
    /// external capture is present; avoids false triggers when frames are sparse on a static
    /// screen). Recovery = `UIScreen.capturedDidChangeNotification` and `RPScreenRecorder`
    /// availability.

    /// Interruption by external capture: fully stop and discard the frozen buffer. Sets
    /// `isCapturing=false` so auto-resume via `startBuffering` and manual re-enable work on
    /// recovery (keeping the session alive would be rejected by the idempotency guard).
    private func interruptForExternalCapture(reason: String) {
        guard isCapturing else { return }
        FlashbackLog.lifecycle.info("\(reason, privacy: .public). Stopping recording and discarding the frozen buffer (interruption).")
        interruptedBySystem = true                         // mark for auto-resume on recovery
        teardownCapture(notify: true)                      // confirmed off (FAB gray) + stop session + discard ring
        onExternalCaptureInterrupt?(true)                  // interrupt toast
    }

    /// Auto-resume when external capture ends / availability recovers. Runs only when recording
    /// intent remains, no double-start is in flight, and external capture is gone.
    private func attemptResume(reason: String) {
        guard interruptedBySystem, wantsRecording, !isCapturing, !Self.screenIsCaptured() else { return }
        // Never resume while inactive/backgrounded: startCapture needs a foreground-active app,
        // so starting here would fail, burn the flag, and show a resume toast for a dead start
        // (#22). appDidBecomeActive retries this path once the app is active again.
        guard UIApplication.shared.applicationState == .active else { return }
        interruptedBySystem = false
        FlashbackLog.lifecycle.info("\(reason, privacy: .public). Auto-resuming recording.")
        startBuffering(seconds: desiredBufferSeconds)
        onExternalCaptureInterrupt?(false)                 // resume toast
    }

    // MARK: - Background / foreground (avoid ReplayKit's auto-resume path — issue #21)

    /// Pause capture on backgrounding. With no live session at suspension time, replayd has
    /// nothing to offer a resume for, so the off-main `applicationWindow` walk never runs.
    /// Same teardown semantics as the external-capture interruption (discard the ring; the
    /// screen isn't captured while backgrounded anyway), but **silent** — no interrupt toast,
    /// since backgrounding is a normal lifecycle event the user initiated.
    ///
    /// Residual risk: `stopCapture` is async fire-and-forget; if the app suspends before
    /// replayd processes the stop, the resume query can still arrive on return. The foreground
    /// handler below re-starting a fresh session keeps even that case consistent.
    @objc private func appDidEnterBackground() {
        guard isCapturing else { return }
        FlashbackLog.lifecycle.info("App entered background. Stopping capture to avoid ReplayKit auto-resume (the buffer restarts empty on return).")
        pausedForBackground = true                         // resume on didBecomeActive (silent path)
        teardownCapture(notify: true)                      // confirmed off + stop session + discard ring
    }

    /// Quietly restart capture once the app is **active** again (recording intent remaining).
    /// Mirrors `attemptResume` minus the resume toast — no interrupt toast was shown on the
    /// way out, and a lifecycle round-trip shouldn't announce itself (#22). Also the retry
    /// point for an external-capture interruption that recovered while the app wasn't active
    /// (`attemptResume` defers to here via its applicationState guard).
    @objc private func appDidBecomeActive() {
        if pausedForBackground {
            pausedForBackground = false
            if Self.screenIsCaptured() {
                // External capture (OS recording / mirroring) started while backgrounded:
                // hand over to the external-capture machinery so its end resumes as usual
                // (with the interruption toast semantics that situation deserves).
                interruptedBySystem = true
            } else if wantsRecording, !isCapturing {
                FlashbackLog.lifecycle.info("App became active. Restarting capture (fresh buffer).")
                startBuffering(seconds: desiredBufferSeconds)
            }
            return
        }
        // Secure-entry pause whose end-editing arrived while inactive: resume now that
        // startCapture can succeed (no-op while a secure field is still being edited).
        resumeAfterSecureEntryIfNeeded()
        // Not a background pause: pick up an external-capture resume deferred while inactive.
        attemptResume(reason: "External capture cleared while the app was inactive")
    }

    // MARK: - Secure-text-entry privacy guard

    /// Begin-editing for any UITextField/UITextView (fires on main). On the first secure
    /// field gaining focus (count 0 → 1) while recording, pauses capture so the password —
    /// the masked dots, the per-keystroke last-character preview, and anything revealed —
    /// never lands in the clip. Silent apart from the floating button turning gray.
    /// Tracking runs even while the guard is off, so toggling the guard on mid-edit can
    /// reconcile against the current focus (`setPausesForSecureTextEntry`).
    @objc private func textEditingBegan(_ note: Notification) {
        guard secureEntryTracker.noteBeginEditing(note.object) else { return }
        guard pausesForSecureTextEntry, isCapturing else { return }
        FlashbackLog.lifecycle.info("Secure text entry began. Pausing capture (the buffer restarts after editing ends).")
        pausedForSecureEntry = true
        teardownCapture(notify: true)              // confirmed off (FAB gray) + stop session + discard ring
    }

    /// End-editing counterpart: once no secure field is being edited, resumes quietly with a
    /// fresh buffer. Tracking is independent of `pausesForSecureTextEntry` so a field
    /// already counted keeps its end-editing paired even if the flag were toggled mid-edit.
    @objc private func textEditingEnded(_ note: Notification) {
        guard secureEntryTracker.noteEndEditing(note.object) else { return }
        resumeAfterSecureEntryIfNeeded()
    }

    /// Restart capture after a secure-entry pause, when conditions allow. Deferred to
    /// `appDidBecomeActive` when the app isn't active (keyboard dismissal can arrive
    /// mid-backgrounding, where `startCapture` would fail — same rationale as #22).
    private func resumeAfterSecureEntryIfNeeded() {
        guard pausedForSecureEntry, !secureEntryTracker.isEditingSecure else { return }
        guard UIApplication.shared.applicationState == .active else { return }   // didBecomeActive retries
        guard wantsRecording, !isCapturing else { pausedForSecureEntry = false; return }
        pausedForSecureEntry = false
        if Self.screenIsCaptured() {
            // External capture took over during the pause: hand over to that machinery
            // (its end triggers the usual toast-bearing resume).
            interruptedBySystem = true
            return
        }
        FlashbackLog.lifecycle.info("Secure text entry ended. Restarting capture (fresh buffer).")
        startBuffering(seconds: desiredBufferSeconds)
    }

    /// Updates the secure-entry guard at runtime (config default at start, then the settings
    /// toggle) and reconciles the current state on the spot: re-enabling while a secure field
    /// is being edited pauses immediately; disabling while paused resumes immediately (the
    /// tester explicitly chose capturing evidence around password entry over privacy).
    func setPausesForSecureTextEntry(_ enabled: Bool) {
        guard pausesForSecureTextEntry != enabled else { return }
        pausesForSecureTextEntry = enabled
        if enabled {
            if secureEntryTracker.isEditingSecure, isCapturing {
                FlashbackLog.lifecycle.info("Secure-entry guard re-enabled mid-edit. Pausing capture.")
                pausedForSecureEntry = true
                teardownCapture(notify: true)
            }
        } else if pausedForSecureEntry {
            pausedForSecureEntry = false
            guard wantsRecording, !isCapturing, !Self.screenIsCaptured(),
                  UIApplication.shared.applicationState == .active else { return }
            FlashbackLog.lifecycle.info("Secure-entry guard disabled while paused. Restarting capture.")
            startBuffering(seconds: desiredBufferSeconds)
        }
    }

    /// Whether the screen is being captured externally (OS screen recording / AirPlay / mirroring).
    private static func screenIsCaptured() -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.isCaptured ?? false
    }

    // MARK: - Rotation detection (drives the capture-session restart)

    /// The active window scene's current interface orientation, mapped to a
    /// `CGImagePropertyOrientation` used purely as a **rotation-comparison key** (see
    /// `imageOrientation(for:)`). Defaults to `.up` when no scene is resolvable. Picks the same scene
    /// as `screenIsCaptured` (foreground-active first).
    private static func currentInterfaceOrientation() -> CGImagePropertyOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return imageOrientation(for: scene?.interfaceOrientation ?? .portrait)
    }

    /// Map a `UIInterfaceOrientation` to a distinct `CGImagePropertyOrientation` used as a rotation
    /// **comparison key**: the watchdog only needs to know *that* the orientation changed (each of the
    /// four device orientations maps to a different value), to decide whether to restart the capture
    /// session. The specific value carries no transform meaning anymore — clips are oriented by the
    /// capture restart picking up the new native dimensions, not by a metadata transform.
    /// - `.portrait` → `.up`, `.landscapeRight` → `.left`, `.landscapeLeft` → `.right`,
    ///   `.portraitUpsideDown` → `.down`, `.unknown`/future → `.up` (safe default).
    static func imageOrientation(for interface: UIInterfaceOrientation) -> CGImagePropertyOrientation {
        switch interface {
        case .portrait: return .up
        case .landscapeRight: return .left
        case .landscapeLeft: return .right
        case .portraitUpsideDown: return .down
        case .unknown: return .up
        @unknown default: return .up
        }
    }

    /// Short human-readable label (u/r/l/d/-) for the rotation-comparison key, for restart logging only.
    private static func orientationLabel(_ o: CGImagePropertyOrientation?) -> String {
        switch o {
        case .up: return "u"
        case .right: return "r"
        case .left: return "l"
        case .down: return "d"
        default: return "-"
        }
    }

    private func handleAvailabilityChange(available: Bool) {
        if available { attemptResume(reason: "画面録画が利用可能に復帰") }
        else { interruptForExternalCapture(reason: "画面録画が利用不可に（通話/別アプリ等）") }
    }

    /// ReplayKit availability-change callback (`nonisolated` because it can arrive on a
    /// background thread). Reads the value, hops to `@MainActor`, and handles it via `self`
    /// (MainActor-isolated, Sendable).
    nonisolated func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {
        let available = screenRecorder.isAvailable
        Task { @MainActor [weak self] in self?.handleAvailabilityChange(available: available) }
    }

    /// `UIScreen.capturedDidChangeNotification` (external capture start/end). **Used only as a
    /// resume trigger** — start detection is the watchdog's job, so that devices where in-app
    /// capture itself sets `isCaptured` don't mistake their own recording start for an
    /// interruption. May arrive on main, but hops for Swift 6.
    @objc nonisolated private func screenCaptureStateChanged() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if Self.screenIsCaptured() {
                // On devices where in-app recording doesn't set isCaptured, a transition to true
                // definitively means external capture started: go gray immediately, nearly in sync
                // with its start. For devices that do set it / undetermined, defer to the watchdog
                // (avoid false triggers).
                if self.inAppMarksCaptured == false {
                    self.interruptForExternalCapture(reason: "外部キャプチャ（画面収録/ミラーリング）開始を検知")
                }
            } else {
                self.attemptResume(reason: "外部キャプチャが終了")
            }
        }
    }

    // MARK: - Frame-supply watchdog (interruption detection)

    /// While capturing, treat a video frame stall of `stallThreshold` seconds **while external
    /// capture is present** as an interruption and stop. Covers paths where the availability
    /// delegate doesn't fire, such as Control Center screen recording.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)   // 0.1s steps (finer than the threshold, for quick detection)
                guard let self, self.isCapturing else { return }
                // During a rotation restart the old session is being torn down and the new one not yet
                // up, so frames are legitimately absent: skip stall detection (which would otherwise
                // mistake the gap for an external-capture interruption). The orientation poll is also
                // skipped — the restart re-seeds the baseline when the new session begins.
                guard !self.isRestartingForOrientation else { continue }
                self.checkStall()
                self.pollInterfaceOrientation()
            }
        }
    }

    /// Detect a device rotation (watchdog tick, recording only) and restart the capture session so
    /// the new session begins at the new orientation's native dimensions. On devices that rotate only
    /// the frame content — neither the buffer size nor an attachment changes (iPhone 15 Pro / iOS
    /// 26.5) — this poll is the sole rotation signal. A MainActor property read is cheap, so polling
    /// every 0.1s tick is fine; it also catches 180° flips that overlay-size callbacks miss. Devices
    /// that *do* attach RPVideoSampleOrientationKey are handled by the attachment→reset path instead,
    /// so `restartCaptureForOrientationChange` no-ops once an attachment has been observed.
    private func pollInterfaceOrientation() {
        let current = Self.currentInterfaceOrientation()
        guard current != lastNotedOrientation else { return }
        let previous = lastNotedOrientation
        lastNotedOrientation = current
        restartCaptureForOrientationChange(from: previous, to: current)
    }

    /// Restart the ReplayKit capture session in response to a rotation, so each clip is captured at
    /// the new orientation's native resolution, upright, with correct aspect.
    ///
    /// Why a restart (not a metadata transform): ReplayKit freezes the buffer dimensions at the
    /// interface orientation present when capture *started* and keeps them for the session's life. On
    /// rotation the frame *content* doesn't rotate — it stays upright but gets anamorphically squeezed
    /// into the frozen (wrong-aspect) buffer. No attachment arrives and the size doesn't change, so a
    /// `preferredTransform` can't fix the already-distorted pixels. Only a fresh session picks up the
    /// new native dimensions.
    ///
    /// Sequencing safety: `stopCapture` is async; a stop→**immediate** start crashes on device. So we
    /// start the new session only inside the stop completion handler (the proven ordering from the
    /// external-capture interrupt→resume flow). Throughout, the logical recording state stays ON
    /// (`isCapturing` true) so the watchdog loop and FAB/Controller state don't flicker; the gap is
    /// silent (no interrupt callback/toast — log only). `captureConfirmed` is dropped for the gap so
    /// stall detection can't false-fire, and is re-raised by the new session's completion handler.
    private func restartCaptureForOrientationChange(from: CGImagePropertyOrientation?,
                                                    to: CGImagePropertyOrientation) {
        guard isCapturing, !isRestartingForOrientation else { return }
        // Attachment-bearing devices orient clips correctly via the attachment→reset+transform path;
        // a restart (and its ~1s gap) is unnecessary and undesirable there. Skip if any attachment
        // has been observed on the current ring.
        guard ring?.hasSeenOrientationAttachment != true else { return }

        isRestartingForOrientation = true
        captureConfirmed = false                           // suppress stall detection across the gap (re-raised on restart)
        let transition = "向き\(Self.orientationLabel(from))→\(Self.orientationLabel(to))"
        FlashbackLog.lifecycle.info("回転を検知。capture セッションを再起動（\(transition, privacy: .public)）。直前バッファは破棄。")

        ring?.teardown()                                   // discard the old-orientation buffer
        ring = nil
        ringHolder.set(nil)                                // drop in-flight samples until the new session starts

        let seconds = desiredBufferSeconds
        // stopCapture completion lands on a background thread; @Sendable required (no closure boxing).
        // Hop back to MainActor and begin the new session there. Proceed even on stop error (the
        // session may already be dead) — the goal is to come back up at the new orientation.
        recorder.stopCapture { @Sendable error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    FlashbackLog.lifecycle.info("回転再起動: stopCapture がエラーを返したが新セッションへ進む: \(error.localizedDescription, privacy: .public)")
                }
                self.isRestartingForOrientation = false
                // Bail if recording was turned off / interrupted during the gap (don't revive a session
                // the user/system stopped). beginCaptureSession re-seeds the orientation baseline.
                guard self.isCapturing, self.wantsRecording else { return }
                self.beginCaptureSession(seconds: seconds)
            }
        }
    }

    private func checkStall() {
        guard captureConfirmed else { return }
        let idle = ringHolder.secondsSinceLastVideo()
        // Device-trait probe: at the first frame after recording starts (normally with no
        // external capture), record once whether in-app recording itself sets UIScreen.isCaptured.
        if inAppMarksCaptured == nil, idle != nil {
            inAppMarksCaptured = Self.screenIsCaptured()
        }
        // Backup detection: interrupt if frames stall for stallThreshold seconds during external
        // capture (insurance against a missed capturedDidChange / no true notification on devices
        // that set isCaptured).
        //
        // The `inAppMarksCaptured == false` gate is required: `screenIsCaptured()` means "external
        // capture present" only on devices where in-app recording doesn't set isCaptured. On
        // devices that do (==true), isCaptured is always true while recording, so the gate is
        // useless and a static screen (ReplayKit only supplies frames on screen changes = normal
        // idle) gets mistaken for an interruption, repeating stop→auto-resume (FAB flicker).
        // Matches the immediate path's gate (screenCaptureStateChanged) for symmetry.
        // Devices with inAppMarksCaptured==true (iPhone 15 Pro etc.) aren't covered here and are
        // caught instead by the "system recording stopped" path below.
        if let idle, idle > Self.stallThreshold, inAppMarksCaptured == false, Self.screenIsCaptured() {
            interruptForExternalCapture(reason: "外部キャプチャ中にフレーム供給停止を検知")
        }
        // Detection for devices where in-app recording sets isCaptured (iPhone 15 Pro etc.). Since
        // isCaptured can't distinguish a CC overlay, treat "frame stall AND system-side
        // `RPScreenRecorder.isRecording` == false" as external capture takeover. A static screen
        // keeps isRecording true so this won't false-trigger (CC takeover drops it to false).
        if inAppMarksCaptured == true, captureConfirmed, wantsRecording,
           let idle, idle > Self.stallThreshold, !recorder.isRecording {
            interruptForExternalCapture(reason: "システム録画停止＋フレーム供給停止を検知（外部キャプチャ奪取）")
        }
    }
}

/// Holder for the "current ring" touched by the capture handler (background thread).
/// A lock makes the ring swap atomic, so retention changes (ring swap) without stopping
/// recording and post-stop sample drops (ring=nil) are both safe.
private final class RingHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var ring: SegmentRingWriter?
    /// Monotonic time (ns) of the last **video** sample. 0 = none received yet.
    /// Used by the watchdog to detect interruptions where frame supply stops (OS recording etc.).
    private var lastVideoNanos: UInt64 = 0
    /// Count and last message of errors received by the capture handler (DEBUG instrumentation).
    private var errorCount = 0
    private var lastErrorText: String?

    func set(_ newRing: SegmentRingWriter?) {
        lock.lock(); defer { lock.unlock() }
        ring = newRing
    }

    /// Reset the frame clock and error instrumentation on a new capture start (so stale values
    /// don't cause false triggers).
    func resetClock() {
        lock.lock(); lastVideoNanos = 0; errorCount = 0; lastErrorText = nil; lock.unlock()
    }

    /// Record an error received by the capture handler (background thread).
    func noteError(_ error: Error) {
        lock.lock(); errorCount += 1; lastErrorText = error.localizedDescription; lock.unlock()
    }

    /// Snapshot of the recorded error count and last message.
    func errorSnapshot() -> (count: Int, last: String?) {
        lock.lock(); defer { lock.unlock() }
        return (errorCount, lastErrorText)
    }

    func ingest(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType) {
        lock.lock()
        let current = ring
        if type == .video { lastVideoNanos = DispatchTime.now().uptimeNanoseconds }
        lock.unlock()
        current?.ingest(sampleBuffer, type: type)
    }

    /// Seconds since the last video sample. nil if none has ever been received.
    func secondsSinceLastVideo() -> Double? {
        lock.lock(); let last = lastVideoNanos; lock.unlock()
        guard last != 0 else { return nil }
        return Double(DispatchTime.now().uptimeNanoseconds &- last) / 1_000_000_000
    }
}

/// A local escape hatch to carry a non-Sendable value across the concurrency boundary
/// (`queue.async`). Safe because the value is taken by ownership from ReplayKit and handed
/// only to a single serial queue, never touched from other threads.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
}

/// Maintains a ring of mp4 segments covering the last N seconds on a dedicated serial queue,
/// merging them into a single mp4 on export. All mutable state is touched only on `queue`,
/// hence `@unchecked Sendable` (effectively a serial actor).
///
/// `internal` so tests can feed synthetic frames and verify the export pipeline on the
/// Simulator via the AVFoundation path alone, without ReplayKit.
final class SegmentRingWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FlashbackKit.SegmentRingWriter")
    private let segmentDuration: TimeInterval
    private let maxSegments: Int
    /// Target retention length (seconds). The ring over-retains (N + a partial segment), so
    /// export trims to the last this-many seconds to remove duration overshoot. If recording is
    /// shorter than N, the whole stock is returned.
    private let bufferSeconds: TimeInterval

    // Everything below is accessed only on `queue`.
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var currentSegmentStart: CMTime = .invalid
    private var segmentURLs: [URL] = []
    /// Dimensions of the segments currently in the ring (set from the first sample of the
    /// segment in `startNewSegment`, nil when the ring is empty). Used to detect a screen-size
    /// change (rotation) so the ring can be reset before mixing incompatible segments. Touched
    /// only on `queue`; a DEBUG-only mirror (`mirrorDimensionsForDebug`) exposes it to the HUD.
    private var ringDimensions: CMVideoDimensions? {
        didSet { mirrorFormatForDebug() }   // expose to the MainActor HUD (DEBUG only)
    }
    /// The ring's confirmed sample orientation (RPVideoSampleOrientationKey, as a
    /// `CGImagePropertyOrientation`). Set from the first sample of a segment in `startNewSegment`,
    /// nil when the ring is empty. On a physical device, ReplayKit keeps the buffer dimensions
    /// fixed (native portrait surface) and signals rotation by changing this attachment instead,
    /// so an orientation change is treated the same as a size change: reset the ring so we never
    /// merge segments of differing orientation, and drive `composeAndExport`'s upright transform.
    /// Touched only on `queue`; mirrored to the HUD via `mirrorFormatForDebug` (DEBUG only).
    private var ringOrientation: CGImagePropertyOrientation? {
        didSet { mirrorFormatForDebug() }
    }
    /// Whether *any* sample seen by this ring carried an RPVideoSampleOrientationKey attachment.
    /// Distinguishes "no attachment ever (treated as .up)" from "attachment present and == .up" on
    /// the HUD — the ground truth we need from a device to know whether rotation is even signalled
    /// via this attachment. Sticky once true; touched only on `queue`, mirrored for the HUD.
    private var sawOrientationAttachment = false {
        didSet { mirrorFormatForDebug() }
    }
    /// Torn-down flag. Guards against late samples arriving after finalization recreating a segment.
    private var tornDown = false

    /// Whether *any* sample seen by this ring has carried an RPVideoSampleOrientationKey attachment,
    /// mirrored under an NSLock so `ScreenRecorder` (MainActor) can read it without hopping onto
    /// `queue` (same pattern as RingHolder's lastVideoNanos). Drives the orientation-restart
    /// decision: on attachment-bearing devices the attachment→reset+transform path already orients
    /// clips correctly, so a capture-session restart is unnecessary (and its gap undesirable).
    private let attachmentSeenLock = NSLock()
    private var attachmentSeenMirror = false

    /// Thread-safe snapshot of whether an orientation attachment has ever been observed on this ring.
    /// Read from `ScreenRecorder` on the MainActor.
    var hasSeenOrientationAttachment: Bool {
        attachmentSeenLock.lock(); defer { attachmentSeenLock.unlock() }
        return attachmentSeenMirror
    }

    /// Mirror the ring's dimensions + orientation into an NSLock-guarded box (DEBUG only) so the
    /// MainActor diagnostics line can read it without hopping onto `queue` (same pattern as
    /// RingHolder's lastVideoNanos). Also mirrors `sawOrientationAttachment` into a Release-safe box
    /// (separate lock) for the restart decision. A no-op for the DEBUG-only HUD fields in Release.
    private func mirrorFormatForDebug() {
        attachmentSeenLock.lock()
        attachmentSeenMirror = sawOrientationAttachment
        attachmentSeenLock.unlock()
        #if DEBUG
        debugDimsLock.lock()
        debugRingDimensions = ringDimensions.map { ($0.width, $0.height) }
        debugRingOrientation = ringOrientation
        debugSawOrientationAttachment = sawOrientationAttachment
        debugDimsLock.unlock()
        #endif
    }

    #if DEBUG
    private let debugDimsLock = NSLock()
    private var debugRingDimensions: (width: Int32, height: Int32)?
    private var debugRingOrientation: CGImagePropertyOrientation?
    private var debugSawOrientationAttachment = false

    /// DEBUG: the ring's current segment format ("WxH@o"), or "-" when the ring is empty.
    /// The `@o` suffix is the orientation tag: `u`=up, `r`=right, `l`=left, `d`=down, and `@-`
    /// when no RPVideoSampleOrientationKey attachment has ever arrived (so "attachment absent" is
    /// visibly distinct from "attachment present and == .up", which both render upright). On a
    /// device, `@-` while rotating means rotation is NOT signalled via this attachment — and since
    /// the dimensions still change clip-to-clip (the capture session is restarted on rotation), the
    /// `WxH` flipping is the visible confirmation that rotation handling fired.
    var debugDimensionsText: String {
        debugDimsLock.lock()
        let d = debugRingDimensions
        let o = debugRingOrientation
        let saw = debugSawOrientationAttachment
        debugDimsLock.unlock()
        guard let d else { return "-" }
        let tag = saw ? Self.orientationTag(o ?? .up) : "-"
        return "\(d.width)x\(d.height)@\(tag)"
    }

    /// DEBUG: one-letter tag for an orientation (u/r/l/d). Falls back to "u" for unexpected values.
    private static func orientationTag(_ o: CGImagePropertyOrientation) -> String {
        switch o {
        case .up, .upMirrored: return "u"
        case .right, .rightMirrored: return "r"
        case .left, .leftMirrored: return "l"
        case .down, .downMirrored: return "d"
        @unknown default: return "u"
        }
    }
    #endif

    init(bufferSeconds: TimeInterval) {
        self.bufferSeconds = bufferSeconds
        let seg = max(2, bufferSeconds / 6)                // split the window into ~6
        self.segmentDuration = seg
        self.maxSegments = Int((bufferSeconds / seg).rounded(.up)) + 1   // always keep at least N seconds
    }

    // MARK: - Ingest

    func ingest(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType) {
        guard type == .video else { return }               // video only
        let box = UncheckedSendableBox(value: sampleBuffer)
        queue.async { [self] in append(box.value) }
    }

    private func append(_ sb: CMSampleBuffer) {
        guard !tornDown else { return }                    // drop late samples after finalization
        guard CMSampleBufferDataIsReady(sb) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        let orientation = self.orientation(of: sb)         // effective orientation (.up when no attachment); also flags "saw attachment"

        // Format changed (rotation / iPad multitasking). Two independent signals, both routed to the
        // same reset so we never passthrough-merge incompatible segments:
        //  1. Dimension change — happens when the surface size flips (e.g. iPad multitasking).
        //  2. Orientation-attachment change — on a phone ReplayKit keeps the buffer dimensions fixed
        //     (native portrait surface) and rotates the *content*, flagging it via
        //     RPVideoSampleOrientationKey only. Without (2), a rotated clip plays back sideways.
        // Belt-and-braces: keep both checks even though a single one usually fires per rotation.
        if let fmt = CMSampleBufferGetFormatDescription(sb) {
            let dim = CMVideoFormatDescriptionGetDimensions(fmt)
            let sizeChanged = ringDimensions.map { $0.width != dim.width || $0.height != dim.height } ?? false
            let orientationChanged = ringOrientation.map { $0 != orientation } ?? false
            if sizeChanged || orientationChanged {
                resetForFormatChange(fromDim: ringDimensions, toDim: dim,
                                     fromOrientation: ringOrientation, toOrientation: orientation)
            }
        }

        if writer == nil {
            startNewSegment(firstSample: sb, at: pts, orientation: orientation)
        } else if CMTimeGetSeconds(CMTimeSubtract(pts, currentSegmentStart)) >= segmentDuration {
            finalizeCurrent()
            startNewSegment(firstSample: sb, at: pts, orientation: orientation)
        }

        guard let writer, writer.status == .writing,
              let input = videoInput, input.isReadyForMoreMediaData else { return }
        input.append(sb)                                   // drop the frame when not ready (acceptable for PoC)
    }

    // MARK: - Segments

    private func startNewSegment(firstSample sb: CMSampleBuffer, at pts: CMTime,
                                 orientation: CGImagePropertyOrientation) {
        guard let fmt = CMSampleBufferGetFormatDescription(sb) else { return }
        let dim = CMVideoFormatDescriptionGetDimensions(fmt)
        guard dim.width > 0, dim.height > 0 else { return }

        let url = Self.tempURL(prefix: "flashback-seg-")
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dim.width),
            AVVideoHeightKey: Int(dim.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard w.canAdd(input) else { return }
        w.add(input)
        guard w.startWriting() else { return }
        w.startSession(atSourceTime: pts)                  // first sample's PTS (.zero not allowed)

        writer = w
        videoInput = input
        currentSegmentStart = pts
        ringDimensions = dim                               // record the ring's dimensions (rotation detection)
        ringOrientation = orientation                      // record the ring's orientation (rotation detection)
    }

    /// Read the effective orientation of a sample buffer from its RPVideoSampleOrientationKey
    /// attachment (an `NSNumber` carrying a `CGImagePropertyOrientation` rawValue). On a physical
    /// device this is how ReplayKit signals rotation (when it signals at all): the pixel surface
    /// stays the native-portrait size, and the value flips to .left/.right/.down as the device
    /// rotates. When the attachment is absent (older OS / Simulator synthetic frames / devices that
    /// don't attach the key, e.g. iPhone 15 Pro / iOS 26.5) the content is treated as `.up`; on
    /// those devices rotation is handled by restarting the capture session instead (see
    /// `ScreenRecorder.restartCaptureForOrientationChange`).
    private func orientation(of sb: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard let raw = CMGetAttachment(sb, key: RPVideoSampleOrientationKey as CFString,
                                        attachmentModeOut: nil) as? NSNumber,
              let o = CGImagePropertyOrientation(rawValue: raw.uint32Value) else {
            return .up                                     // no attachment → treat as upright
        }
        sawOrientationAttachment = true                    // an attachment exists (HUD ground truth)
        return o
    }

    /// Finalize the current segment; on completion, append its URL to the ring and drop old ones.
    private func finalizeCurrent(completion: (() -> Void)? = nil) {
        guard let writer, let input = videoInput else { completion?(); return }
        let url = writer.outputURL
        input.markAsFinished()
        self.writer = nil
        self.videoInput = nil
        self.currentSegmentStart = .invalid

        // The finishWriting / queue.async closures are treated as @Sendable. writer
        // (AVAssetWriter) and completion are non-Sendable, but this finalization flow runs on a
        // single logical thread (finishWriting completion → our serial queue), touches writer only
        // here, and calls completion exactly once, so it's safe. Boxing the values changes the ARC
        // path and crashes via block over-release, so we instead mark the captured locals
        // nonisolated(unsafe) to assert "safe across the concurrency boundary".
        nonisolated(unsafe) let finishedWriter = writer
        nonisolated(unsafe) let finishCompletion = completion
        finishedWriter.finishWriting { [weak self] in
            guard let self else { finishCompletion?(); return }
            self.queue.async {
                if finishedWriter.status == .completed {
                    self.segmentURLs.append(url)
                    self.trimRing()
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
                finishCompletion?()
            }
        }
    }

    private func trimRing() {
        while segmentURLs.count > maxSegments {
            let old = segmentURLs.removeFirst()
            try? FileManager.default.removeItem(at: old)
        }
    }

    /// Delete every finalized segment file, clear the list and forget the ring dimensions
    /// (shared by reset and teardown). Must be called on `queue`.
    private func deleteAllSegments() {
        for url in segmentURLs {
            try? FileManager.default.removeItem(at: url)
        }
        segmentURLs.removeAll()
        ringDimensions = nil
        ringOrientation = nil
    }

    /// Drop the entire ring after a format change (dimension and/or orientation) so the next export
    /// only merges segments that share both. Runs synchronously on `queue` (no torn-down flag =
    /// recording continues; the next sample opens a new segment at the new format).
    private func resetForFormatChange(fromDim: CMVideoDimensions?, toDim: CMVideoDimensions,
                                      fromOrientation: CGImagePropertyOrientation?,
                                      toOrientation: CGImagePropertyOrientation) {
        // The in-progress segment holds only old-format frames: cancel it and drop its partial
        // file (don't finalize — it's incompatible with the new dimensions/orientation).
        if let writer, let input = videoInput {
            input.markAsFinished()
            let url = writer.outputURL
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
        }
        deleteAllSegments()                                // also clears ringDimensions / ringOrientation
        writer = nil
        videoInput = nil
        currentSegmentStart = .invalid
        let fromText = fromDim.map { "\($0.width)x\($0.height)" } ?? "?"
        let fromO = Self.orientationName(fromOrientation)
        let toO = Self.orientationName(toOrientation)
        FlashbackLog.lifecycle.info("画面フォーマット変化を検知（\(fromText)@\(fromO)→\(toDim.width)x\(toDim.height)@\(toO)）。リングバッファをリセットし新フォーマットで録り直す。")
    }

    /// Human-readable orientation name for logging (up/right/left/down).
    private static func orientationName(_ o: CGImagePropertyOrientation?) -> String {
        guard let o else { return "?" }
        switch o {
        case .up, .upMirrored: return "up"
        case .right, .rightMirrored: return "right"
        case .left, .leftMirrored: return "left"
        case .down, .downMirrored: return "down"
        @unknown default: return "up"
        }
    }

    // MARK: - Export / teardown

    func export() async throws -> URL {
        let snapshot = try await finalizeAndSnapshot()
        return try await Self.composeAndExport(segments: snapshot.segments,
                                               orientation: snapshot.orientation,
                                               targetSeconds: bufferSeconds)
    }

    private func finalizeAndSnapshot() async throws -> (segments: [URL], orientation: CGImagePropertyOrientation) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                finalizeCurrent {
                    let segs = self.segmentURLs
                    // Capture the orientation under the same queue hop as the segment list so the
                    // upright transform matches exactly the frames being exported (.up if unknown).
                    let orientation = self.ringOrientation ?? .up
                    if segs.isEmpty {
                        continuation.resume(throwing: FlashbackError.recordingUnavailable)
                    } else {
                        continuation.resume(returning: (segs, orientation))
                    }
                }
            }
        }
    }

    func teardown() {
        queue.async { [self] in
            tornDown = true
            finalizeCurrent {
                self.deleteAllSegments()
            }
        }
    }

    /// Concatenate the segments into a single mp4 (passthrough, lossless) and trim to the last
    /// `targetSeconds`. The ring over-retains (N + a partial segment), so cutting only the last N
    /// seconds via `session.timeRange` removes duration overshoot and stabilizes the length
    /// (passthrough may snap to keyframe boundaries with a few frames of error — same approach as
    /// ClipTrimmer). If the concatenated length is under N, return the whole thing (can't fill in
    /// missing stock).
    private static func composeAndExport(segments: [URL],
                                         orientation: CGImagePropertyOrientation,
                                         targetSeconds: TimeInterval) async throws -> URL {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw FlashbackError.recordingUnavailable
        }

        var cursor = CMTime.zero
        var naturalSize: CGSize?
        for url in segments {
            let asset = AVURLAsset(url: url)
            guard let assetTrack = try? await asset.loadTracks(withMediaType: .video).first,
                  let duration = try? await asset.load(.duration), duration > .zero else {
                continue
            }
            if naturalSize == nil { naturalSize = try? await assetTrack.load(.naturalSize) }
            let range = CMTimeRange(start: .zero, duration: duration)
            try? track.insertTimeRange(range, of: assetTrack, at: cursor)
            cursor = CMTimeAdd(cursor, duration)
        }
        guard cursor > .zero else { throw FlashbackError.recordingUnavailable }

        // Set the upright transform as metadata (no re-encode). On a phone, ReplayKit's buffer is the
        // native-portrait surface and rotation lives only in the orientation attachment, so the raw
        // frames are sideways/upside-down for non-portrait device orientations. The preferredTransform
        // tells every player/exporter how to display them upright. For .up it's identity, so existing
        // (portrait) recordings are byte-for-byte unchanged.
        if let naturalSize {
            track.preferredTransform = uprightTransform(for: orientation, naturalSize: naturalSize)
        }

        let outURL = tempURL(prefix: "flashback-")
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw FlashbackError.recordingUnavailable
        }
        session.outputURL = outURL
        session.outputFileType = .mp4

        // Export only the last targetSeconds (drop the over-retained leading excess to stabilize length).
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        if cursor > target {
            session.timeRange = CMTimeRange(start: CMTimeSubtract(cursor, target), duration: target)
        }

        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            throw session.error ?? FlashbackError.recordingUnavailable
        }
        return outURL
    }

    /// Affine transform that displays a frame of `naturalSize` upright, given the orientation of its
    /// stored pixels (`CGImagePropertyOrientation`). `CGImagePropertyOrientation` names how the
    /// pixels are stored relative to upright, so the transform is the rotation that *undoes* it:
    ///
    /// - `.up`     → identity. The frame is already upright; existing portrait clips are unchanged.
    /// - `.down`   → 180°. The frame is upside-down (rotate π, then translate by (w, h) to bring it
    ///                back into the positive quadrant). Display size stays (w, h).
    /// - `.right`  → +90° (clockwise). `.right` means the stored row 0 is on the right edge, i.e.
    ///                the frame must rotate +π/2 to stand up. After rotation the rect lands in
    ///                negative x, so translate by (h, 0). Display size becomes (h, w) — W/H swap.
    /// - `.left`   → −90° (counter-clockwise). Mirror of `.right`: rotate −π/2 and translate by
    ///                (0, w). Display size becomes (h, w) — W/H swap.
    ///
    /// (Mirrored variants are folded into their base rotation; the screen recorder never produces
    /// mirrored frames, so the extra flip is intentionally omitted.) Tests pin the resulting matrix
    /// and the post-transform display size for each case.
    static func uprightTransform(for orientation: CGImagePropertyOrientation,
                                 naturalSize: CGSize) -> CGAffineTransform {
        let w = naturalSize.width, h = naturalSize.height
        switch orientation {
        case .up, .upMirrored:
            return .identity
        case .down, .downMirrored:
            return CGAffineTransform(rotationAngle: .pi).translatedBy(x: -w, y: -h)
        case .right, .rightMirrored:
            return CGAffineTransform(rotationAngle: .pi / 2).translatedBy(x: 0, y: -h)
        case .left, .leftMirrored:
            return CGAffineTransform(rotationAngle: -.pi / 2).translatedBy(x: -w, y: 0)
        @unknown default:
            return .identity
        }
    }

    // MARK: - Temp files

    private static func tempURL(prefix: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)\(UUID().uuidString).mp4")
    }

    /// Clean up leftovers from the previous launch (flashback-* / flashback-seg-*).
    static func purgeTempFiles() {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in items where url.lastPathComponent.hasPrefix("flashback-") {
            try? fm.removeItem(at: url)
        }
    }
}
#else
final class ScreenRecorder {
    var isAvailable: Bool { false }
    var isRecording: Bool { false }
    private(set) var pausesForSecureTextEntry = true
    func setPausesForSecureTextEntry(_ enabled: Bool) { pausesForSecureTextEntry = enabled }
    var onCaptureStarted: ((Bool) -> Void)?
    var onRecordingStateChanged: ((Bool) -> Void)?
    func startBuffering(seconds: TimeInterval) {}
    func changeBufferSeconds(_ seconds: TimeInterval) {}
    func stopBuffering() {}
    func exportBufferedClip() async throws -> URL { throw FlashbackError.notImplemented }
    #if DEBUG
    var debugFrameAge: Double? { nil }
    var debugScreenIsCaptured: Bool { false }
    var debugInAppMarksCaptured: Bool? { nil }
    #endif
}
#endif
