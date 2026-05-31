#if canImport(UIKit)
import UIKit

/// 画面に常駐する小さなフローティングボタン（🐞）でレポート UI を起動するトリガ。
///
/// 実体のあるボタン（独立した小さな view）として overlay に載せるため、
/// `PassthroughWindow.hitTest` がボタン領域だけを拾い、それ以外はホストへ透過する。
/// 物理的な振りが使えない据え置き端末でも確実に発火する手段。
///
/// 操作性:
/// - **長押し**（既定 0.6 秒）で起動。袖や手が軽く触れた程度では誤爆しない。
/// - **ドラッグ**で位置を移動でき、離すと左右どちらか近い端へ吸着する。
/// - 普段は半透明で控えめ、触れている間だけ濃く表示。
/// - 初期位置は `FloatingButtonCorner` で四隅から指定可能。
@MainActor
final class FloatingButtonTrigger: TriggerDetecting {
    var onTrigger: (() -> Void)?

    private weak var host: UIViewController?
    private let corner: FloatingButtonCorner
    private var button: FloatingButtonView?

    init(host: UIViewController, corner: FloatingButtonCorner) {
        self.host = host
        self.corner = corner
    }

    func start() {
        guard button == nil, let hostView = host?.view else { return }

        let button = FloatingButtonView()
        button.onTrigger = { [weak self] in self?.onTrigger?() }
        hostView.addSubview(button)
        button.place(in: hostView, corner: corner)
        self.button = button
    }

    func stop() {
        button?.onTrigger = nil
        button?.removeFromSuperview()
        button = nil
        onTrigger = nil
    }
}

/// 半透明・ドラッグ可能・長押しで発火するフローティングボタン本体（純 UIKit）。
@MainActor
private final class FloatingButtonView: UIView {
    var onTrigger: (() -> Void)?

    private static let diameter: CGFloat = 56
    private static let edgeMargin: CGFloat = 16
    private static let peek: CGFloat = 22          // タック時に画面端へ残す幅
    private static let tuckThreshold: CGFloat = 24 // この距離以上端へ押し込むとタック
    private let idleAlpha: CGFloat = 0.5
    private let activeAlpha: CGFloat = 1.0

    private var dragStartCenter: CGPoint = .zero
    private var lastRawCenter: CGPoint = .zero
    private var isTucked = false
    private var tuckedAtMaxX = false

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        backgroundColor = .tintColor
        layer.cornerRadius = Self.diameter / 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        alpha = idleAlpha
        isAccessibilityElement = true
        accessibilityLabel = "Flashback レポート"
        accessibilityHint = "長押しでバグレポートを開く"

        let icon = UIImageView(image: UIImage(systemName: "ladybug.fill"))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
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
            setActive(true)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            popScale()
            onTrigger?()
        case .ended, .cancelled, .failed:
            setActive(false)
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
            setActive(true)
            dragStartCenter = center
            lastRawCenter = center
        case .changed:
            let t = recognizer.translation(in: parent)
            if isTucked {
                // 端から引き離す方向に大きく引いたら引き出す。
                let pullOut = tuckedAtMaxX ? -t.x : t.x
                if pullOut > 40 {
                    isTucked = false
                    accessibilityHint = "長押しでバグレポートを開く"
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
        accessibilityHint = "タップで表示"
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // 隠す側は跳ね返りが浅め（damping 高め）で「収まる」感じに。
        spring(to: CGPoint(x: targetX, y: center.y), velocity: velocity, damping: 0.78, alpha: idleAlpha)
    }

    /// タック状態から端のマージン位置へ引き出す。
    private func unTuck(in parent: UIView) {
        guard isTucked else { return }
        isTucked = false
        accessibilityHint = "長押しでバグレポートを開く"
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
#else
final class FloatingButtonTrigger: TriggerDetecting {
    var onTrigger: (() -> Void)?
    func start() {}
    func stop() {}
}
#endif
