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
            HStack {
                Text("画面収録")
                    .foregroundStyle(FlashbackColor.label)
                Spacer()
                // 「録画が実際に回っているか」を表示（環境の可否=isAvailable ではなく isRecording）。
                // ReportView の状態と意味を揃える。設定画面なので標準色（緑=オン・グレー=オフ）。
                if store.isRecording() {
                    Text("録画中").foregroundStyle(FlashbackColor.success)
                } else {
                    Text("停止中").foregroundStyle(FlashbackColor.secondaryLabel)
                }
            }
            // iOS 設定にトグルが無いため、deep-link ではなく録画の再試行を提供する。
            Button {
                store.retryRecording()
            } label: {
                Text("録画を有効にする")
                    .foregroundStyle(FlashbackColor.settingsLink)   // 青
                    .contentShape(Rectangle())
            }
        } header: {
            Text("録画")
        } footer: {
            Text("画面収録の許可はアプリ起動時に一度だけ確認されます（iOS の仕様上、設定での事前許可はできません）。拒否した場合は「録画を有効にする」で再試行するか、アプリを再起動してください。")
        }
    }
}
#endif
