import SwiftUI
import FlashbackKit

/// FlashbackKit の仮UIループを確認するためのホスト画面。
///
/// 起動時に `Flashback.start()` を呼ぶと、SDK が overlay window に
/// 既定トリガ（シェイク / フローティングボタン）を仕込む。
/// いずれかのトリガ → ReportView → タイトル入力 → 共有 でループが回る。
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

            Text("端末を振る（手持ち）／ フローティングボタンを長押し（据え置き）でレポート UI を開く")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            #if DEBUG
            // Simulator では ReplayKit 実録画が動かず本物のクリップが出ないため、
            // 合成サンプル動画でトリミング UX を確認するためのデバッグ入口。
            Button {
                Flashback.debugPresentSampleReport()
            } label: {
                Label("サンプル動画でトリマーを開く", systemImage: "scissors")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            // クリップ無し（録画オフ）時の「おやすみ」案内 UI を確認するための入口。
            Button {
                Flashback.debugPresentEmptyReport()
            } label: {
                Label("おやすみ状態を開く", systemImage: "moon")
            }
            .buttonStyle(.bordered)

            // 「録画オン直後」状態（オレンジマーク＋録画中）を確認するための入口。
            Button {
                Flashback.debugPresentRecordingJustEnabled()
            } label: {
                Label("録画オン直後を開く", systemImage: "record.circle")
            }
            .buttonStyle(.bordered)

            // 「録画不可（この端末では利用できません）」状態を確認するための入口。
            Button {
                Flashback.debugPresentReportUnavailable()
            } label: {
                Label("録画不可状態を開く", systemImage: "iphone.slash")
            }
            .buttonStyle(.bordered)

            // 画面収録 許可プライミングのシートを確認するための入口。
            Button {
                Flashback.debugPresentPriming()
            } label: {
                Label("許可プライミングを開く", systemImage: "hand.raised")
            }
            .buttonStyle(.bordered)

            // 設定画面を確認するための入口。
            Button {
                Flashback.debugPresentSettings()
            } label: {
                Label("設定を開く", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            #endif
        }
        .onAppear {
            // triggers 未指定なので既定（シェイク + フローティングボタン）。
            Flashback.start(
                // ハンドオフ: 録画→トリム→共有まで終えた成果物がここに届く。
                // AI 要約・Slack 送信・自社連携はホスト側で自由に（ここでは demo としてログ出力）。
                onReport: { report in
                    print("[Flashback] onReport: \(report.device.displayModel) / \(report.title)")
                    if let clip = report.clipURL {
                        print("[Flashback] clip: \(clip.path)")
                    }
                }
            )

            #if DEBUG
            // 環境変数 FLASHBACK_TRIM_DEMO が立っていれば起動直後にトリマーを自動提示する
            // （Simulator/自動検証でトリミング UX を確認するため）。
            if ProcessInfo.processInfo.environment["FLASHBACK_TRIM_DEMO"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    Flashback.debugPresentSampleReport()
                }
            }
            // FLASHBACK_EMPTY_DEMO が立っていれば起動直後に「おやすみ」状態を自動提示する。
            if ProcessInfo.processInfo.environment["FLASHBACK_EMPTY_DEMO"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    Flashback.debugPresentEmptyReport()
                }
            }
            // FLASHBACK_JUST_ENABLED_DEMO で起動直後に「録画オン直後」状態を自動提示する。
            if ProcessInfo.processInfo.environment["FLASHBACK_JUST_ENABLED_DEMO"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    Flashback.debugPresentRecordingJustEnabled()
                }
            }
            // FLASHBACK_UNAVAILABLE_DEMO で起動直後に「録画不可」状態を自動提示する。
            if ProcessInfo.processInfo.environment["FLASHBACK_UNAVAILABLE_DEMO"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    Flashback.debugPresentReportUnavailable()
                }
            }
            // FLASHBACK_PRIMING_DEMO で起動直後に許可プライミングのシートを自動提示する。
            if ProcessInfo.processInfo.environment["FLASHBACK_PRIMING_DEMO"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    Flashback.debugPresentPriming()
                }
            }
            // FLASHBACK_TOAST_DEMO=progress|failure で起動直後にトーストを自動表示する。
            if let toastKind = ProcessInfo.processInfo.environment["FLASHBACK_TOAST_DEMO"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    Flashback.debugShowToast(toastKind)
                }
            }
            // FLASHBACK_SETTINGS_DEMO で起動直後に設定画面を自動提示する。
            if ProcessInfo.processInfo.environment["FLASHBACK_SETTINGS_DEMO"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    Flashback.debugPresentSettings()
                }
            }
            #endif
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
