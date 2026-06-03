import SwiftUI
import FlashbackKit

/// FlashbackKit の仮UIループを確認するためのホスト画面。
///
/// 起動時に `Flashback.start()` を呼ぶと、SDK が overlay window に
/// 既定トリガ（シェイク / フローティングボタン）を仕込む。
/// いずれかのトリガ → ReportView → タイトル入力 → 共有 でループが回る。
///
/// 録画の成否を確認しやすいよう、画面に「動き」を用意している:
/// - ホームタブ … 常時アニメーションするオブジェクト＋経過時間
/// - タブ切替・各タブのスクロール … 画面遷移が録画クリップに明確に残る
struct ContentView: View {
    @State private var startDate = Date()

    var body: some View {
        TabView {
            HomeTab(startDate: startDate)
                .tabItem { Label("ホーム", systemImage: "house") }
            DummyListTab()
                .tabItem { Label("リスト", systemImage: "list.bullet") }
            DummyGalleryTab()
                .tabItem { Label("ギャラリー", systemImage: "square.grid.2x2") }
            #if DEBUG
            DebugTab()
                .tabItem { Label("デバッグ", systemImage: "ladybug") }
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
            Self.presentDemosFromEnvironment()
            #endif
        }
    }

    #if DEBUG
    /// 環境変数で指定された状態を起動直後に自動提示する（Simulator / 自動検証用）。
    static func presentDemosFromEnvironment() {
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
}

// MARK: - ホームタブ

/// 起動状況・常時アニメーション・デバッグ入口を載せたホーム。
private struct HomeTab: View {
    let startDate: Date

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("FlashbackKit Example")
                    .font(.title2.bold())

                // 録画動作確認用の常時アニメーション（横移動＋回転＋色変化）。
                MotionDemo(start: startDate)
                    .frame(height: 84)
                    .padding(.horizontal, 24)

                // 起動からの経過時間（mm:ss.SSS）。20fps で更新。動きの時刻づけ用。
                TimelineView(.periodic(from: startDate, by: 0.05)) { context in
                    Text(Self.elapsedString(from: startDate, to: context.date))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                }

                Text("オブジェクトの動き／タブ切替・スクロールが録画クリップに残れば、\n直前 N 秒がちゃんと録れている証拠になる")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("端末を振る（手持ち）／ フローティングボタンを長押し（据え置き）でレポート UI を開く")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
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

// MARK: - ダミーUIタブ（録画に画面遷移を残すため）

/// スクロールするダミー一覧。タブ切替＋スクロールで録画に動きが残る。
private struct DummyListTab: View {
    private let symbols = ["star.fill", "bell.fill", "bolt.fill", "leaf.fill", "flame.fill",
                           "drop.fill", "moon.fill", "heart.fill", "cloud.fill", "sun.max.fill"]
    var body: some View {
        NavigationStack {
            List(0..<30, id: \.self) { i in
                HStack(spacing: 12) {
                    Image(systemName: symbols[i % symbols.count])
                        .font(.title3)
                        .foregroundStyle(Color(hue: Double(i % 10) / 10, saturation: 0.7, brightness: 0.9))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("アイテム \(i + 1)").font(.body)
                        Text("ダミー行 — スクロールで動きを確認").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("リスト")
        }
    }
}

/// 色付きカードのグリッド。スクロールで動きが出る。
private struct DummyGalleryTab: View {
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<24, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(hue: Double(i) / 24, saturation: 0.65, brightness: 0.92))
                            .frame(height: 100)
                            .overlay(
                                Text("\(i + 1)")
                                    .font(.title.bold())
                                    .foregroundStyle(.white.opacity(0.9))
                            )
                    }
                }
                .padding(16)
            }
            .navigationTitle("ギャラリー")
        }
    }
}

// MARK: - デバッグタブ（各状態の即プレビュー・DEBUG 限定）

#if DEBUG
/// 各 ReportView 状態 / 設定 / プライミングを即プレビューする開発用入口を集約したタブ。
/// ホームをすっきり保つため、これらはここへ寄せる（env 変数でも起動直後に提示可能）。
private struct DebugTab: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Simulator では ReplayKit 実録画が動かないため、合成サンプル動画で
                    // トリミング UX を確認する入口。
                    Button {
                        Flashback.debugPresentSampleReport()
                    } label: {
                        Label("サンプル動画でトリマーを開く", systemImage: "scissors")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Flashback.debugPresentEmptyReport()
                    } label: {
                        Label("おやすみ状態を開く", systemImage: "moon")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Flashback.debugPresentRecordingJustEnabled()
                    } label: {
                        Label("録画オン直後を開く", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Flashback.debugPresentReportUnavailable()
                    } label: {
                        Label("録画不可状態を開く", systemImage: "iphone.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Flashback.debugPresentPriming()
                    } label: {
                        Label("許可プライミングを開く", systemImage: "hand.raised")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Flashback.debugPresentSettings()
                    } label: {
                        Label("設定を開く", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
            }
            .navigationTitle("デバッグ")
        }
    }
}
#endif

// MARK: - 常時アニメーション

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
