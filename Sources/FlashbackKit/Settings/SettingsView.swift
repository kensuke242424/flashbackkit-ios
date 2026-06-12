#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// Settings screen (native system look). Pushed from the gear in the report screen.
///
/// Only this screen uses standard iOS colors to feel like Settings.app: back/links blue,
/// toggles green. The one exception is the retention-seconds checkmark, which uses the
/// brand action color (orange).
struct SettingsView: View {
    @ObservedObject var store: FlashbackSettingsStore

    var body: some View {
        Form {
            displaySection
            retentionSection
            permissionSection
            debugSection
        }
        .navigationTitle(Text("Settings", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        // Settings.app look: override the parent ReportView's orange tint with blue
        // (back/links).
        .tint(FlashbackColor.settingsLink)
    }

    // MARK: - Display

    private var displaySection: some View {
        Section {
            // Pin the toggle to green (don't inherit the view's blue tint).
            Toggle(isOn: $store.floatingButtonVisible) {
                Text("Show a launch button on screen", bundle: .module)
            }
                .tint(FlashbackColor.success)
        } header: {
            Text("Display", bundle: .module)
        } footer: {
            Text("Shows a launch button on screen so you can launch a report from it. (You can also launch by shaking the device twice.)", bundle: .module)
        }
    }

    // MARK: - Debug

    /// Rarely-used / diagnostic controls, kept at the bottom out of the way.
    private var debugSection: some View {
        Section {
            // The value is the inverse of the store's exclusion flag (on = shown = not
            // excluded). Default off = hidden. Disabling the exclusion makes the button
            // appear in OS screenshots/recordings, but it still never appears in Flashback's
            // own clip (a separate overlay window that ReplayKit doesn't capture).
            Toggle(isOn: Binding(
                get: { !store.excludesButtonFromCapture },
                set: { store.excludesButtonFromCapture = !$0 }
            )) {
                Text("Show the launch button in OS screenshots and recordings", bundle: .module)
            }
            .tint(FlashbackColor.success)
            // Escape hatch for the secure-entry privacy guard: keep recording while a
            // password field is edited, to capture evidence of bugs around password entry.
            // Default off (guard active). Mid-edit toggles take effect immediately.
            Toggle(isOn: $store.recordsDuringSecureEntry) {
                Text("Keep recording during password entry", bundle: .module)
            }
            .tint(FlashbackColor.success)
        } header: {
            Text("Debug", bundle: .module)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Usually unnecessary. Turn this on only when you want the launch button to appear in OS screenshots/recordings, e.g. for documentation.", bundle: .module)
                Text("\"Keep recording during password entry\": normally recording pauses while a password field is edited so secrets stay out of the clip. When on, the field's content (including the briefly shown last-typed character) is recorded — use it only to capture a bug around password entry.", bundle: .module)
            }
        }
    }

    // MARK: - Retention length

    private var retentionSection: some View {
        Section {
            ForEach(FlashbackSettingsStore.retentionOptions, id: \.self) { seconds in
                Button {
                    store.retentionSeconds = seconds
                } label: {
                    HStack {
                        Text("\(seconds) sec", bundle: .module)
                            .foregroundStyle(FlashbackColor.label)
                        Spacer()
                        if store.retentionSeconds == seconds {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(FlashbackColor.action)   // selection checkmark = action color
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(store.retentionSeconds == seconds ? [.isSelected] : [])
            }
        } header: {
            Text("Recording length to keep", bundle: .module)
        } footer: {
            Text("Keep the selected number of seconds of recording at all times, and write it out when triggered. Longer uses more memory.", bundle: .module)
        }
    }

    // MARK: - Recording (permission)

    private var permissionSection: some View {
        Section {
            // Whether to prompt for permission on launch (default off). Pin the toggle to
            // green (don't inherit the blue tint).
            Toggle(isOn: $store.promptOnLaunch) {
                Text("Confirm permission on launch", bundle: .module)
            }
                .tint(FlashbackColor.success)
            HStack {
                Text("Screen recording", bundle: .module)
                    .foregroundStyle(FlashbackColor.label)
                Spacer()
                // Show whether recording is actually running (the confirmed state
                // isRecordingActive, not environment availability). Only "recording" once
                // permission is confirmed; @Published auto-updates after the response.
                if store.isRecordingActive {
                    Text("Recording", bundle: .module).foregroundStyle(FlashbackColor.success)
                } else {
                    Text("Stopped", bundle: .module).foregroundStyle(FlashbackColor.secondaryLabel)
                }
            }
            // While recording, show a stop action (red). When off and the device can
            // record, show an enable action (blue). When recording is unavailable
            // (Simulator/unsupported; tapping would do nothing), show nothing.
            if store.isRecordingActive {
                Button {
                    store.stopRecording()
                } label: {
                    Text("Stop recording", bundle: .module)
                        .foregroundStyle(FlashbackColor.danger)         // red (turn-off action)
                        .contentShape(Rectangle())
                }
            } else if store.isRecordingAvailable() {
                // iOS has no Settings toggle for this, so offer a recording retry rather
                // than a deep link.
                Button {
                    store.retryRecording()
                } label: {
                    Text("settings.enableRecording", bundle: .module)
                        .foregroundStyle(FlashbackColor.settingsLink)   // blue
                        .contentShape(Rectangle())
                }
            }
        } header: {
            Text("section.recording", bundle: .module)
        } footer: {
            Text("When \"Confirm permission on launch\" is on, screen-recording permission is confirmed right after launch. (Due to iOS, a persistent always-allow in Settings isn't possible.)", bundle: .module)
        }
    }
}
#endif
