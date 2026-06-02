#if canImport(SwiftUI) && canImport(UIKit) && canImport(AVFoundation)
import SwiftUI
import UIKit
import AVFoundation

/// レポート入力 UI（"Quiet" 確定デザイン・フルスクリーン）。
///
/// 直前クリップのプレビュー＋トリミング・タイトル・端末情報を確認し、右上の
/// **共有（↑）ひとつ**で OS 標準シート（写真 / ファイル / AirDrop / 他アプリ）へ渡す。
/// 出口は共有か ✕（キャンセル）のみ。完了ボタン・送信ボタン・成功トーストは持たない。
///
/// クリップが無い場合は3つの空状態を出し分ける（いずれも成果物を確定しない＝onReport を発火しない）:
/// - **おやすみ（dormant）**: 録画オフだが端末は録画可能（`isRecordingAvailable()==true`）。
///   「録画はオフです」＋「録画をオンにする」（再試行 CTA）を出す。
/// - **録画オン直後（justEnabled）**: 上の CTA が成立した直後。オレンジ録画中マーク＋
///   「録画をオンにしました / ● 録画中」（CTA なし・この回はまだクリップ無し）。
/// - **利用不可（unavailable）**: 端末/環境が録画非対応（`isRecordingAvailable()==false`・
///   Simulator / 非対応端末 / ミラーリング中）。「この端末では画面収録を利用できません」と案内のみ
///   （押しても成立しないため CTA は出さない）。
///
/// 本ファイルは Presenter（UIKit + SwiftUI 環境）からのみ使われるため UIKit/AVFoundation を前提にする。
struct ReportView: View {
    /// 直前クリップ。nil なら「おやすみ（録画オフ）」状態を表示する。
    let clipURL: URL?
    /// レポートに同梱される端末情報（QA が確認できるよう表示する）。
    /// `DeviceInfo.current()` は `@MainActor` なので呼び出し側（Presenter）で採取して渡す。
    let device: DeviceInfo
    /// 共有: 選択範囲を切り出し→commit し、共有シート用の最終クリップ URL を返す。
    let onShare: (String, ClosedRange<Double>?) async -> URL?
    /// キャンセル（✕）。
    let onCancel: () -> Void
    /// 設定画面のストア（歯車 / おやすみ状態の「録画をオンにする」から push）。
    @ObservedObject var settings: FlashbackSettingsStore

    @State private var title = ""
    /// 選択範囲（秒）。`0...0` は未確定で、トリマーが尺確定後に全体へ広げる。
    @State private var selection: ClosedRange<Double> = 0...0
    @State private var shareItem: ShareItem?
    @State private var isWorking = false
    @State private var showingSettings = false

