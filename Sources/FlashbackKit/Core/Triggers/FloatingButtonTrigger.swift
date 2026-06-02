#if canImport(UIKit)
import UIKit

/// 画面に常駐する小さなフローティングボタン（Time Slice マーク）でレポート UI を起動するトリガ。
///
/// 実体のあるボタン（独立した小さな view）として overlay に載せるため、
/// `PassthroughWindow.hitTest` がボタン領域だけを拾い、それ以外はホストへ透過する。
/// 物理的な振りが使えない据え置き端末でも確実に発火する手段。
///
/// 操作性:
/// - **長押し**（0.5 秒）で起動。押下中はマーク外周にプログレスリングが溜まる。
///   袖や手が軽く触れた程度では誤爆しない。
/// - **ドラッグ**で位置を移動でき、離すと左右どちらか近い端へ吸着 / タックする。
/// - 普段は半透明で控えめ、触れている間だけ濃く表示。
/// - 初期位置は `FloatingButtonCorner` で四隅から指定可能。
///
/// 見た目（README の「オレンジ＝録画中・グレー＝非録画」）:
/// - 録画中: オレンジ円・白リング・白@0.5 くさび。
/// - 長押し中: 上に加えてプログレスリング。
/// - 端タック中: グレー・オレンジ@1.0 くさび（録画は継続）。
/// - 休止（録画オフ）: グレー・白@0.6 くさび。
@MainActor
final class FloatingButtonTrigger: TriggerDetecting {
    var onTrigger: (() -> Void)?
    /// 長押し開始時（ゲージが溜まり始めた時点）。進行中トーストを早出しするため。
    var onPressStart: (() -> Void)?
    /// 長押しが発火せず中断した時（早離し / ドラッグ転化 / 取消）。早出しトーストを消すため。
    var onPressCancel: (() -> Void)?

    private weak var host: UIViewController?
    private let corner: FloatingButtonCorner
    private let recordingEnabled: Bool
    private var button: FloatingButtonView?

    init(host: UIViewController, corner: FloatingButtonCorner, recordingEnabled: Bool = true) {
        self.host = host
        self.corner = corner
        self.recordingEnabled = recordingEnabled
    }

    func start() {
        guard button == nil, let hostView = host?.view else { return }

        let button = FloatingButtonView(recordingEnabled: recordingEnabled)
        button.onTrigger = { [weak self] in self?.onTrigger?() }
        button.onPressStart = { [weak self] in self?.onPressStart?() }
        button.onPressCancel = { [weak self] in self?.onPressCancel?() }
        hostView.addSubview(button)
        button.place(in: hostView, corner: corner)
        self.button = button
    }

    /// 録画オン/オフ（休止）を切り替える。Settings / 権限状態の反映用。
    func setRecordingEnabled(_ enabled: Bool) {
        button?.recordingEnabled = enabled
    }

    func stop() {
        button?.onTrigger = nil
        button?.onPressStart = nil
        button?.onPressCancel = nil
        button?.removeFromSuperview()
        button = nil
        onTrigger = nil
        onPressStart = nil
        onPressCancel = nil
    }
}

/// 半透明・ドラッグ可能・長押しで発火するフローティングボタン本体（純 UIKit）。
/// グリフは Time Slice マーク（リング＋くさび＋ハブ）を CAShapeLayer で描く。
@MainActor
private final class FloatingButtonView: UIView {
    var onTrigger: (() -> Void)?
    /// 長押し開始（ゲージ充填の開始）。/ 中断（未発火で終了）。
    var onPressStart: (() -> Void)?
    var onPressCancel: (() -> Void)?
    /// この押下で発火済みか。touchesEnded での誤キャンセル（トースト消し）を防ぐ。
    private var didFire = false
    /// 進行中トーストの早出しを少し遅らせる予約（ドラッグ移動だけの時の一瞬表示を防ぐ）。
    private var pressStartWork: DispatchWorkItem?
    private static let toastDelay: CFTimeInterval = 0.18

    /// 録画オン（オレンジ）/ オフ（グレー休止）。変更で見た目を更新する。
    var recordingEnabled: Bool {
        didSet { applyAppearance() }
    }

    private static let diameter: CGFloat = 56
    private static let markDiameter: CGFloat = 36  // ボタン内のマーク径（ratio ≈ 0.64）
    private static let edgeMargin: CGFloat = 16
    private static let peek: CGFloat = 22          // タック時に画面端へ残す幅
    private static let tuckThreshold: CGFloat = 24 // この距離以上端へ押し込むとタック
    private static let pressDuration: CFTimeInterval = 0.5   // 操作感優先で 0.35→0.5（誤爆しにくく）
    private static let pressScale: CGFloat = 1.06            // 長押しゲージ満了時の微増スケール
    private let idleAlpha: CGFloat = 0.5   // 待機時の opacity（タック中も同じ）
    private let activeAlpha: CGFloat = 1.0

