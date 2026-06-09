#if canImport(SwiftUI)
import SwiftUI

/// Holds settings-screen state and applies changes (SDK-internal, host-independent).
///
/// `@Published` changes are applied straight to the SDK (FAB visibility, retention
/// seconds). Permission state is read live via closures. The Controller creates and
/// owns this, passing it down through ReportView to SettingsView.
@MainActor
final class FlashbackSettingsStore: ObservableObject {
    /// Whether the floating button (FAB) is visible.
    @Published var floatingButtonVisible: Bool {
        didSet { onFloatingButtonVisibleChanged(floatingButtonVisible) }
    }
    /// Retention seconds (one of `retentionOptions`). Changes are persisted to
    /// UserDefaults and applied immediately by the Controller (ring swap), so the
    /// value survives across launches.
    /// Pitfall: init assignment doesn't trigger didSet, so it neither persists nor
    /// applies (same as promptOnLaunch).
    @Published var retentionSeconds: Int {
        didSet {
            UserDefaults.standard.set(retentionSeconds, forKey: Self.retentionSecondsKey)
            onRetentionChanged(retentionSeconds)
        }
    }
    /// Whether screen recording is available (device/environment can record;
    /// `RPScreenRecorder.isAvailable`). Distinct from recording on/off (stays true even
    /// when denied). Used to decide whether to show CTAs.
    let isRecordingAvailable: () -> Bool

    /// Whether recording is actually active (permission confirmed). Drives the
    /// "recording/stopped" indicator in settings. Updated by the Controller via
    /// `ScreenRecorder.onRecordingStateChanged` (@Published auto-updates the UI).
    /// False until the permission dialog is answered (no optimistic true).
    @Published var isRecordingActive: Bool

    /// Whether a retry via "turn on recording" just succeeded. While `true`, the
    /// ReportView empty state shows "recording just enabled" instead of the off state.
    /// The Controller resets it on each presentation so a later empty state isn't
    /// mistakenly shown as justEnabled.
    @Published var recordingJustEnabled = false

    /// Whether to prompt for the screen-recording permission on launch (`startCapture`
    /// right after start). Toggled in settings. Changes are persisted to UserDefaults
    /// and applied immediately by the Controller (on -> buffering starts at once).
    @Published var promptOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(promptOnLaunch, forKey: Self.promptOnLaunchKey)
            onPromptOnLaunchChanged(promptOnLaunch)
        }
    }

    /// Whether to exclude the launch button (and toasts) from OS screenshots/recordings.
    /// Default true (hidden; privacy first). The "show in screenshots/recordings" settings
    /// toggle is the inverse of this value (on = shown = false). Changes are persisted to
    /// UserDefaults and the Controller toggles the overlay exclusion immediately.
    @Published var excludesButtonFromCapture: Bool {
        didSet {
            UserDefaults.standard.set(excludesButtonFromCapture, forKey: Self.excludesButtonFromCaptureKey)
            onExcludesButtonFromCaptureChanged(excludesButtonFromCapture)
        }
    }

    /// Whether the screen-recording priming was already shown once (once per device).
    /// Once `true`, "turn on recording" goes straight to the OS prompt (retry) without
    /// priming. A plain flag with no SDK side effects, so it reads/writes UserDefaults
    /// directly.
    var hasPrimedScreenRecording: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hasPrimedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hasPrimedKey) }
    }

    /// Whether the "shake twice to launch" hint was already shown once (once per device).
    /// Shown once right after the FAB is turned off, and never again after `true`.
    /// A plain flag with no SDK side effects, so it reads/writes UserDefaults directly.
    var hasSeenShakeHint: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hasSeenShakeHintKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hasSeenShakeHintKey) }
    }

    /// Retention-seconds choices.
    static let retentionOptions = [10, 20, 30, 60]

    /// UserDefaults keys (prefixed to avoid colliding with the host app).
    static let promptOnLaunchKey = "FlashbackKit.promptOnLaunch"
    static let retentionSecondsKey = "FlashbackKit.retentionSeconds"
    static let hasPrimedKey = "FlashbackKit.hasPrimedScreenRecording"
    static let hasSeenShakeHintKey = "FlashbackKit.hasSeenShakeHint"
    static let excludesButtonFromCaptureKey = "FlashbackKit.excludesButtonFromCapture"

    private let onFloatingButtonVisibleChanged: (Bool) -> Void
    private let onRetentionChanged: (Int) -> Void
    private let onRetryRecording: () -> Void
    private let onStopRecording: () -> Void
    private let onPromptOnLaunchChanged: (Bool) -> Void
    private let onExcludesButtonFromCaptureChanged: (Bool) -> Void

    init(
        floatingButtonVisible: Bool,
        retentionSeconds: Int,
        promptOnLaunch: Bool,
        excludesButtonFromCapture: Bool,
        isRecordingActive: Bool,
        isRecordingAvailable: @escaping () -> Bool,
        onFloatingButtonVisibleChanged: @escaping (Bool) -> Void,
        onRetentionChanged: @escaping (Int) -> Void,
        onRetryRecording: @escaping () -> Void,
        onStopRecording: @escaping () -> Void,
        onPromptOnLaunchChanged: @escaping (Bool) -> Void,
        onExcludesButtonFromCaptureChanged: @escaping (Bool) -> Void
    ) {
        self.floatingButtonVisible = floatingButtonVisible
        self.retentionSeconds = retentionSeconds
        self.promptOnLaunch = promptOnLaunch            // init assignment doesn't trigger didSet (no persist/side effect)
        self.excludesButtonFromCapture = excludesButtonFromCapture
        self.isRecordingActive = isRecordingActive
        self.isRecordingAvailable = isRecordingAvailable
        self.onFloatingButtonVisibleChanged = onFloatingButtonVisibleChanged
        self.onRetentionChanged = onRetentionChanged
        self.onRetryRecording = onRetryRecording
        self.onStopRecording = onStopRecording
        self.onPromptOnLaunchChanged = onPromptOnLaunchChanged
        self.onExcludesButtonFromCaptureChanged = onExcludesButtonFromCaptureChanged
    }

    /// Retries recording (`startCapture`). Used for granting permission after a denial
    /// and for "turn on recording" from the off state. On iOS the permission dialog
    /// appears at app launch; a retry may re-present it (version-dependent).
    func retryRecording() {
        onRetryRecording()
    }

    /// Stops recording (user action). Resume via "enable recording" / "turn on recording".
    func stopRecording() {
        onStopRecording()
    }
}
#endif
