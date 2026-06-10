import Foundation

/// FlashbackKit public entry point.
///
/// > Recall the moment before the bug.
public enum Flashback {

    /// Start FlashbackKit.
    /// Installs the triggers and overlay (default: shake / floating button) and arms the SDK
    /// to present the report UI when a trigger fires. Narrow the means via `configuration.triggers`.
    ///
    /// Recording does not begin here: with the default `promptOnLaunch: false`, nothing is
    /// recorded (and no iOS permission prompt appears) until the tester turns recording on —
    /// or until launch, if you set `promptOnLaunch: true`.
    ///
    /// Call once at app launch (in any of SwiftUI `App.init`,
    /// `AppDelegate.didFinishLaunching`, `SceneDelegate.scene(_:willConnectTo:)`, or the
    /// root view's `.onAppear`). Even when called before scene connection
    /// (`didFinishLaunching`) in a SceneDelegate-based app, the SDK waits for scene
    /// connection and installs the overlay window automatically, so it works regardless of
    /// call timing.
    ///
    /// - Parameters:
    ///   - configuration: Behavior options (buffer seconds, triggers, etc.). Defaults to `.init()`.
    ///   - onReport: Callback handing the finished `FlashbackReport`
    ///     (title, device info, clip URL) to the host after recording, trimming, and sharing —
    ///     the sole extension point. Host-specific work such as AI summarization, Slack
    ///     delivery, or sending to your own backend goes here (the SDK's job ends at delivering
    ///     the report). Called on the MainActor.
    ///     Note: `report.clipURL` is a temporary file; copy or upload it here if you need to keep it.
    @MainActor
    public static func start(
        configuration: FlashbackConfiguration = .init(),
        onReport: (@MainActor (FlashbackReport) -> Void)? = nil
    ) {
        FlashbackController.shared.start(configuration: configuration, onReport: onReport)
    }

    /// Stop FlashbackKit.
    /// Stops buffer recording, removes all triggers, and tears down the overlay window —
    /// the counterpart to `start()`. Safe to call even if `start()` wasn't called.
    @MainActor
    public static func stop() {
        FlashbackController.shared.stop()
    }
}
