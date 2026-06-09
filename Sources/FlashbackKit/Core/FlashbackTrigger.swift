/// The set of triggers that launch the report UI.
///
/// Being an `OptionSet`, multiple means can be enabled at once. Choose per environment:
/// shake for handheld devices, the floating button for stationary / fixed-stand use.
///
/// ```swift
/// Flashback.start()                                   // default: all means on
/// Flashback.start(configuration: .init(triggers: [.shake]))          // handheld only
/// Flashback.start(configuration: .init(triggers: [.floatingButton])) // stationary only (reliable)
/// ```
///
/// Future triggers are added by appending a new bit, without breaking the existing
/// `rawValue` or `.default` (forward compatible).
public struct FlashbackTrigger: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Shaking the device. For handheld use. Detected via the accelerometer, so it does not
    /// fire on the Simulator.
    public static let shake = FlashbackTrigger(rawValue: 1 << 0)

    /// A small floating button (Time Slice mark) that stays on screen; long-press to launch.
    /// As a real button it fires reliably and doesn't block host interaction. A dependable
    /// means for stationary use such as a fixed stand. Can be dragged to reposition.
    public static let floatingButton = FlashbackTrigger(rawValue: 1 << 1)

    /// Default trigger set. Covers both handheld (shake) and stationary (floating button).
    public static let `default`: FlashbackTrigger = [.shake, .floatingButton]
}
