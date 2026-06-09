import Foundation

/// FlashbackKit public entry point.
///
/// > Recall the moment before the bug.
public enum Flashback {

    /// Start FlashbackKit.
    /// Begins buffer recording and presents the report UI on any enabled trigger
    /// (default: shake / floating button). Narrow the means via `configuration.triggers`.
    ///
    /// Call once at app launch (in any of SwiftUI `App.init`,
    /// `AppDelegate.didFinishLaunching`, `SceneDelegate.scene(_:willConnectTo:)`, or the
    /// root view's `.onAppear`). Even when called before scene connection
    /// (`didFinishLaunching`) in a SceneDelegate-based app, the SDK waits for scene
    /// connection and installs the overlay window automatically, so it works regardless of
    /// call timing.
    ///
    /// - Parameter onReport: Callback handing the finished `FlashbackReport`
    ///   (title, device info, clip URL) to the host after recording, trimming, and sharing —
    ///   the sole extension point. Host-specific work such as AI summarization, Slack
    ///   delivery, or sending to your own backend goes here (the SDK's job ends at delivering
    ///   the report). Called on the MainActor.
    ///   Note: `report.clipURL` is a temporary file; copy or upload it here if you need to keep it.
    @MainActor
    public static func start(
        configuration: FlashbackConfiguration = .init(),
        onReport: (@MainActor (FlashbackReport) -> Void)? = nil
    ) {
        FlashbackController.shared.start(configuration: configuration, onReport: onReport)
    }

    /// Stop recording and listeners.
    @MainActor
    public static func stop() {
        FlashbackController.shared.stop()
    }
}
