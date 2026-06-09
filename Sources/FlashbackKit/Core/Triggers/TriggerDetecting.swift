/// Shared interface for the detectors that fire a report-launch trigger.
///
/// `FlashbackController` creates one detector per enabled `FlashbackTrigger`;
/// whichever one fires funnels into a single handler via `onTrigger`.
///
/// `@MainActor` because it touches UI and detection.
@MainActor
protocol TriggerDetecting: AnyObject {
    /// Called when the trigger fires. Set before calling `start()`.
    var onTrigger: (() -> Void)? { get set }

    /// Starts detection. No-op on environments where it is unavailable.
    func start()

    /// Stops detection and clears the callback.
    func stop()
}
