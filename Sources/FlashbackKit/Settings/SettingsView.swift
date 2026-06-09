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
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        // Settings.app look: override the parent ReportView's orange tint with blue
        // (back/links).
        .tint(FlashbackColor.settingsLink)
    }

    // MARK: - Display

    private var displaySection: some View {
        Section {
            // Pin the toggle to green (don't inherit the view's blue tint).
            Toggle("画面上に起動ボタンを表示", isOn: $store.floatingButtonVisible)
                .tint(FlashbackColor.success)
            // The label names the subject (launch button) and "OS" so it self-explains.
            // Disabling the exclusion makes the button appear in OS screenshots/recordings,
            // but it still never appears in Flashback's own clip (a separate overlay window
            // that ReplayKit doesn't capture). "OS" is spelled out to avoid confusion.
            // The value is the inverse of the store's exclusion flag (on = shown = not
            // excluded). Default off = hidden.
            Toggle("起動ボタンを OS のスクリーンショット・録画に写す", isOn: Binding(
                get: { !store.excludesButtonFromCapture },
                set: { store.excludesButtonFromCapture = !$0 }
            ))
            .tint(FlashbackColor.success)
        } header: {
            Text("表示")
        } footer: {
            Text("画面上に起動ボタンを表示し、そこからレポートを起動できます。（端末を2回振っても起動できます。）")
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
                        Text("\(seconds) 秒")
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
            Text("保持する録画の長さ")
        } footer: {
            Text("選択した秒数の録画を常に保持し、発火時に書き出します。長いほどメモリを使います。")
        }
    }

    // MARK: - Recording (permission)

    private var permissionSection: some View {
        Section {
            // Whether to prompt for permission on launch (default off). Pin the toggle to
            // green (don't inherit the blue tint).
            Toggle("アプリ起動時に権限を確認する", isOn: $store.promptOnLaunch)
                .tint(FlashbackColor.success)
            HStack {
                Text("画面収録")
                    .foregroundStyle(FlashbackColor.label)
                Spacer()
                // Show whether recording is actually running (the confirmed state
                // isRecordingActive, not environment availability). Only "recording" once
                // permission is confirmed; @Published auto-updates after the response.
                if store.isRecordingActive {
                    Text("録画中").foregroundStyle(FlashbackColor.success)
                } else {
                    Text("停止中").foregroundStyle(FlashbackColor.secondaryLabel)
                }
            }
            // While recording, show a stop action (red). When off and the device can
            // record, show an enable action (blue). When recording is unavailable
            // (Simulator/unsupported; tapping would do nothing), show nothing.
            if store.isRecordingActive {
                Button {
                    store.stopRecording()
                } label: {
                    Text("録画を停止する")
                        .foregroundStyle(FlashbackColor.danger)         // red (turn-off action)
                        .contentShape(Rectangle())
                }
            } else if store.isRecordingAvailable() {
                // iOS has no Settings toggle for this, so offer a recording retry rather
                // than a deep link.
                Button {
                    store.retryRecording()
                } label: {
                    Text("録画を有効にする")
                        .foregroundStyle(FlashbackColor.settingsLink)   // blue
                        .contentShape(Rectangle())
                }
            }
        } header: {
            Text("録画")
        } footer: {
            Text("「アプリ起動時に権限を確認する」をオンにすると、起動直後に画面収録の許可を確認します。（iOS の仕様上、設定での常時許可はできません。）")
        }
    }
}
#endif
