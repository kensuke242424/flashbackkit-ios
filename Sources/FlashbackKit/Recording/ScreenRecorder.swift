#if canImport(ReplayKit)
import ReplayKit
import AVFoundation
import UIKit

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
    /// Last requested retention seconds, kept so auto-resume restarts with the same value.
    private var desiredBufferSeconds: TimeInterval = 0

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
        SegmentRingWriter.purgeTempFiles()                 // clean up leftovers from last run

        guard isAvailable else {                           // Simulator / unsupported (Sim pinned false above)
            FlashbackLog.lifecycle.info("画面録画は利用不可（Simulator か未対応環境）。clip なしで継続。")
            onCaptureStarted?(false)                       // couldn't turn recording on
            return                                         // don't throw; export side reports recordingUnavailable
        }

        recorder.isMicrophoneEnabled = false               // video only (no mic permission)
        let ring = SegmentRingWriter(bufferSeconds: seconds)
        self.ring = ring
        ringHolder.set(ring)
        ringHolder.resetClock()                            // reset frame clock (avoid false triggers)
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
                    FlashbackLog.lifecycle.error("startCapture 失敗: \(error.localizedDescription, privacy: .public)")
                    self.isCapturing = false
                    self.captureConfirmed = false
                    self.ring?.teardown()
                    self.ring = nil
                    self.onCaptureStarted?(false)
                    self.onRecordingStateChanged?(false)   // confirmed: recording off (denied etc.)
                } else {
                    FlashbackLog.lifecycle.info("startCapture 開始成功（録画オン）")
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
        FlashbackLog.lifecycle.info("\(reason, privacy: .public)。録画を停止し凍ったバッファを破棄（割り込み）。")
        interruptedBySystem = true                         // mark for auto-resume on recovery
        teardownCapture(notify: true)                      // confirmed off (FAB gray) + stop session + discard ring
        onExternalCaptureInterrupt?(true)                  // interrupt toast
    }

    /// Auto-resume when external capture ends / availability recovers. Runs only when recording
    /// intent remains, no double-start is in flight, and external capture is gone.
    private func attemptResume(reason: String) {
        guard interruptedBySystem, wantsRecording, !isCapturing, !Self.screenIsCaptured() else { return }
        interruptedBySystem = false
        FlashbackLog.lifecycle.info("\(reason, privacy: .public)。録画を自動再開。")
        startBuffering(seconds: desiredBufferSeconds)
        onExternalCaptureInterrupt?(false)                 // resume toast
    }

    /// Whether the screen is being captured externally (OS screen recording / AirPlay / mirroring).
    private static func screenIsCaptured() -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.isCaptured ?? false
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
                self.checkStall()
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

/// Holder for the "current ring" touched by the capture handler (background thread, `@Sendable`).
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
    /// Torn-down flag. Guards against late samples arriving after finalization recreating a segment.
    private var tornDown = false

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

        if writer == nil {
            startNewSegment(firstSample: sb, at: pts)
        } else if CMTimeGetSeconds(CMTimeSubtract(pts, currentSegmentStart)) >= segmentDuration {
            finalizeCurrent()
            startNewSegment(firstSample: sb, at: pts)
        }

        guard let writer, writer.status == .writing,
              let input = videoInput, input.isReadyForMoreMediaData else { return }
        input.append(sb)                                   // drop the frame when not ready (acceptable for PoC)
    }

    // MARK: - Segments

    private func startNewSegment(firstSample sb: CMSampleBuffer, at pts: CMTime) {
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

    // MARK: - Export / teardown

    func export() async throws -> URL {
        let segments = try await finalizeAndSnapshot()
        return try await Self.composeAndExport(segments: segments, targetSeconds: bufferSeconds)
    }

    private func finalizeAndSnapshot() async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                finalizeCurrent {
                    let segs = self.segmentURLs
                    if segs.isEmpty {
                        continuation.resume(throwing: FlashbackError.recordingUnavailable)
                    } else {
                        continuation.resume(returning: segs)
                    }
                }
            }
        }
    }

    func teardown() {
        queue.async { [self] in
            tornDown = true
            finalizeCurrent {
                for url in self.segmentURLs {
                    try? FileManager.default.removeItem(at: url)
                }
                self.segmentURLs.removeAll()
            }
        }
    }

    /// Concatenate the segments into a single mp4 (passthrough, lossless) and trim to the last
    /// `targetSeconds`. The ring over-retains (N + a partial segment), so cutting only the last N
    /// seconds via `session.timeRange` removes duration overshoot and stabilizes the length
    /// (passthrough may snap to keyframe boundaries with a few frames of error — same approach as
    /// ClipTrimmer). If the concatenated length is under N, return the whole thing (can't fill in
    /// missing stock).
    private static func composeAndExport(segments: [URL], targetSeconds: TimeInterval) async throws -> URL {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw FlashbackError.recordingUnavailable
        }

        var cursor = CMTime.zero
        for url in segments {
            let asset = AVURLAsset(url: url)
            guard let assetTrack = try? await asset.loadTracks(withMediaType: .video).first,
                  let duration = try? await asset.load(.duration), duration > .zero else {
                continue
            }
            let range = CMTimeRange(start: .zero, duration: duration)
            try? track.insertTimeRange(range, of: assetTrack, at: cursor)
            cursor = CMTimeAdd(cursor, duration)
        }
        guard cursor > .zero else { throw FlashbackError.recordingUnavailable }

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
