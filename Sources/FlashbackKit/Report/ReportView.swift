#if canImport(SwiftUI) && canImport(UIKit) && canImport(AVFoundation)
import SwiftUI
import UIKit
import AVFoundation

/// レポート入力 UI: 直前クリップのプレビュー＋トリミング + コメント + 端末情報。
///
/// 出口は右上の「共有（↑）」ひとつ。OS 標準シート経由で 写真に保存 / ファイルに保存 /
/// AirDrop / 他アプリ送信 をまとめて選べる。クリップが無い場合（Simulator / 録画不可）は
/// タイトルのみで「完了」になる。共有 / 完了 を確定した時点でホスト（onReport）へ手渡される。
/// 本ファイルは Presenter（UIKit + SwiftUI 環境）からのみ使われるため UIKit/AVFoundation を前提にする。
struct ReportView: View {
    let clipURL: URL?
    /// レポートに同梱される端末情報（送信前に QA が確認できるよう表示する）。
    /// `DeviceInfo.current()` は `@MainActor` なので、呼び出し側（Presenter）で採取して渡す。
    let device: DeviceInfo
    /// 完了: クリップ無し時（録画不可 / Simulator）の確定。commit して UI を閉じる。
    let onComplete: (String) async -> Void
    /// 共有: 切り出し→commit し、共有シート用の最終クリップ URL を返す。
    let onShare: (String, ClosedRange<Double>?) async -> URL?
    let onCancel: () -> Void

    @State private var title: String = ""
    /// 選択範囲（秒）。`0...0` は未確定で、トリマーが尺確定後に全体へ広げる。
    @State private var selection: ClosedRange<Double> = 0...0
    @State private var shareItem: ShareItem?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let clipURL {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("必要な部分だけ残す")
                                .font(.subheadline.weight(.semibold))
                            VideoTrimmerView(url: clipURL, selection: $selection)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("タイトル")
                            .font(.subheadline.weight(.semibold))
                        TextField("タイトルを入力", text: $title)
                            .textFieldStyle(.roundedBorder)
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
                    .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if clipURL == nil {
                        Button("完了") { complete() }
                            .disabled(title.isEmpty || isWorking)
                    } else {
                        Button(action: share) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("共有")
                        .disabled(isWorking)
                    }
                }
            }
            .overlay {
                if isWorking {
                    ProgressView()
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    private var selectionForClip: ClosedRange<Double>? {
        clipURL == nil ? nil : selection
    }

    private func complete() {
        isWorking = true
        Task {
            await onComplete(title)
            isWorking = false
        }
    }

    private func share() {
        isWorking = true
        Task {
            let url = await onShare(title, selectionForClip)
            isWorking = false
            if let url {
                shareItem = ShareItem(url: url)
            }
        }
    }
}

/// `.sheet(item:)` で扱うための Identifiable な共有対象。
private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// `UIActivityViewController`（OS 標準の共有シート）を SwiftUI に橋渡しする。
/// 端末保存（写真 / ファイル）・AirDrop・他アプリ送信はここから選べる。
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// レポートに同梱される端末情報。枠で囲わず、控えめなグレー文字で補足的に示す。
private struct DeviceInfoCard: View {
    let device: DeviceInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("環境情報")
            row("iphone", device.modelName)   // 人が読む用途なので識別子は付けない（記録用は Slack/ログの displayModel）
            row("gearshape", "\(device.systemName) \(device.systemVersion)")
            row("app.badge", "v\(device.appVersion) (\(device.buildNumber))")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
            Spacer(minLength: 0)
        }
    }
}
#endif