    private static let action = FlashbackColor.actionUIColor
    private static let slate = FlashbackColor.slateUIColor

    private let ringLayer = CAShapeLayer()
    private let wedgeLayer = CAShapeLayer()
    private let hubLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()

    private var dragStartCenter: CGPoint = .zero
    private var lastRawCenter: CGPoint = .zero
    private var isTucked = false
    private var tuckedAtMaxX = false

    init(recordingEnabled: Bool = true) {
        self.recordingEnabled = recordingEnabled
        super.init(frame: CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        layer.cornerRadius = Self.diameter / 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22                 // README: 0 4px 12px rgba(0,0,0,0.22)
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 4)
        alpha = idleAlpha
        isAccessibilityElement = true
        accessibilityLabel = "Flashback を起動"
        accessibilityHint = "長押しで起動"

        setUpMarkLayers()
        applyAppearance()

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = Self.pressDuration
        longPress.cancelsTouchesInView = false
        addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)

        // タック（端へ隠した）状態からの復帰用。通常時のタップは無視（誤発火防止）。
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Time Slice マーク描画

    private func setUpMarkLayers() {
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.strokeColor = UIColor.white.cgColor
        ringLayer.lineCap = .round
        hubLayer.fillColor = UIColor.white.cgColor
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        progressLayer.isHidden = true
        // 順序: リング → くさび → ハブ → プログレス。
        layer.addSublayer(ringLayer)
        layer.addSublayer(wedgeLayer)
        layer.addSublayer(hubLayer)
        layer.addSublayer(progressLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let k = Self.markDiameter / 64                 // viewBox 64 からのスケール
        let radius = 20 * k
        ringLayer.lineWidth = 3.2 * k
        ringLayer.path = UIBezierPath(arcCenter: center, radius: radius,
                                      startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath

        // くさび: 12 時から反時計回り 66°（左斜め上・巻き戻し方向）。点サンプリングで向きを確定。
        let wedge = UIBezierPath()
        wedge.move(to: center)
        let steps = 48
        for i in 0...steps {
            let clock = -(66 * Double(i) / Double(steps)) * .pi / 180
            wedge.addLine(to: CGPoint(x: center.x + radius * CGFloat(sin(clock)),
                                      y: center.y - radius * CGFloat(cos(clock))))
        }
        wedge.close()
        wedgeLayer.path = wedge.cgPath

        let hubRadius = 2.6 * k
        hubLayer.path = UIBezierPath(arcCenter: center, radius: hubRadius,
                                     startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath

        // プログレスリング: ボタン外周のやや内側を 12 時から**反時計回り**に充填（時間を巻き戻す意味）。
        let progressRadius = bounds.width / 2 - 2
        progressLayer.lineWidth = 3
        progressLayer.path = UIBezierPath(arcCenter: center, radius: progressRadius,
                                          startAngle: -.pi / 2, endAngle: -.pi / 2 - 2 * .pi,
                                          clockwise: false).cgPath
    }

    /// 状態（録画中 / 休止 / タック）に応じて背景色・くさび色を反映する。
    private func applyAppearance() {
        backgroundColor = (recordingEnabled && !isTucked) ? Self.action : Self.slate
        let wedgeColor: UIColor
        if isTucked {
            wedgeColor = Self.action                       // タック中: オレンジくさび。
        } else if recordingEnabled {
            wedgeColor = UIColor.white.withAlphaComponent(0.5)   // 録画中。
        } else {
            wedgeColor = UIColor.white.withAlphaComponent(0.6)   // 休止。
        }
        wedgeLayer.fillColor = wedgeColor.cgColor
    }

    // MARK: - 長押しプログレス（ゲージ＋opacity＋微増スケール）

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        didFire = false
        // タック中のタッチは引き出し用。プログレスは出さない。
        guard !isTucked else { return }
        beginPressRamp()
        // 進行中トーストは少し遅らせて出す（ドラッグ移動だけの時は出る前に取消）。
        schedulePressStart()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        clearPress(restoreActive: false)
        cancelPressStart()
        if !didFire { onPressCancel?() }       // 未発火で離した＝早出しトーストを消す。
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        clearPress(restoreActive: false)
        cancelPressStart()
        if !didFire { onPressCancel?() }
    }

    /// 押下が `toastDelay` 続いたら進行中トーストを出す（ドラッグ転化はその前に取消）。
    private func schedulePressStart() {
        pressStartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onPressStart?() }
        pressStartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.toastDelay, execute: work)
    }

