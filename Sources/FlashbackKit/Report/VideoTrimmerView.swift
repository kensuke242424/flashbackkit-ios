#if canImport(SwiftUI) && canImport(AVFoundation) && canImport(UIKit)
import SwiftUI
import AVFoundation
import UIKit

/// 直前クリップのプレビュー＋範囲トリミング UI。
///
/// プレビュー（`AVPlayerLayer`）の下にサムネイルのフィルムストリップを敷き、両端の
/// ハンドルで保存範囲を選ぶ。選択範囲は秒で `selection` に双方向バインドする。
/// 依存ゼロ（AVFoundation / SwiftUI / UIKit のみ）。
@MainActor
struct VideoTrimmerView: View {
    let url: URL
    /// 選択範囲（秒）。`lowerBound == upperBound` の初期値を渡すと、尺確定後に全体へ広げる。
    @Binding var selection: ClosedRange<Double>

    /// これ以上は詰められない最小選択長（秒）。
    private let minimumDuration: Double = 1.0

    @State private var player = AVPlayer()
    @State private var duration: Double = 0
    @State private var thumbnails: [UIImage] = []
    @State private var playhead: Double = 0
    @State private var isPlaying = false
    @State private var timeObserver: Any?
    /// 動画の表示アスペクト比（幅/高さ）。尺確定時に実トラックから求め、プレビュー枠を
    /// これに合わせることで黒帯（レターボックス）を出さない。確定までは縦動画想定の暫定値。
    @State private var videoAspect: CGFloat = 9.0 / 16.0

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer(minLength: 0)
                PlayerLayerView(player: player)
                    .aspectRatio(videoAspect, contentMode: .fit)
                    .frame(maxHeight: 280)
                    .background(.black, in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        if duration == 0 {
                            ProgressView().tint(.white)
                        } else if !isPlaying {
                            // 中央の再生アフォーダンス（ポスター表示）。
                            Button(action: togglePlay) {
                                Image(systemName: "play.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .padding(16)
                                    .background(.black.opacity(0.35), in: Circle())
                            }
                            .accessibilityLabel("再生")
                        }
                    }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                // 小さな円形オレンジ再生ボタン（30pt）。
                Button(action: togglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FlashbackColor.onAction)
                        .frame(width: 30, height: 30)
                        .background(FlashbackColor.action, in: Circle())
                }
                .disabled(duration == 0)
                .accessibilityLabel(isPlaying ? "一時停止" : "再生")

                Text(rangeLabel)
                    .font(FlashbackFont.timecode)
                    .foregroundStyle(FlashbackColor.secondaryLabel)
                Spacer()
            }

            FilmstripTrimmer(
                thumbnails: thumbnails,
                duration: duration,
                minimumDuration: minimumDuration,
                playhead: playhead,
                selection: $selection,
                onScrub: { seconds in seek(to: seconds) }
            )
            .frame(height: 56)
        }
        .task(id: url) { await load() }
        .onDisappear { teardown() }
    }

    private var rangeLabel: String {
        guard duration > 0 else { return "—" }
        return "\(format(selection.lowerBound)) ~ \(format(selection.upperBound))  (\(format(selection.upperBound - selection.lowerBound)))"
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - 読み込み

    private func load() async {
        let asset = AVURLAsset(url: url)
        guard let loaded = try? await asset.load(.duration) else { return }
        let seconds = CMTimeGetSeconds(loaded)
        guard seconds.isFinite, seconds > 0 else { return }

        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        duration = seconds
        // 初期値（未設定）なら全体を選択範囲にする。
        if selection.lowerBound >= selection.upperBound {
            selection = 0...seconds
        }
        // 実トラックから表示アスペクト比を求めてプレビュー枠を合わせる（黒帯を出さない）。
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let natural = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let displayed = natural.applying(transform)
            let w = abs(displayed.width), h = abs(displayed.height)
            if w > 0, h > 0 { videoAspect = w / h }
        }
        addObserver()
        await generateThumbnails(asset: asset, duration: seconds)
    }

    private func generateThumbnails(asset: AVURLAsset, duration: Double) async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let count = 8
        var images: [UIImage] = []
        for i in 0..<count {
            let t = duration * Double(i) / Double(count - 1)
            let time = CMTime(seconds: t, preferredTimescale: 600)
            if let cg = try? await generator.image(at: time).image {
                images.append(UIImage(cgImage: cg))
            }
        }
        thumbnails = images
    }

    // MARK: - 再生

    private func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // 再生ヘッドが選択範囲外なら先頭から。
            if playhead < selection.lowerBound || playhead >= selection.upperBound {
                seek(to: selection.lowerBound)
            }
            player.play()
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), duration)
        playhead = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func addObserver() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.03, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            // periodic observer は @Sendable closure。MainActor 隔離の State へは Task で戻す。
            let seconds = CMTimeGetSeconds(time)
            Task { @MainActor in
                playhead = seconds
                // 選択範囲の終端でループ。
                if isPlaying, seconds >= selection.upperBound {
                    seek(to: selection.lowerBound)
                }
            }
        }
    }

    private func teardown() {
        player.pause()
        isPlaying = false
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}

