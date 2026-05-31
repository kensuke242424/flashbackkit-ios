#if canImport(SwiftUI)
import SwiftUI

/// レポート入力 UI: 直前クリップのプレビュー＋トリミング + コメント + 送信。
///
/// `clipURL` が無い場合（Simulator / 録画不可）はコメントのみの最小フォームになる。
struct ReportView: View {
    let clipURL: URL?
    /// レポートに同梱される端末情報（送信前に QA が確認できるよう表示する）。
    /// `DeviceInfo.current()` は `@MainActor` なので、呼び出し側（Presenter）で採取して渡す。
    let device: DeviceInfo
    /// 送信。クリップがある場合は選択範囲（秒）を伴う。無い場合は nil。
    let onSend: (String, ClosedRange<Double>?) -> Void
    let onCancel: () -> Void

    @State private var comment: String = ""
    /// 選択範囲（秒）。`0...0` は未確定で、トリマーが尺確定後に全体へ広げる。
    @State private var selection: ClosedRange<Double> = 0...0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    #if canImport(AVFoundation) && canImport(UIKit)
                    if let clipURL {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("必要な部分だけ残す")
                                .font(.subheadline.weight(.semibold))
                            VideoTrimmerView(url: clipURL, selection: $selection)
                        }
                    }
                    #endif

                    VStack(alignment: .leading, spacing: 6) {
                        Text("何が起きた？")
                            .font(.subheadline.weight(.semibold))
                        TextEditor(text: $comment)
                            .frame(minHeight: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.secondary.opacity(0.3))
                            )
                    }

                    DeviceInfoCard(device: device)
                }
                .padding()
            }
            .navigationTitle("Flashback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("キャンセル")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送信") {
                        onSend(comment, clipURL == nil ? nil : selection)
                    }
                    .disabled(comment.isEmpty)
                }
            }
        }
    }
}

/// レポートに同梱される端末情報の読み取り専用カード。
private struct DeviceInfoCard: View {
    let device: DeviceInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("レポートに含まれる情報")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                row("iphone", device.modelName)   // 人が読む用途なので識別子は付けない（記録用は Slack/ログの displayModel）
                row("gearshape", "\(device.systemName) \(device.systemVersion)")
                row("app.badge", "v\(device.appVersion) (\(device.buildNumber))")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .font(.callout)
            Spacer(minLength: 0)
        }
    }
}
#endif