    private func cancelPressStart() {
        pressStartWork?.cancel()
        pressStartWork = nil
    }

    /// 押下開始: ゲージ充填と同期して opacity（待機→不透明）と微増スケール（→`pressScale`）を
    /// `pressDuration` かけてランプさせる。3 つが同時に満了＝発火タイミングで頂点になる。
    private func beginPressRamp() {
        progressLayer.isHidden = false
        layer.removeAnimation(forKey: "opacity")

        if UIAccessibility.isReduceMotionEnabled {
            // 低モーション: アニメせず即時に満ちた状態・フル不透明。
            progressLayer.strokeEnd = 1
            alpha = activeAlpha
            return
        }

        // ゲージ（外周リング）を pressDuration で線形充填。
        progressLayer.strokeEnd = 1
        let fill = CABasicAnimation(keyPath: "strokeEnd")
        fill.fromValue = 0
        fill.toValue = 1
        fill.duration = Self.pressDuration
        fill.timingFunction = CAMediaTimingFunction(name: .linear)
        progressLayer.add(fill, forKey: "press")

        // opacity と微増スケールをゲージに同期（線形・満了で頂点）。
        UIView.animate(withDuration: Self.pressDuration, delay: 0,
                       options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]) {
            self.alpha = self.activeAlpha
            self.transform = CGAffineTransform(scaleX: Self.pressScale, y: Self.pressScale)
        }
    }

    /// 発火時: ゲージを消す。opacity/スケールは満了済みのまま `popScale` が引き継ぐ。
    private func endPressGauge() {
        progressLayer.removeAnimation(forKey: "press")
        progressLayer.isHidden = true
        progressLayer.strokeEnd = 0
    }

    /// 押下中断（早離し / 取消 / ドラッグ転化）: ゲージを消し、opacity とスケールを素早く戻す。
    /// - Parameter restoreActive: ドラッグ転化時は active（不透明）へ、それ以外は待機 alpha へ。
    private func clearPress(restoreActive: Bool) {
        endPressGauge()
        UIView.animate(withDuration: 0.18, delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.alpha = restoreActive ? self.activeAlpha : self.idleAlpha
            self.transform = .identity
        }
    }

    /// 指定の隅へ初期配置する。
    func place(in container: UIView, corner: FloatingButtonCorner) {
        let bounds = container.bounds
        let inset = container.safeAreaInsets
        let half = Self.diameter / 2
        let minX = inset.left + Self.edgeMargin + half
        let maxX = bounds.width - inset.right - Self.edgeMargin - half
        let minY = inset.top + Self.edgeMargin + half
        let maxY = bounds.height - inset.bottom - Self.edgeMargin - half
        switch corner {
        case .topLeading:     center = CGPoint(x: minX, y: minY)
        case .topTrailing:    center = CGPoint(x: maxX, y: minY)
        case .bottomLeading:  center = CGPoint(x: minX, y: maxY)
        case .bottomTrailing: center = CGPoint(x: maxX, y: maxY)
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            // タック中なら発火せず引き出すだけ。
            if isTucked {
                if let parent = superview { unTuck(in: parent) }
                return
            }
            didFire = true                     // 発火確定。touchesEnded でキャンセル扱いしない。
            endPressGauge()                    // 満了＝発火。ゲージは満ちて消す（opacity/scale は維持）。
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            popScale()                         // ランプの微増スケールから発火ポップへ繋ぐ。
            onTrigger?()
        case .ended, .cancelled, .failed:
            break                              // alpha/scale の後始末は touchesEnded/Cancelled が担う。
        default:
            break
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        // タック中のタップは引き出す。通常時のタップは無視（長押しのみ発火）。
        guard isTucked, let parent = superview else { return }
        unTuck(in: parent)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let parent = superview else { return }
        switch recognizer.state {
        case .began:
            // ドラッグ＝長押しではない。ゲージ/スケールを畳み、不透明（active）に戻す。
            clearPress(restoreActive: true)
            cancelPressStart()                  // 出る前のトースト予約を取消（ドラッグ移動だけの時）。
            if !didFire { onPressCancel?() }    // 既に出ていれば消す。
            dragStartCenter = center
            lastRawCenter = center
        case .changed:
            let t = recognizer.translation(in: parent)
            if isTucked {
                // 端から引き離す方向に大きく引いたら引き出す。
                let pullOut = tuckedAtMaxX ? -t.x : t.x
                if pullOut > 40 {
                    isTucked = false
                    applyAppearance()
                    accessibilityHint = "長押しで起動"
                    // 現在地（端の外）を起点に通常ドラッグへ滑らかに引き継ぐ。
                    dragStartCenter = center
                    lastRawCenter = center
                    recognizer.setTranslation(.zero, in: parent)
                    return
                }
                // タックのまま上下移動（x はタック位置に固定、y のみ追従）。
                center = CGPoint(x: center.x, y: clampY(dragStartCenter.y + t.y, in: parent))
                return
            }
            lastRawCenter = CGPoint(x: dragStartCenter.x + t.x, y: dragStartCenter.y + t.y)
            center = dragClampedCenter(lastRawCenter, in: parent)
        case .ended, .cancelled:
            // タックのまま上下移動して離した場合はその位置に留まる。
            if isTucked { setActive(false); return }
            finishDrag(in: parent, velocity: recognizer.velocity(in: parent).x)
            setActive(false)
        default:
            break
        }
    }

    /// ドラッグ終了時、**離した座標**で判定する。端の定位置より内側で離せば吸着、
    /// 端寄り（しきい値より外）で離せばタック。強いフリックでもその端へタックする。
    /// フリックの速度を spring の初速に渡して、勢いに連動した跳ね感を出す。
    private func finishDrag(in parent: UIView, velocity: CGFloat) {
        let leftRest = restMarginX(in: parent, maxEdge: false)
        let rightRest = restMarginX(in: parent, maxEdge: true)
        let flick: CGFloat = 1500   // pt/s。これ以上の勢いで弾いたら端へ投げてタック。
        if center.x < leftRest - Self.tuckThreshold || velocity < -flick {
            tuck(toMaxEdge: false, in: parent, velocity: velocity)
        } else if center.x > rightRest + Self.tuckThreshold || velocity > flick {
            tuck(toMaxEdge: true, in: parent, velocity: velocity)
        } else {
            snapToNearestEdge(in: parent, velocity: velocity)
        }
    }

    /// 画面端へスッと隠し、`peek` 幅だけ残す（YouTube ミニプレーヤー風）。
    private func tuck(toMaxEdge: Bool, in parent: UIView, velocity: CGFloat = 0) {
        let half = Self.diameter / 2
        let targetX = toMaxEdge
            ? parent.bounds.width + half - Self.peek
            : -half + Self.peek
        isTucked = true
        tuckedAtMaxX = toMaxEdge
        applyAppearance()                       // グレー＋オレンジくさびへ。
        accessibilityHint = "タップで表示"
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // 隠す側は跳ね返りが浅め（damping 高め）で「収まる」感じに。
        spring(to: CGPoint(x: targetX, y: center.y), velocity: velocity, damping: 0.78, alpha: idleAlpha)
    }

    /// タック状態から端のマージン位置へ引き出す。
    private func unTuck(in parent: UIView) {
        guard isTucked else { return }
        isTucked = false
        applyAppearance()
        accessibilityHint = "長押しで起動"
        let target = clampedCenter(CGPoint(x: tuckedAtMaxX ? .greatestFiniteMagnitude : -.greatestFiniteMagnitude,
                                           y: center.y), in: parent)
        // 引き出しは弾みを強めに（damping 低め）でポンッと出す。
        spring(to: target, velocity: 0, damping: 0.55, alpha: activeAlpha) { [weak self] in
            self?.setActive(false)
        }
    }

    /// 中心座標へ spring（跳ね）アニメーションで移動する共通処理。
    /// - Parameters:
    ///   - velocity: フリック速度（pt/s）。移動距離で正規化して spring 初速に渡す。
    ///   - damping: 0 に近いほどよく跳ね、1 に近いほど跳ねずに収まる。
    private func spring(to target: CGPoint,
                        velocity: CGFloat = 0,
                        damping: CGFloat = 0.55,
                        alpha: CGFloat? = nil,
                        completion: (() -> Void)? = nil) {
        let distance = abs(target.x - center.x)
        let initialVelocity = distance > 1 ? min(abs(velocity) / distance, 12) : 0
        UIView.animate(withDuration: 0.55, delay: 0,
                       usingSpringWithDamping: damping,
                       initialSpringVelocity: initialVelocity,
                       options: [.allowUserInteraction, .curveEaseOut]) {
            self.center = target
            if let alpha { self.alpha = alpha }
        } completion: { _ in completion?() }
    }

    /// ボタンが safe area 内に収まるよう中心座標を丸める。
    private func clampedCenter(_ point: CGPoint, in parent: UIView) -> CGPoint {
        let inset = parent.safeAreaInsets
        let half = Self.diameter / 2
        let minX = inset.left + Self.edgeMargin + half
        let maxX = parent.bounds.width - inset.right - Self.edgeMargin - half
        let minY = inset.top + Self.edgeMargin + half
        let maxY = parent.bounds.height - inset.bottom - Self.edgeMargin - half
        return CGPoint(x: min(max(point.x, minX), maxX), y: min(max(point.y, minY), maxY))
    }

    /// y 座標だけ safe area 内に丸める（タック中の上下移動用）。
    private func clampY(_ y: CGFloat, in parent: UIView) -> CGFloat {
        let half = Self.diameter / 2
        let minY = parent.safeAreaInsets.top + Self.edgeMargin + half
        let maxY = parent.bounds.height - parent.safeAreaInsets.bottom - Self.edgeMargin - half
        return min(max(y, minY), maxY)
    }

    /// 左右いずれかの定位置（吸着位置）の x 座標。
    private func restMarginX(in parent: UIView, maxEdge: Bool) -> CGFloat {
        let half = Self.diameter / 2
        return maxEdge
            ? parent.bounds.width - parent.safeAreaInsets.right - Self.edgeMargin - half
            : parent.safeAreaInsets.left + Self.edgeMargin + half
    }

    /// ドラッグ中のクランプ。x は端の壁を作らず、タック位置（画面端の外）まで指追従させる。
    /// 端で止まらないので「壁に当たる」違和感が出ない。y は safe area 内。
    private func dragClampedCenter(_ point: CGPoint, in parent: UIView) -> CGPoint {
        let half = Self.diameter / 2
        let xMin = -half + Self.peek
        let xMax = parent.bounds.width + half - Self.peek
        return CGPoint(x: min(max(point.x, xMin), xMax), y: clampY(point.y, in: parent))
    }

    /// 左右の近い端へ吸着させる（フリック速度に連動した跳ね感つき）。
    private func snapToNearestEdge(in parent: UIView, velocity: CGFloat = 0) {
        let inset = parent.safeAreaInsets
        let half = Self.diameter / 2
        let minX = inset.left + Self.edgeMargin + half
        let maxX = parent.bounds.width - inset.right - Self.edgeMargin - half
        let targetX = (center.x - minX) < (maxX - center.x) ? minX : maxX
        spring(to: CGPoint(x: targetX, y: center.y), velocity: velocity, damping: 0.6)
    }

    private func setActive(_ active: Bool) {
        UIView.animate(withDuration: 0.15) {
            self.alpha = active ? self.activeAlpha : self.idleAlpha
        }
    }

    /// 発火時に一瞬ふくらんで弾むスケール。タップ感のフィードバック。
    private func popScale() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut]) {
            self.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        } completion: { _ in
            UIView.animate(withDuration: 0.45, delay: 0,
                           usingSpringWithDamping: 0.45, initialSpringVelocity: 6,
                           options: [.allowUserInteraction]) {
                self.transform = .identity
            }
        }
    }
}