/// `AVPlayerLayer` を SwiftUI に橋渡しする最小ビュー（既定コントロール無し）。
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// サムネイルのフィルムストリップ＋両端ハンドル＋再生ヘッド。
private struct FilmstripTrimmer: View {
    let thumbnails: [UIImage]
    let duration: Double
    let minimumDuration: Double
    let playhead: Double
    @Binding var selection: ClosedRange<Double>
    let onScrub: (Double) -> Void

    private let handleWidth: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let usable = max(width - handleWidth * 2, 1)
            let startX = handleWidth + xOffset(for: selection.lowerBound, usable: usable)
            let endX = handleWidth + xOffset(for: selection.upperBound, usable: usable)

            ZStack(alignment: .leading) {
                filmstrip(width: width, height: height)

                // 選択外を暗く。
                dim(width: startX, height: height)
                dim(width: width - endX, height: height).offset(x: endX)

                // 選択枠: 背景色の外輪（2pt）＋アクション色の枠（2.5pt）。
                RoundedRectangle(cornerRadius: 6)
                    .stroke(FlashbackColor.background, lineWidth: 6)
                    .frame(width: max(endX - startX, 0), height: height)
                    .offset(x: startX)
                RoundedRectangle(cornerRadius: 6)
                    .stroke(FlashbackColor.action, lineWidth: 2.5)
                    .frame(width: max(endX - startX, 0), height: height)
                    .offset(x: startX)

                handle(at: startX, height: height, usable: usable, isStart: true)
                handle(at: endX, height: height, usable: usable, isStart: false)

                // 再生ヘッド（label 色の細い縦バー）。
                if duration > 0 {
                    Rectangle()
                        .fill(FlashbackColor.label)
                        .frame(width: 2, height: height)
                        .offset(x: handleWidth + xOffset(for: playhead, usable: usable))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .coordinateSpace(name: "strip")
        }
    }

    /// 高さを明示しオーバーフローさせない（縛らないと .fill が縦に溢れて下の UI に被る）。
    private func filmstrip(width: CGFloat, height: CGFloat) -> some View {
        let count = max(thumbnails.count, 1)
        let cellWidth = width / CGFloat(count)
        return HStack(spacing: 0) {
            if thumbnails.isEmpty {
                Rectangle().fill(.gray.opacity(0.3))
            } else {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cellWidth, height: height)
                        .clipped()
                }
            }
        }
        .frame(width: width, height: height)
    }

    private func dim(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(.black.opacity(0.5))
            .frame(width: max(width, 0), height: height)
            .allowsHitTesting(false)
    }

    /// 指の絶対位置（"strip" 座標）で追従するハンドル。translation 累積のドリフトを避ける。
    private func handle(at x: CGFloat, height: CGFloat, usable: CGFloat, isStart: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(FlashbackColor.action)
            .frame(width: handleWidth, height: height)
            .overlay(
                Capsule().fill(FlashbackColor.onAction).frame(width: 3, height: 18)
            )
            .offset(x: x - handleWidth / 2)
            .accessibilityLabel(isStart ? "開始位置" : "終了位置")
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("strip"))
                    .onChanged { value in
                        let seconds = secondsForX(value.location.x - handleWidth, usable: usable)
                        if isStart {
                            let upper = selection.upperBound
                            let newLower = min(max(seconds, 0), upper - minimumDuration)
                            selection = newLower...upper
                            onScrub(newLower)
                        } else {
                            let lower = selection.lowerBound
                            let newUpper = max(min(seconds, duration), lower + minimumDuration)
                            selection = lower...newUpper
                            onScrub(newUpper)
                        }
                    }
            )
    }

    private func xOffset(for seconds: Double, usable: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return usable * CGFloat(seconds / duration)
    }

    private func secondsForX(_ x: CGFloat, usable: CGFloat) -> Double {
        guard usable > 0 else { return 0 }
        return Double(x / usable) * duration
    }
}
#endif
