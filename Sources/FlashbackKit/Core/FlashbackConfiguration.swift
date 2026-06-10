import Foundation

/// Options controlling FlashbackKit's behavior, passed to `Flashback.start(configuration:)`.
///
/// All fields have sensible defaults, so `FlashbackConfiguration()` is a valid starting point.
public struct FlashbackConfiguration: Sendable {
    /// Seconds of recent footage held in the ring buffer. Default 20 (matches the settings
    /// screen's 10/20/30/60 options).
    public var bufferSeconds: TimeInterval

    /// Master on/off switch. Default `true`; when `false`, `Flashback.start()` does nothing.
    /// The SDK does not auto-disable in Release — hosts gate this themselves if they want that.
    public var isEnabled: Bool

    /// The set of triggers that launch the report UI (`OptionSet`, multiple at once).
    /// Default covers both handheld (shake) and stationary (floating button) use.
    /// Narrow it per environment, e.g. `.init(triggers: [.shake])`.
    public var triggers: FlashbackTrigger

    /// Initial corner for `.floatingButton`. Default bottom-trailing.
    /// QA can drag it elsewhere once shown.
    public var floatingButtonCorner: FloatingButtonCorner

    /// Whether to request screen-recording permission at launch (i.e. `startCapture`
    /// immediately). **Default false**: don't show the OS permission dialog at launch; the
    /// user starts recording deliberately via "turn on recording" (priming). Can be opted
    /// into via the settings toggle, and the choice is persisted (this default applies only
    /// on first run, when no persisted value exists).
    public var promptOnLaunch: Bool

    /// Whether to run on the Simulator. **Default false**: ReplayKit in-app capture doesn't
    /// actually work on the Simulator (it reports success but emits no frames), so
    /// `Flashback.start()` does nothing there (no FAB,
    /// triggers, or overlay). This avoids an unusable FAB lingering or onboarding running
    /// when a developer is building a different app on the Simulator or spinning up many
    /// new simulators. Set true only to inspect the SDK's own UI on the Simulator (the
    /// Example app sets it true). Has no effect on device builds (this flag is only read
    /// under `targetEnvironment(simulator)`).
    public var runsOnSimulator: Bool

    /// Creates a configuration. Every parameter has a default, so call sites can override
    /// only what they need (e.g. `FlashbackConfiguration(triggers: [.shake])`).
    public init(
        bufferSeconds: TimeInterval = 20,
        isEnabled: Bool = true,
        triggers: FlashbackTrigger = .default,
        floatingButtonCorner: FloatingButtonCorner = .bottomTrailing,
        promptOnLaunch: Bool = false,
        runsOnSimulator: Bool = false
    ) {
        self.bufferSeconds = bufferSeconds
        self.isEnabled = isEnabled
        self.triggers = triggers
        self.floatingButtonCorner = floatingButtonCorner
        self.promptOnLaunch = promptOnLaunch
        self.runsOnSimulator = runsOnSimulator
    }
}

/// Initial corner for the floating button.
public enum FloatingButtonCorner: Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}
