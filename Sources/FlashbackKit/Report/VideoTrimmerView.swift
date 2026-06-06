#if canImport(SwiftUI) && canImport(AVFoundation) && canImport(UIKit)
import SwiftUI
import AVFoundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

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
    /// プレビュー枠の最大高さ。ハーフモーダルでは小さく、展開時は大きく渡す。
    var previewMaxHeight: CGFloat = 280
    /// 再生ヘッド位置の 1 フレームをフル解像度で画像化し、共有用の一時ファイル URL を渡す。
    /// `nil` ならカメラ（静止画キャプチャ）ボタンを出さない。
    var onCaptureStill: ((URL) -> Void)? = nil
    /// キャプチャ時点のタイトル（レポート入力）を返す。クリップ共有と同様、ファイル名と
    /// 画像メタデータの title へ反映する。入力途中の最新値を読むためクロージャで受ける。
    var currentTitle: () -> String = { "" }
    /// 画像メタデータの description に焼く端末情報（クリップ共有の mp4 description と同じ文字列）。
    var deviceDescription: String = ""

    /// これ以上は詰められない最小選択長（秒）。
    private let minimumDuration: Double = 1.0

    @State private var player = AVPlayer()
    @State private var duration: Double = 0
    @State private var thumbnails: [UIImage] = []
    @State private var playhead: Double = 0
    @State private var isPlaying = false
    /// 再生ヘッドをドラッグ中か。periodic observer の playhead 上書きを止め、指追従にする。
    @State private var isScrubbing = false
    /// 静止画の書き出し中か。二度押し抑止＋ボタンをスピナー表示にする。
    @State private var isCapturingStill = false
    /// キャプチャ時にプレビューを一瞬白く光らせる「撮った感」用の不透明度（0→0.85→0）。
    @State private var flashOpacity: Double = 0
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
                    .frame(maxHeight: previewMaxHeight)
                    .background(.black, in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        if duration == 0 {
                            ProgressView().tint(.white)
                        } else if !isPlaying {
                            // 一時停止中のポスター表示。タップ判定は映像エリア全体で受けるので非対話。
                            Image(systemName: "play.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(16)
                                .background(.black.opacity(0.35), in: Circle())
                                .allowsHitTesting(false)
                        }
                    }
                    // スクショ時の白フラッシュ（撮影合図）。映像形状にクリップ・非対話。
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white)
                            .opacity(flashOpacity)
                            .allowsHitTesting(false)
                    }
                    // 映像エリア全体をタップで再生/一時停止トグル（再生中タップで停止できる）。
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { if duration > 0 { togglePlay() } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("プレビュー")
                    .accessibilityValue(isPlaying ? "再生中" : "一時停止中")
                    .accessibilityHint("タップで再生 / 一時停止")
                    .accessibilityAction { if duration > 0 { togglePlay() } }
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
                onScrub: { seconds in seek(to: seconds) },
                onScrubBegan: { beginScrub() },
                onScrubEnded: { isScrubbing = false },
                // 再生ヘッドの真下に追従するカメラボタンから静止画キャプチャを起動する。
                onCapture: onCaptureStill != nil ? { captureStill() } : nil,
                isCapturing: isCapturingStill
            )
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
        if selection.lowerBound >= selection.upperBound {
            // 初回（未設定）: 選択を「中間点〜終端」にする（最低選択長は確保）。
            // 再生ヘッド／プレビュー／カメラボタンは**録画の最後尾（最新の画面）**へ置く。最新フレームが
            // そこなので「今の画面をそのままスクショ」がすぐできる。
            let start = max(0, min(seconds / 2, seconds - minimumDuration))
            selection = start...seconds
            seek(to: seconds)
        } else {
            // 再ロード（設定へ push して戻る等で .task が再実行）: 選択は維持。replaceCurrentItem で
            // 0 に戻った再生位置を直前のヘッド位置（選択範囲内へクランプ）へ復帰させる。これをしないと
            // periodic observer が playhead を 0 に同期し、カメラボタンだけ左端へ飛ぶ（選択は中央のまま）。
            seek(to: min(max(playhead, selection.lowerBound), selection.upperBound))
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

    // MARK: - 静止画キャプチャ

    /// 再生ヘッド位置の 1 フレームをフル解像度で抜き出し、PNG として一時ファイルに書いて共有へ渡す。
    ///
    /// `AVAssetImageGenerator` の許容誤差を 0 にして、再生ヘッドが当たっている厳密なコマを取る
    /// （サムネ生成は速度優先で誤差∞なのと対照的）。回転は `appliesPreferredTrackTransform` で正す。
    /// 元が圧縮済み動画フレームなので、再 JPEG 圧縮で文字が滲まないよう PNG で書き出す。
    private func captureStill() {
        guard duration > 0, !isCapturingStill else { return }
        // 再生中なら止めて、見えているコマと書き出すコマを一致させる。
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        playCaptureFeedback()   // 触覚＋プレビュー白フラッシュ（押した瞬間に「撮った感」を返す）
        isCapturingStill = true
        // 末尾ぴったり（duration）だと誤差0の generator がそのコマを取り損ねる（duration には表示中の
        // フレームが無い）ので、僅かに内側へ寄せる。最後尾既定でも最新フレームを確実に取れる。
        let seconds = min(max(playhead, 0), max(duration - 0.05, 0))
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let sourceURL = url
        let title = currentTitle()
        let description = deviceDescription
        // VideoTrimmerView は @MainActor なので、この Task も MainActor 隔離を継承する
        // （UIImage/CGImage を隔離跨ぎさせない＝既知の Sendable 罠を踏まない）。
        Task {
            defer { isCapturingStill = false }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: sourceURL))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            guard let cg = try? await generator.image(at: time).image else { return }
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(stillFileName(at: seconds, title: title))
            try? FileManager.default.removeItem(at: fileURL)   // 同名衝突を避ける
            guard writeTitledPNG(cg, title: title, description: description, to: fileURL) else { return }
            onCaptureStill?(fileURL)
        }
    }

    /// キャプチャの手応え。触覚（軽い衝撃）＋プレビューの白フラッシュ。
    /// フラッシュは一旦点灯を確定させてから次フレームで減衰させる（同一ループで 0.85→0 を書くと
    /// 中間の 0.85 が描画されず光らないため、減衰だけ非同期にずらす）。
    private func playCaptureFeedback() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        flashOpacity = 0.85
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.35)) { flashOpacity = 0 }
        }
    }

    /// 共有ファイル名。クリップ共有とタイトル挿入仕様を揃える：
    /// - タイトル有り: `<無害化タイトル>-<タイムコード>.png`（点なのでどのコマか分かるよう時刻を添える）
    /// - タイトル空: `flashback-screenshot-<日時>.png`（クリップの `flashback-video-...` と種別だけ違う）
    private func stillFileName(at seconds: Double, title: String) -> String {
        guard !title.isEmpty else { return "\(ClipTrimmer.fallbackName(kind: "screenshot")).png" }
        let total = Int(seconds.rounded())
        let stamp = String(format: "%dm%02ds", total / 60, total % 60)
        return "\(ClipTrimmer.sanitizedFileName(title))-\(stamp).png"
    }

    /// PNG を title / description 付きで書き出す。クリップの mp4 メタデータと役割を揃える：
    /// title=タイトル（有る時のみ）／description=端末情報（常時）。PNG の tEXt（iTXt/XMP）へ埋め込む。
    private func writeTitledPNG(_ cgImage: CGImage, title: String, description: String, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return false }
        var png: [CFString: Any] = [:]
        if !title.isEmpty { png[kCGImagePropertyPNGTitle] = title }
        if !description.isEmpty { png[kCGImagePropertyPNGDescription] = description }
        let properties: [CFString: Any] = png.isEmpty ? [:] : [kCGImagePropertyPNGDictionary: png]
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    /// 再生ヘッドのドラッグ開始（冪等）。再生中なら一時停止し、observer の上書きを止める。
    private func beginScrub() {
        guard !isScrubbing else { return }
        isScrubbing = true
        if isPlaying {
            player.pause()
            isPlaying = false
        }
    }

    private func addObserver() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.03, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            // periodic observer は @Sendable closure。MainActor 隔離の State へは Task で戻す。
            let seconds = CMTimeGetSeconds(time)
            Task { @MainActor in
                // スクラブ中は指追従を優先（observer は playhead を上書きしない）。
                guard !isScrubbing else { return }
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
    /// 再生ヘッドのドラッグ開始（冪等）／終了。スクラブ中の一時停止・observer 抑制を親に伝える。
    var onScrubBegan: () -> Void = {}
    var onScrubEnded: () -> Void = {}
    /// 再生ヘッド真下のカメラボタンのタップ＝静止画キャプチャ起動。`nil` なら追従トラックを出さない。
    var onCapture: (() -> Void)? = nil
    /// キャプチャ書き出し中。ボタンをスピナー表示にして二度押しを止める。
    var isCapturing: Bool = false

    /// カメラボタンに指が触れている間 true。押下中だけ少し膨らませて手応えを返す
    /// （指を離すと gesture 終了で自動的に false へ戻り、スプリングでポンと戻る）。
    @GestureState private var isPressingCapture = false

    private let handleWidth: CGFloat = 14
    /// ハンドルの透明ヒット域（見た目より広く取り、スクラブ面より確実に掴めるようにする）。
    private let handleHitWidth: CGFloat = 34
    private let stripHeight: CGFloat = 56
    /// キャプチャボタン（キャレット6＋丸34＝40）にぴったりの高さ。下の余白を抑える。
    private let captureTrackHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 4) {
            filmstripBar
                .frame(height: stripHeight)
            if onCapture != nil {
                captureTrack
            }
        }
    }

    /// サムネ＋両端ハンドル＋再生ヘッドの本体バー（高さ固定）。
    private var filmstripBar: some View {
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

                // 再生ヘッドの見た目（オレンジのクリップバーより**背面**・非対話。細い縦バー＋上部ノブ）。
                if duration > 0 {
                    playheadVisual(at: handleWidth + xOffset(for: playhead, usable: usable), height: height)
                }

                // 選択枠: 背景色の外輪（2pt）＋アクション色の枠（2.5pt）。
                RoundedRectangle(cornerRadius: 6)
                    .stroke(FlashbackColor.background, lineWidth: 6)
                    .frame(width: max(endX - startX, 0), height: height)
                    .offset(x: startX)
                RoundedRectangle(cornerRadius: 6)
                    .stroke(FlashbackColor.action, lineWidth: 2.5)
                    .frame(width: max(endX - startX, 0), height: height)
                    .offset(x: startX)

                // 再生ヘッドのグラブ（ヘッド上の小さめ領域）。**ハンドルより後ろ（下の z 順）**に置き、
                // クリップバー（トリム）を主役・最優先に。再生ヘッドはハンドルに重ならない所で次点で掴める。
                if duration > 0 {
                    playheadGrab(at: handleWidth + xOffset(for: playhead, usable: usable),
                                 height: height, usable: usable)
                }

                handle(at: startX, height: height, usable: usable, isStart: true)
                handle(at: endX, height: height, usable: usable, isStart: false)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .coordinateSpace(name: "strip")
        }
    }

    /// 再生ヘッドの真下に追従するカメラボタン（上向きキャレットで「この位置を撮る」を示す）。
    /// x マッピングはストリップと同一（全幅・同 `handleWidth`）なのでヘッド直下に揃う。
    /// 端ではボタンが見切れぬよう、ボタン中心を半径ぶんクランプする。
    private var captureTrack: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usable = max(width - handleWidth * 2, 1)
            let headX = handleWidth + xOffset(for: playhead, usable: usable)
            let radius: CGFloat = 17
            let cx = min(max(headX, radius), width - radius)
            CaptureHeadButton(isCapturing: isCapturing)
                .scaleEffect(isPressingCapture ? 1.14 : 1.0)   // 押下中は少し膨張（手応え）
                .animation(.spring(response: 0.26, dampingFraction: 0.55), value: isPressingCapture)
                .padding(.horizontal, 8)             // ドラッグしやすいよう左右の当たり判定を広げる
                .contentShape(Rectangle())
                .position(x: cx, y: 20)
                .gesture(captureGesture(usable: usable))
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("この瞬間を画像で保存")
                .accessibilityHint("再生ヘッドの位置の画面を画像として共有します。左右ドラッグで位置調整。")
                .accessibilityAction { onCapture?() }
        }
        .frame(height: captureTrackHeight)
        .coordinateSpace(name: "captureTrack")
        .disabled(duration == 0)
    }

    /// カメラボタンの操作。横ドラッグ＝再生位置の調整（スクラブ）、ほぼ動かさず離す＝タップ＝キャプチャ。
    /// 再生ヘッドのグラブ（`playheadGrab`）と同じ秒換算で、選択範囲内へクランプする。
    private func captureGesture(usable: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("captureTrack"))
            .updating($isPressingCapture) { _, pressing, _ in pressing = true }
            .onChanged { value in
                // 微小なブレはタップ判定に残すため、少し動いてからスクラブを始める。
                guard abs(value.translation.width) > 3 else { return }
                onScrubBegan()
                let seconds = secondsForX(value.location.x - handleWidth, usable: usable)
                onScrub(clampToSelection(seconds))
            }
            .onEnded { value in
                let isTap = abs(value.translation.width) <= 3 && abs(value.translation.height) <= 3
                onScrubEnded()
                if isTap { onCapture?() }
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
    /// 見た目は `handleWidth`、ヒット域は広め（`handleHitWidth`）にしてスクラブ面より確実に掴める。
    private func handle(at x: CGFloat, height: CGFloat, usable: CGFloat, isStart: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(FlashbackColor.action)
            .frame(width: handleWidth, height: height)
            .overlay(
                Capsule().fill(FlashbackColor.onAction).frame(width: 3, height: 18)
            )
            .frame(width: handleHitWidth, height: height)   // 透明な広いヒット域（見た目は中央の handleWidth）
            .contentShape(Rectangle())
            .offset(x: x - handleHitWidth / 2)
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

    /// 再生ヘッドの見た目（細い縦バーのみ）。非対話（グラブは別レイヤ）。
    private func playheadVisual(at x: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(FlashbackColor.label)
            .frame(width: 2, height: height)
            .offset(x: x)
            .allowsHitTesting(false)
    }

    /// 再生ヘッドのグラブ（ヘッド上の小さめ領域）。位置は選択範囲内へクランプして seek。
    /// ハンドル（広いヒット域・上の z 順）に重なる箇所ではトリムが優先される＝クリップバーが主役。
    /// グラブ幅はハンドルのヒット域より狭くして、重なり時はハンドルが確実に勝つようにする。
    private func playheadGrab(at x: CGFloat, height: CGFloat, usable: CGFloat) -> some View {
        let grabWidth: CGFloat = 26
        return Color.clear
            .frame(width: grabWidth, height: height)
            .contentShape(Rectangle())
            .offset(x: x - grabWidth / 2 + 1)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("strip"))
                    .onChanged { value in
                        onScrubBegan()
                        let seconds = secondsForX(value.location.x - handleWidth, usable: usable)
                        onScrub(clampToSelection(seconds))
                    }
                    .onEnded { _ in onScrubEnded() }
            )
            .accessibilityLabel("再生位置")
            .accessibilityValue(timeLabel(playhead))
            .accessibilityAdjustableAction { direction in
                let target = direction == .increment ? playhead + 1 : playhead - 1
                onScrubBegan()
                onScrub(clampToSelection(target))
                onScrubEnded()
            }
    }

    /// 選択範囲内へクランプ（トリム外へは出さない）。
    private func clampToSelection(_ seconds: Double) -> Double {
        min(max(seconds, selection.lowerBound), selection.upperBound)
    }

    private func timeLabel(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
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

/// 再生ヘッド直下に置くキャプチャボタンの見た目（上向きキャレット＋カメラ丸ボタン）。
/// アウトライン（背景色で塗り＋アクション色の枠）で、塗りの再生ボタンと役割を分ける。
/// 操作（タップ＝キャプチャ／横ドラッグ＝スクラブ）は親の `captureTrack` 側でまとめて扱う。
private struct CaptureHeadButton: View {
    let isCapturing: Bool

    var body: some View {
        VStack(spacing: 0) {
            CaretUp()
                .fill(FlashbackColor.action)
                .frame(width: 12, height: 6)
            ZStack {
                Circle()
                    .fill(FlashbackColor.background)
                    .overlay(Circle().stroke(FlashbackColor.action, lineWidth: 1.5))
                if isCapturing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(FlashbackColor.action)
                } else {
                    Image(systemName: "camera")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FlashbackColor.action)
                }
            }
            .frame(width: 34, height: 34)
        }
    }
}

/// 上向き三角（キャレット）。再生ヘッドの方向を指す目印。
private struct CaretUp: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
#endif
