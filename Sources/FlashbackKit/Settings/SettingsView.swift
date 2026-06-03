#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// 設定画面（システム純正ルック）。レポート画面の歯車から push される。
///
/// この画面だけは標準 iOS 色で「設定.app 然」とする: 戻る/リンク=青・トグル=緑。
/// 例外として保持秒数の選択チェックのみブランドのアクション色（オレンジ）。
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
        // 設定は「設定.app 然」: 親 ReportView のオレンジ tint を上書きして青（戻る/リンク）に。
        .tint(FlashbackColor.settingsLink)
    }

    // MARK: - 表示

    private var displaySection: some View {
        Section {
            // トグルは緑に固定（view の青 tint に流されないよう明示）。
            Toggle("フローティングボタンを表示", isOn: $store.floatingButtonVisible)
                .tint(FlashbackColor.success)
        } header: {
            Text("表示")
        } footer: {
            Text("オフにすると、シェイク操作のみでレポートを起動します。")
        }
    }

    // MARK: - 保持する録画の長さ

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
                                .foregroundStyle(FlashbackColor.action)   // 選択チェック=アクション色
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

    // MARK: - 録画（権限）

    private var permissionSection: some View {
        Section {
            // 起動時に権限を確認するか（既定オフ）。トグルは緑固定（青 tint に流されないよう明示）。
            Toggle("アプリ起動時に権限を確認する", isOn: $store.promptOnLaunch)
                .tint(FlashbackColor.success)
            HStack {
                Text("画面収録")
                    .foregroundStyle(FlashbackColor.label)
                Spacer()
                // 「録画が実際に回っているか」を表示（環境の可否ではなく確定状態 isRecordingActive）。
                // 許可確定後だけ「録画中」。@Published なので応答後に自動更新される。設定画面は標準色。
                if store.isRecordingActive {
                    Text("録画中").foregroundStyle(FlashbackColor.success)
                } else {
                    Text("停止中").foregroundStyle(FlashbackColor.secondaryLabel)
                }
            }
            // 録画中は停止動線（赤）。録画オフ かつ 端末が録画可能なら有効化動線（青）。
            // 録画不可（Simulator/非対応＝押しても無反応）では何も出さない。
            if store.isRecordingActive {
                Button {
                    store.stopRecording()
                } label: {
                    Text("録画を停止する")
                        .foregroundStyle(FlashbackColor.danger)         // 赤（オフにする操作）
                        .contentShape(Rectangle())
                }
            } else if store.isRecordingAvailable() {
                // iOS 設定にトグルが無いため、deep-link ではなく録画の再試行を提供する。
                Button {
                    store.retryRecording()
                } label: {
                    Text("録画を有効にする")
                        .foregroundStyle(FlashbackColor.settingsLink)   // 青
                        .contentShape(Rectangle())
                }
            }
        } header: {
            Text("録画")
        } footer: {
            Text("「アプリ起動時に権限を確認する」をオンにすると、起動直後に画面収録の許可を確認します。オフのときは「録画をオンにする」を押したときだけ確認します（iOS の仕様上、設定での事前許可はできません）。")
        }
    }
}
#endif
