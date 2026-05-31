import SwiftUI
import FlashbackKit

/// FlashbackKit の仮UIループを確認するためのホスト画面。
///
/// 起動時に `Flashback.start()` を呼ぶと、SDK が overlay window に
/// 既定トリガ（シェイク / 3本指ロングプレス / フローティングボタン 🐞）を仕込む。
/// いずれかのトリガ → ReportView → コメント入力 → 送信 でループが回る。
///
/// 画面中央に「起動からの経過時間」をミリ秒単位で表示する。録画クリップを後で
/// 再生したとき、この数字が動いていれば「トリガー直前の N 秒」が録れている証拠になる。
struct ContentView: View {
    @State private var startDate = Date()

    var body: some View {
        VStack(spacing: 24) {
            Text("FlashbackKit Example")
                .font(.title2.bold())

            // 起動からの経過時間（mm:ss.SSS）。20fps で更新し、録画で動きが見えるようにする。
            TimelineView(.periodic(from: startDate, by: 0.05)) { context in
                Text(Self.elapsedString(from: startDate, to: context.date))
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
            }

            Text("起動からの経過時間。録画クリップでこの数字が動いていれば\n直前 N 秒が録れている証拠になる")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("端末を振る（手持ち）／ 🐞 ボタンを長押し（据え置き）でレポート UI を開く")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .onAppear {
            // Webhook を設定するとここから Slack へ送れる。
            // 未設定（nil）の場合はレポート内容をコンソール出力する。
            // triggers 未指定なので既定（シェイク + フローティングボタン）。
            Flashback.start(
                configuration: .init(slackWebhookURL: nil)
            )
        }
    }

    /// 経過時間を mm:ss.SSS に整形する。
    private static func elapsedString(from start: Date, to now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(start))
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let millis = Int((elapsed - elapsed.rounded(.down)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, millis)
    }
}