    private var hasClip: Bool { clipURL != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let clipURL {
                        VideoTrimmerView(url: clipURL, selection: $selection)
                        titleField
                    } else if settings.recordingJustEnabled {
                        justEnabledInvitation
                    } else if settings.isRecordingAvailable() {
                        dormantInvitation        // 録画オフ（拒否など）。再試行できるので CTA あり。
                    } else {
                        unavailableInvitation    // この端末/環境では録画不可。CTA なし。
                    }
                    DeviceInfoSection(device: device)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FlashbackColor.background)
            .navigationTitle("レポート")           // 子（設定）の戻るボタン文言。中央は principal で上書き。
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .overlay { workingOverlay }
            .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView(store: settings)
            }
        }
        .tint(FlashbackColor.action)   // ✕ / 共有 / 歯車 / コントロールをオレンジに。
    }

    // MARK: - ナビゲーションバー

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Flashback")                       // ブランド名は英語のまま。中央・label 色。
                .font(FlashbackFont.navTitle)
                .foregroundStyle(FlashbackColor.label)
        }
        ToolbarItem(placement: .cancellationAction) {
            Button(action: onCancel) { Image(systemName: "xmark") }
                .accessibilityLabel("キャンセル")
                .disabled(isWorking)
        }
        // 右グループ: 共有（クリップがある時のみ）→ 歯車（常時）。
        ToolbarItemGroup(placement: .primaryAction) {
            if hasClip {
                Button(action: share) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("共有")
                    .disabled(isWorking)
            }
            Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("設定")
                .disabled(isWorking)
        }
    }

    // MARK: - タイトル（クリップがある時のみ）

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("タイトル")
                .font(FlashbackFont.fieldLabel)
                .foregroundStyle(FlashbackColor.label)
            TextField(
                "",
                text: $title,
                prompt: Text("タイトルを入力").foregroundColor(FlashbackColor.tertiaryLabel)
            )
            .font(FlashbackFont.body)
            .foregroundStyle(FlashbackColor.label)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(FlashbackColor.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(FlashbackColor.separator, lineWidth: 1)
            )
            .submitLabel(.done)
        }
    }

    // MARK: - おやすみ（録画オフ）状態

    private var dormantInvitation: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 破線プレースホルダ箱: 休止マーク＋「録画はオフです」。
            placeholderBox {
                TimeSliceMark.dormantOnSurface()
                    .frame(width: 40, height: 40)
                Text("録画はオフです")
                    .font(FlashbackFont.body)
                    .foregroundStyle(FlashbackColor.secondaryLabel)
            }

            // 中立コピー（QA 特有の「不具合」表現は避ける・README コピー注記準拠）。
            Text("オンにすると、直前の操作の録画を自動で保持します。")
                .font(FlashbackFont.body)
                .foregroundStyle(FlashbackColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            // 録画をオンにする（橙・録画を再試行＝拒否後の後付け許可を狙う）。
            Button { settings.retryRecording() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                    Text("録画をオンにする")
                }
                .font(FlashbackFont.body.weight(.semibold))
                .foregroundStyle(FlashbackColor.action)
            }
            .accessibilityLabel("録画をオンにする")
        }
    }

    // MARK: - 録画不可（Simulator / 非対応環境）状態

    /// 端末/環境が画面収録に対応していない（`isRecordingAvailable() == false`）時の空状態。
    /// 「録画をオンにする」を押しても成立しないため **CTA は出さない**（案内のみ）。
    /// Simulator・非対応端末・ミラーリング中などが該当する。
    private var unavailableInvitation: some View {
        VStack(alignment: .leading, spacing: 16) {
            placeholderBox {
                TimeSliceMark.dormantOnSurface()           // グレー休止マーク
                    .frame(width: 40, height: 40)
                Text("この端末では画面収録を利用できません")
                    .font(FlashbackFont.body)
                    .foregroundStyle(FlashbackColor.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }

            // 中立な補足（なぜ不可か）。CTA は出さない。
            Text("Simulator や画面収録に対応していない環境では録画できません。実機でお試しください。")
                .font(FlashbackFont.body)
                .foregroundStyle(FlashbackColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 録画オン直後（justEnabled）状態

    /// おやすみで「録画をオンにする」が成立した直後の継続状態。マークがグレー休止 →
    /// オレンジ録画中へ変わり、「録画をオンにしました」＋「● 録画中」を示す。今回はまだ
    /// クリップが無いため共有・タイトルは無く、✕ で閉じる（歯車は残る）。CTA も無い。
    private var justEnabledInvitation: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 破線プレースホルダ箱: 録画中マーク（オレンジ）＋肯定見出し＋「● 録画中」ピル。
            placeholderBox {
                TimeSliceMark.recordingOnSurface()
                    .frame(width: 40, height: 40)
                Text("録画をオンにしました")
                    .font(FlashbackFont.body)
                    .foregroundStyle(FlashbackColor.label)
                recordingPill
            }

            // この回はクリップ無し＝「次回から」を伝える中立コピー。
            Text("次回の起動操作から、直前の操作を自動で保持します。")
                .font(FlashbackFont.body)
                .foregroundStyle(FlashbackColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 「● 録画中」ステータスピル（オレンジ点＋オレンジ文字 / 薄いオレンジ tint 背景）。
    private var recordingPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(FlashbackColor.action)
                .frame(width: 6, height: 6)
            Text("録画中")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(FlashbackColor.action)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(FlashbackColor.action.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("録画中")
    }

    /// おやすみ / 録画オン直後で共通の破線プレースホルダ箱（角丸12・破線枠）。
    private func placeholderBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12, content: content)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        FlashbackColor.separator,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            )
    }

    // MARK: - 作業中オーバーレイ（共有の書き出し中）

    @ViewBuilder
    private var workingOverlay: some View {
        if isWorking {
            ProgressView()
                .controlSize(.large)
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - アクション

    private func share() {
        isWorking = true
        Task {
            let url = await onShare(title, selection)
            isWorking = false
            if let url {
                shareItem = ShareItem(url: url)
            }
        }
    }
}

/// 端末情報。枠で囲わず、控えめなグレー文字＋SF Mono で補足的に示す（左寄せ・スタック）。
private struct DeviceInfoSection: View {
    let device: DeviceInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("環境情報")
                .font(FlashbackFont.caption)
                .foregroundStyle(FlashbackColor.tertiaryLabel)
            // 人が読む用途なので識別子は付けない（記録用の displayModel はログ側）。
            row("iphone", device.modelName)
            row("gearshape", "\(device.systemName) \(device.systemVersion)")
            row("app", "v\(device.appVersion) (\(device.buildNumber))")
        }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 16)
            Text(text)
                .font(FlashbackFont.mono)
            Spacer(minLength: 0)
        }
        .foregroundStyle(FlashbackColor.secondaryLabel)
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
#endif
