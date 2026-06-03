#if canImport(SwiftUI)
import SwiftUI

/// Time Slice ロゴのくさび（扇形）Shape。
///
/// 「時の時計」＋「直前 N 秒を切り取る」を表す、12 時から**反時計回り（左斜め上）**に開くパイ片。
/// 正本（design_handoff `_tsWedge`）の仕様どおり、扇は `cd ∈ [−66°, 0°]`＝真上から
/// 反時計回りに 66°（10 時方向の左上）を満たす。巻き戻し（時間を遡る）方向を表す。
///
/// 角度は **時計座標**（0° = 12 時、時計回りに増加）で受ける。SwiftUI の
/// `addArc(clockwise:)` は y 下向き座標で意味が反転して紛らわしいため、
/// 円弧を点サンプリングで描いて向きの曖昧さを排除している。
struct TimeSliceWedge: Shape {
    /// くさびの開始角（12 時基準・時計回り）。既定 0°（真上）。
    var start: Angle = .degrees(0)
    /// 開く角度（真上から反時計回りに開く）。既定 66°。
    var sweep: Angle = .degrees(66)

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)

        let steps = 48
        for i in 0...steps {
            // 真上から反時計回りに開く（cd を負方向へ）→ 左斜め上の扇。
            let clock = start.radians - sweep.radians * Double(i) / Double(steps)
            // 時計座標 → 画面座標: 0° で真上 (0, -r)、時計回りに増加。
            let x = center.x + radius * sin(clock)
            let y = center.y - radius * cos(clock)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }
}

/// Time Slice マーク（リング + くさび + 針 + ハブ）。
///
/// 色と不透明度を差し替えるだけで FAB の4状態（録画中 / 長押し中 / 端タック / 休止）と
/// ロゴ用途を表現できるよう、要素ごとに色を受ける。寸法は viewBox 64 を基準に
/// 与えられた frame へ等倍スケールする（リング半径 20・線幅 3.2・ハブ半径 2.6・針 12時方向 r=18）。
/// 針（12時を指す時計の針）はブランド更新で追加。リング/ハブと同色。
///
/// 呼び出し側で `.frame(width:height:)` を指定して使う（例: FAB マーク 36pt）。
struct TimeSliceMark: View {
    var ringColor: Color
    var wedgeColor: Color
    var hubColor: Color
    var wedgeStart: Angle = .degrees(0)
    var wedgeSweep: Angle = .degrees(66)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let k = side / 64                     // viewBox 64 からのスケール
            let ringDiameter = 40 * k             // 半径 20
            let strokeWidth = 3.2 * k
            let hubDiameter = 5.2 * k             // 半径 2.6
            let handLength = 18 * k               // 中心→12時の針（r=18・リング内側 2 手前）

            ZStack {
                Circle()
                    .stroke(ringColor, lineWidth: strokeWidth)
                    .frame(width: ringDiameter, height: ringDiameter)

                TimeSliceWedge(start: wedgeStart, sweep: wedgeSweep)
                    .fill(wedgeColor)
                    .frame(width: ringDiameter, height: ringDiameter)

                // 針（12時方向）。リング/ハブと同色・丸キャップ。中心から真上へ伸ばす。
                Capsule()
                    .fill(ringColor)
                    .frame(width: strokeWidth, height: handLength)
                    .offset(y: -handLength / 2)

                Circle()
                    .fill(hubColor)
                    .frame(width: hubDiameter, height: hubDiameter)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)               // 装飾。意味は親の accessibilityLabel が持つ。
    }
}

extension TimeSliceMark {
    /// ブランドロゴ用（リング/ハブ = label・くさび = アクションオレンジ）。
    static func logo() -> TimeSliceMark {
        TimeSliceMark(ringColor: FlashbackColor.label,
                      wedgeColor: FlashbackColor.action,
                      hubColor: FlashbackColor.label)
    }

    /// 録画 OFF（休止 / おやすみ）のマーク。グレーのリング＋中立くさび。
    /// ReportView の空状態（明るいサーフェス上）では白の薄いくさびが消えるため、
    /// くさびはグレー @0.55 を使う（README の "Neutral on light surface"）。
    static func dormantOnSurface() -> TimeSliceMark {
        TimeSliceMark(ringColor: FlashbackColor.slate,
                      wedgeColor: FlashbackColor.slate.opacity(0.55),
                      hubColor: FlashbackColor.slate)
    }

    /// プライミング（事前説明）のヒーローマーク。まだ録画オフなので Slate 中立。
    /// くさびは控えめ（@0.45）で「これからオンにする」ニュアンス（正本 priming.jsx 準拠）。
    static func primingNeutral() -> TimeSliceMark {
        TimeSliceMark(ringColor: FlashbackColor.slate,
                      wedgeColor: FlashbackColor.slate.opacity(0.45),
                      hubColor: FlashbackColor.slate)
    }

    /// 録画オン直後（録画中）のマーク。明るいサーフェス上でオレンジ一色。
    /// 色ルール「グレー→オレンジ＝録画中」を表す（ReportView の justEnabled 状態）。
    static func recordingOnSurface() -> TimeSliceMark {
        TimeSliceMark(ringColor: FlashbackColor.action,
                      wedgeColor: FlashbackColor.action,
                      hubColor: FlashbackColor.action)
    }
}

/// FlashbackKit ワードマーク。"Flashback"（label）+ "Kit"（オレンジ）、semibold、軽いトラッキング。
/// ブランド名は英語のまま（UI ラベルは日本語）。
struct FlashbackWordmark: View {
    var size: Font.TextStyle = .headline

    var body: some View {
        (Text("Flashback").foregroundColor(FlashbackColor.label)
         + Text("Kit").foregroundColor(FlashbackColor.action))
            .font(.system(size, design: .default).weight(.semibold))
            .tracking(-0.3)                       // ≈ -0.02em
            .accessibilityLabel("FlashbackKit")
    }
}

/// マーク + ワードマークのロゴロックアップ。
struct FlashbackLogo: View {
    var markSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 6) {
            TimeSliceMark.logo()
                .frame(width: markSize, height: markSize)
            FlashbackWordmark()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("FlashbackKit")
    }
}

#if DEBUG
#Preview("Time Slice") {
    VStack(spacing: 28) {
        FlashbackLogo()
        HStack(spacing: 20) {
            // 録画中（オレンジ FAB 想定: 白リング・白@0.5 くさび）
            TimeSliceMark(ringColor: .white,
                          wedgeColor: .white.opacity(0.5),
                          hubColor: .white)
                .frame(width: 36, height: 36)
                .padding(10)
                .background(FlashbackColor.action, in: Circle())

            // 端タック（グレー FAB・オレンジ@1.0 くさび）
            TimeSliceMark(ringColor: .white,
                          wedgeColor: FlashbackColor.action,
                          hubColor: .white)
                .frame(width: 36, height: 36)
                .padding(10)
                .background(FlashbackColor.slate.opacity(0.82), in: Circle())

            // 休止（明るいサーフェス上）
            TimeSliceMark.dormantOnSurface()
                .frame(width: 36, height: 36)
        }
    }
    .padding(40)
}
#endif
#endif