#if DEBUG && canImport(SwiftUI)
import SwiftUI

extension FloatingButtonView {
    /// プレビュー専用: 状態を直接セットする（タック / 長押しプログレス）。
    func previewConfigure(tucked: Bool, pressProgress: CGFloat?) {
        isTucked = tucked
        applyAppearance()
        alpha = tucked ? idleAlpha : activeAlpha
        if let pressProgress {
            progressLayer.isHidden = false
            progressLayer.strokeEnd = pressProgress
        }
    }
}

/// FAB の4状態を Xcode プレビューで確認するためのラッパ。
private struct FABStatePreview: UIViewRepresentable {
    var recording: Bool
    var tucked: Bool = false
    var pressProgress: CGFloat? = nil

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let fab = FloatingButtonView(recordingEnabled: recording)
        fab.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(fab)
        NSLayoutConstraint.activate([
            fab.widthAnchor.constraint(equalToConstant: 56),
            fab.heightAnchor.constraint(equalToConstant: 56),
            fab.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            fab.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        fab.previewConfigure(tucked: tucked, pressProgress: pressProgress)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

#Preview("FAB 4状態") {
    HStack(spacing: 20) {
        FABStatePreview(recording: true)                          // 録画中
        FABStatePreview(recording: true, pressProgress: 0.65)     // 長押し中
        FABStatePreview(recording: true, tucked: true)            // 端タック
        FABStatePreview(recording: false)                         // 休止
    }
    .frame(height: 90)
    .padding(40)
}
#endif
#else
final class FloatingButtonTrigger: TriggerDetecting {
    var onTrigger: (() -> Void)?
    func start() {}
    func stop() {}
}
#endif
