import SwiftUI
import FlashbackKit

/// FlashbackKit の仮UIループを確認するためのホスト画面。
///
/// 起動時に `Flashback.start()` を呼ぶと、SDK が overlay window に
/// 既定トリガ（シェイク / フローティングボタン）を仕込む。
/// いずれかのトリガ → ReportView → タイトル入力 → 共有 でループが回る。
///
/// 画面上部に「常時アニメーションするオブジェクト」と「起動からの経過時間」を出す。
/// 録画クリップを後で再生したとき、オブジェクトが動き・数字が進んでいれば
/// 「トリガー直前の N 秒」がちゃんと録れている証拠になる。
struct ContentView: View {
    @State private var startDate = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("FlashbackKit Example")
                    .font(.title2.bold())

                // 録画動作確認用の常時アニメーション（横移動＋回転＋色変化）。
                // 録画クリップのどの瞬間を見ても「動いている」ことが分かるようにする。
                MotionDemo(start: startDate)
                    .frame(height: 84)
                    .padding(.horizontal, 24)

                // 起動からの経過時間（mm:ss.SSS）。20fps で更新。動きの時刻づけ用に併置。
                TimelineView(.periodic(from: startDate, by: 0.05)) { context in
                    Text(Self.elapsedString(from: startDate, to: context.date))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                }

                Text("上のオブジェクトが動き・数字が進んでいれば、録画クリップに\n直前 N 秒の動きが残っている証拠になる")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("端末を振る（手持ち）／ フローティングボタンを長押し（据え置き）でレポート UI を開く")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                #if DEBUG
                debugButtons
                #endif
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
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
            presentDemosFromEnvironment()
            #endif
        }
    }

    #if DEBUG
    /// デバッグ用の各状態への入口（Simulator / 見た目確認）。
    @ViewBuilder
    private var debugButtons: some View {
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
    }

    /// 環境変数で指定された状態を起動直後に自動提示する（Simulator / 自動検証用）。
    private func presentDemosFromEnvironment() {
        let env = ProcessInfo.processInfo.environment
        func after(_ delay: TimeInterval, _ action: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
        if env["FLASHBACK_TRIM_DEMO"] != nil { after(0.5) { Flashback.debugPresentSampleReport() } }
        if env["FLASHBACK_EMPTY_DEMO"] != nil { after(0.5) { Flashback.debugPresentEmptyReport() } }
        if env["FLASHBACK_JUST_ENABLED_DEMO"] != nil { after(0.5) { Flashback.debugPresentRecordingJustEnabled() } }
        if env["FLASHBACK_UNAVAILABLE_DEMO"] != nil { after(0.5) { Flashback.debugPresentReportUnavailable() } }
        if env["FLASHBACK_PRIMING_DEMO"] != nil { after(0.5) { Flashback.debugPresentPriming() } }
        if let toastKind = env["FLASHBACK_TOAST_DEMO"] { after(0.6) { Flashback.debugShowToast(toastKind) } }
        if env["FLASHBACK_SETTINGS_DEMO"] != nil { after(0.5) { Flashback.debugPresentSettings() } }
    }
    #endif

    /// 経過時間を mm:ss.SSS に整形する。
    private static func elapsedString(from start: Date, to now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(start))
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let millis = Int((elapsed - elapsed.rounded(.down)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, millis)
    }
}

/// 録画動作確認用の常時アニメーション（Example 専用）。
///
/// 横移動（三角波バウンド）＋回転＋色相サイクルの3要素を持たせ、録画クリップの
/// どの瞬間を切り取っても「動いている」ことが一目で分かるようにする。
/// `TimelineView(.animation)` で表示リフレッシュに同期して滑らかに動かす。
private struct MotionDemo: View {
    let start: Date

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            let period = 2.4
            let phase = t.truncatingRemainder(dividingBy: period) / period   // 0..1
            let tri = phase < 0.5 ? phase * 2 : (1 - phase) * 2               // 0→1→0（左右バウンド）
            let hue = (t / 6).truncatingRemainder(dividingBy: 1)             // 色相を 6 秒周期で一巡

            GeometryReader { geo in
                let size: CGFloat = 60
                let x = (geo.size.width - size) * tri
                let y = (geo.size.height - size) / 2
                ZStack(alignment: .topLeading) {
                    // 走行レーン（位置変化を分かりやすく）。
                    Capsule()
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 6)
                        .frame(maxWidth: .infinity)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    Circle()
                        .fill(Color(hue: hue, saturation: 0.75, brightness: 0.9))
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "location.north.fill")     // 向きで回転が見える
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(t * 120))        // 1.33 回転/秒
                        )
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                        .offset(x: x, y: y)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
