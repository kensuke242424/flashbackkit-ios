#if canImport(UIKit) && canImport(CoreMotion)
import CoreMotion

/// Detects a shake via the accelerometer (`CMMotionManager`) and calls `onTrigger`.
///
/// Design decision: motion events (`UIWindow.motionEnded`) are only delivered to
/// the **key window's responder chain**. FlashbackKit's overlay window is
/// deliberately non-key (zero host interference), so motionEnded never reaches it.
/// Making the overlay key would steal the host's keyboard and shake-to-undo, and
/// would stop firing during modal presentation or text editing — exactly when a
/// user wants to report a bug. CoreMotion never touches the responder chain and
/// fires reliably regardless of the host's UI state, so we use it instead.
///
/// Threshold logic lives in `ShakeEvaluator` (pure logic) so it can be unit-tested.
@MainActor
final class ShakeTrigger: TriggerDetecting {
    var onTrigger: (() -> Void)?

    private let motionManager = CMMotionManager()
    private let queue: OperationQueue
    private let evaluator = ShakeEvaluator()

    init() {
        let queue = OperationQueue()
        queue.name = "FlashbackKit.ShakeTrigger"
        queue.maxConcurrentOperationCount = 1   // Serial: confine the evaluator's state to this queue
        self.queue = queue
    }

    /// Starts accelerometer updates. No-op when unavailable (e.g. Simulator).
    func start() {
        guard motionManager.isAccelerometerAvailable else { return }
        guard !motionManager.isAccelerometerActive else { return }

        evaluator.reset()
        motionManager.accelerometerUpdateInterval = 1.0 / 20.0   // 20Hz

        // The handler runs on `queue` (non-MainActor, serial). The evaluator is
        // touched only from within this queue; we hop to MainActor only on a hit
        // to call `onTrigger`.
        //
        // Pitfall: `@Sendable` **must** be explicit. `CMAccelerometerHandler` is not
        // a @Sendable type, so inside a @MainActor class the closure is inferred as
        // @MainActor-isolated. CoreMotion then calls it on a background queue, which
        // contradicts that isolation and crashes immediately via
        // `dispatch_assert_queue` (same pitfall as ReplayKit startCapture). The
        // compiler assumes same-isolation calls, so there is no warning — it only
        // surfaces on a real device.
        motionManager.startAccelerometerUpdates(to: queue) { @Sendable [weak self, evaluator] data, _ in
            guard let data else { return }
            let a = data.acceleration
            guard evaluator.process(x: a.x, y: a.y, z: a.z, timestamp: data.timestamp) else { return }
            Task { @MainActor in self?.onTrigger?() }
        }
    }

    /// Stops accelerometer updates and clears the callback.
    func stop() {
        motionManager.stopAccelerometerUpdates()
        onTrigger = nil
    }
}

/// Pure shake-detection logic. Holds internal state under the assumption that it
/// is only called from `ShakeTrigger`'s serial queue (hence `@unchecked Sendable`).
///
/// To avoid false triggers from a single jolt (drop, tap, pocket in/out), a shake
/// is only recognized when several acceleration peaks occur within a time window;
/// a cooldown after firing prevents repeated fires. Thresholds are conservative
/// defaults meant to be tuned.
final class ShakeEvaluator: @unchecked Sendable {
    private let peakThreshold: Double   // Above this g, count one peak
    private let rearmThreshold: Double  // Below this g, start counting the next peak
    private let window: TimeInterval    // Time window for counting peaks (seconds)
    private let cooldown: TimeInterval  // Ignore period after firing (seconds)
    private let requiredPeaks: Int      // Peaks needed to recognize a shake

    private var armed = true
    private var peakCount = 0
    private var firstPeakAt: TimeInterval = 0
    private var lastFireAt: TimeInterval = -.greatestFiniteMagnitude

    init(
        peakThreshold: Double = 2.3,
        rearmThreshold: Double = 1.3,
        window: TimeInterval = 1.0,
        cooldown: TimeInterval = 1.5,
        requiredPeaks: Int = 2
    ) {
        self.peakThreshold = peakThreshold
        self.rearmThreshold = rearmThreshold
        self.window = window
        self.cooldown = cooldown
        self.requiredPeaks = requiredPeaks
    }

    /// Resets state. Call when starting updates.
    func reset() {
        armed = true
        peakCount = 0
        firstPeakAt = 0
        lastFireAt = -.greatestFiniteMagnitude
    }

    /// Feeds one acceleration sample; returns `true` when a shake is recognized.
    /// - Parameters:
    ///   - x: X-axis acceleration (g, gravity included).
    ///   - y: Y-axis acceleration (g, gravity included).
    ///   - z: Z-axis acceleration (g, gravity included).
    ///   - timestamp: Monotonic timestamp (seconds), e.g. `CMAccelerometerData.timestamp`.
    func process(x: Double, y: Double, z: Double, timestamp: TimeInterval) -> Bool {
        // Don't count during the cooldown after firing (suppress repeat fires and rebound peaks).
        if timestamp - lastFireAt < cooldown { return false }

        let magnitude = (x * x + y * y + z * z).squareRoot()

        // Once back to rest or weak acceleration, re-arm to count the next peak.
        if magnitude < rearmThreshold {
            armed = true
            return false
        }

        // Ignore sub-peak values, or the same peak continuing (before re-arm).
        guard magnitude >= peakThreshold, armed else { return false }
        armed = false

        // Restart the count if the window has elapsed.
        if peakCount == 0 || timestamp - firstPeakAt > window {
            peakCount = 1
            firstPeakAt = timestamp
        } else {
            peakCount += 1
        }

        if peakCount >= requiredPeaks {
            lastFireAt = timestamp
            peakCount = 0
            return true
        }
        return false
    }
}
#else
final class ShakeTrigger: TriggerDetecting {
    var onTrigger: (() -> Void)?
    func start() {}
    func stop() {}
}
#endif
