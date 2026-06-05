#if canImport(UIKit)
import UIKit

/// 画面に常駐する小さなフローティングボタン（Time Slice マーク）でレポート UI を起動するトリガ。
///
/// 実体のあるボタン（独立した小さな view）として overlay に載せるため、
/// `PassthroughWindow.hitTest` がボタン領域だけを拾い、それ以外はホストへ透過する。
/// 物理的な振りが使えない据え置き端末でも確実に発火する手段。
///
/// 操作性（録画状態で役割が変わる）:
/// - 録画オフ（グレー＝寝てる）: **シングルタップで録画オン**（起こす）。初見でも自然に
///   当たる導線にするため、寝てる状態は長押しを要求しない。
/// - 録画オン（オレンジ＝起きてる）: **長押し**（0.4 秒）でレポート起動。押下中はマーク外周に
///   プログレスリングが溜まり、袖や手が軽く触れた程度では誤爆しない。短くタップした時は
///   無反応で終わらせず「長押しでレポート起動」のヒントを出す。
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
    /// 録画オフ（グレー）状態でのシングルタップ。録画をオン（起こす）にするため。
    var onWake: (() -> Void)?
    /// 録画オン（オレンジ）状態での短いタップ。無反応で終わらせず長押しを促すヒント用。
    var onShortTapHint: (() -> Void)?

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
        button.onWake = { [weak self] in self?.onWake?() }
        button.onShortTapHint = { [weak self] in self?.onShortTapHint?() }
        hostView.addSubview(button)
        button.placeAvoidingTabBar(in: hostView, corner: corner)
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
        button?.onWake = nil
        button?.onShortTapHint = nil
        button?.removeFromSuperview()
        button = nil
        onTrigger = nil
        onPressStart = nil
        onPressCancel = nil
        onWake = nil
        onShortTapHint = nil
    }
}

/// FAB の最後の位置（端＋縦の割合＋タック状態）を端末に永続化するストア。
/// 絶対座標ではなく「左右どちらの端か」＋「縦位置の割合」で持つので、safe area やタブバー差・
/// 別端末でも破綻しない。タック（端に半分隠した）状態も保持し、次回も同じ見た目で復元する。
private enum FABPositionStore {
    static let edgeKey = "FlashbackKit.fabEdgeIsTrailing"
    static let yKey = "FlashbackKit.fabYFraction"
    static let tuckedKey = "FlashbackKit.fabTucked"

    static func save(edgeIsTrailing: Bool, yFraction: Double, tucked: Bool) {
        let d = UserDefaults.standard
        d.set(edgeIsTrailing, forKey: edgeKey)
        d.set(yFraction, forKey: yKey)
        d.set(tucked, forKey: tuckedKey)
    }

    static func load() -> (edgeIsTrailing: Bool, yFraction: Double, tucked: Bool)? {
        let d = UserDefaults.standard
        guard d.object(forKey: yKey) != nil else { return nil }   // 未保存なら nil（既定コーナーを使う）
        return (d.bool(forKey: edgeKey), d.double(forKey: yKey), d.bool(forKey: tuckedKey))
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
    /// 録画オフ（グレー）でのシングルタップ＝録画オン。/ 録画オン（オレンジ）での短タップ＝ヒント。
    var onWake: (() -> Void)?
    var onShortTapHint: (() -> Void)?
    /// この押下で発火済みか。touchesEnded での誤キャンセル（トースト消し）を防ぐ。
    private var didFire = false
    /// 進行中トーストの早出しを少し遅らせる予約（ドラッグ移動だけの時の一瞬表示を防ぐ）。
    private var pressStartWork: DispatchWorkItem?
    private static let toastDelay: CFTimeInterval = 0.18

    /// 録画オン（オレンジ）/ オフ（グレー休止）。変更で見た目を更新する。
    /// 実際に状態が変わり画面に載っている時だけ、タイムスライスが満ちる/畳む演出を再生する
    /// （色クロスフェード＋くさび 0°⇄66°＋ポップ＋触覚）。それ以外（初期化・refresh）は即時スナップ。
    var recordingEnabled: Bool {
        didSet {
            if recordingEnabled != oldValue, window != nil {
                animateRecordingTransition(to: recordingEnabled)
            } else {
                applyAppearance()
            }
        }
    }

    private static let diameter: CGFloat = 56
    private static let markDiameter: CGFloat = 36  // ボタン内のマーク径（ratio ≈ 0.64）
    private static let edgeMargin: CGFloat = 16
    private static let peek: CGFloat = 22          // タック時に画面端へ残す幅
    private static let tuckThreshold: CGFloat = 24 // この距離以上端へ押し込むとタック
    private static let pressDuration: CFTimeInterval = 0.4   // 0.35→0.5（誤爆しにくく）→0.4（やや短く・操作感優先）
    private static let pressScale: CGFloat = 1.14            // 長押しゲージ満了時の膨張（手応え強化で 1.06→1.14）
    private let idleAlpha: CGFloat = 0.5   // 待機時の opacity（タック中も同じ）
    private let activeAlpha: CGFloat = 1.0

    private static let action = FlashbackColor.actionUIColor
    private static let slate = FlashbackColor.slateUIColor

    private let ringLayer = CAShapeLayer()
    private let wedgeLayer = CAShapeLayer()
    private let handLayer = CAShapeLayer()
    private let hubLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()

    private var dragStartCenter: CGPoint = .zero
    private var lastRawCenter: CGPoint = .zero
    private var isTucked = false
    private var tuckedAtMaxX = false
    /// ホストのタブバーに被らないよう下端へ加算するインセット。**配置時に一度だけ**判定して保持する
    /// （動的追従はしない）。タブバーが無ければ 0。以後のクランプ（ドラッグ下限）にも一貫して使う。
    private var extraBottomInset: CGFloat = 0
    /// ユーザーが一度でも触れたか。表示直後のタブバー再判定（再配置）を中断する条件に使う。
    private var hasUserInteracted = false

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

        setUpMarkLayers()
        applyAppearance()                          // accessibilityHint も状態に応じてここで設定する。

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
        handLayer.fillColor = UIColor.clear.cgColor
        handLayer.strokeColor = UIColor.white.cgColor       // 針はリング/ハブと同色（FAB は白）
        handLayer.lineCap = .round
        hubLayer.fillColor = UIColor.white.cgColor
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        progressLayer.isHidden = true
        // 順序: リング → くさび → 針 → ハブ → プログレス。
        layer.addSublayer(ringLayer)
        layer.addSublayer(wedgeLayer)
        layer.addSublayer(handLayer)
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

        // くさび（タイムスライス）。録画状態に応じた充填率で描く（オフ=0°＝畳んで非表示／オン=66°）。
        // 状態遷移は setWedgeSweep(animated:) でアニメするので、ここは現状態へスナップのみ。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wedgeLayer.path = wedgePath(sweep: recordingEnabled ? 1 : 0)
        CATransaction.commit()

        // 針: 中心→12時方向（r=18・リング内側 2 手前）。丸キャップ。
        let hand = UIBezierPath()
        hand.move(to: center)
        hand.addLine(to: CGPoint(x: center.x, y: center.y - 18 * k))
        handLayer.lineWidth = 3.2 * k
        handLayer.path = hand.cgPath

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

    /// 背景色・くさびを**録画状態だけ**で決める（タックは色に影響しない）。アニメ無しの即時スナップ。
    /// 色ルール「録画中＝オレンジ／停止中＝グレー」。停止中はタイムスライス（くさび）を畳んで非表示にし、
    /// 「録っていない＝スライスが無い」を形でも示す。タック中の見分けは形状（ハーフピル）と alpha が担う。
    private func applyAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundColor = recordingEnabled ? Self.action : Self.slate
        wedgeLayer.fillColor = UIColor.white.withAlphaComponent(0.5).cgColor
        wedgeLayer.path = wedgePath(sweep: recordingEnabled ? 1 : 0)
        CATransaction.commit()
        if !isTucked {
            accessibilityHint = recordingEnabled ? "長押しでレポートを起動" : "タップで録画を開始"
        }
    }

    /// 録画 on/off の遷移演出（案: タイムスライスが満ちる）。色クロスフェード＋くさび 0°⇄66° の
    /// スイープ＋スプリングのポップ＋触覚（on=しっかり / off=やわらか）。
    private func animateRecordingTransition(to on: Bool) {
        UIImpactFeedbackGenerator(style: on ? .medium : .soft).impactOccurred()
        wedgeLayer.fillColor = UIColor.white.withAlphaComponent(0.5).cgColor
        UIView.animate(withDuration: 0.3, delay: 0, options: [.allowUserInteraction, .curveEaseInOut]) {
            self.backgroundColor = on ? Self.action : Self.slate
        }
        setWedgeSweep(on ? 1 : 0, animated: true)
        if !UIAccessibility.isReduceMotionEnabled {
            popToggle()
            if on { emitPingRing(color: Self.action) }   // 録画アーム＝外向きの波紋ピング（オン時だけ）
        }
        if !isTucked {
            accessibilityHint = on ? "長押しでレポートを起動" : "タップで録画を開始"
        }
    }

    /// 録画オン時に、ボタン外周から波紋リングを一発広げてフェードアウトさせる（レーダーピング）。
    /// ボタンの円形クリップに切られないよう、親ビューの **FAB 背後** に一時レイヤを置き、完了後に除去する。
    private func emitPingRing(color: UIColor) {
        guard let host = superview else { return }
        let side = Self.diameter
        let ring = CAShapeLayer()
        ring.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        ring.position = center                         // 親座標での FAB 中心
        ring.path = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: side - 2, height: side - 2)).cgPath
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = color.withAlphaComponent(0.65).cgColor
        ring.lineWidth = 2.5
        ring.opacity = 0                               // 最終状態（アニメで 0.7→0）
        host.layer.insertSublayer(ring, below: layer)  // FAB の背後から湧き出す

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 2.3
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.7
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.6
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "ping")
        CATransaction.commit()
    }

    /// くさび（タイムスライス）の充填率（0=畳む / 1=66°満タン）を設定する。
    /// `animated` 時は path を補間（満ちる=easeOut / 畳む=easeIn）。点数が同じなので滑らかに補間できる。
    private func setWedgeSweep(_ sweep: CGFloat, animated: Bool) {
        let to = wedgePath(sweep: sweep)
        if animated {
            let from = wedgeLayer.presentation()?.path ?? wedgeLayer.path
            let anim = CABasicAnimation(keyPath: "path")
            anim.fromValue = from
            anim.toValue = to
            anim.duration = 0.38
            anim.timingFunction = CAMediaTimingFunction(name: sweep > 0 ? .easeOut : .easeIn)
            wedgeLayer.path = to
            wedgeLayer.add(anim, forKey: "wedgeSweep")
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            wedgeLayer.path = to
            CATransaction.commit()
        }
    }

    /// 12 時から反時計回りに `sweep × 66°` 充填したくさび。点数固定（補間用）・sweep=0 は退化＝不可視。
    private func wedgePath(sweep: CGFloat) -> CGPath {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = 20 * (Self.markDiameter / 64)
        let maxDeg = 66.0 * Double(max(0, min(sweep, 1)))
        let steps = 48
        let path = UIBezierPath()
        path.move(to: center)
        for i in 0...steps {
            let clock = -(maxDeg * Double(i) / Double(steps)) * .pi / 180
            path.addLine(to: CGPoint(x: center.x + radius * CGFloat(sin(clock)),
                                     y: center.y - radius * CGFloat(cos(clock))))
        }
        path.close()
        return path.cgPath
    }

    /// トグル時の弾み（少し膨らんで戻る）。発火ポップ(1.25)とは別の控えめなスケール。
    private func popToggle() {
        UIView.animate(withDuration: 0.16, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0,
                       options: [.allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
        } completion: { _ in
            UIView.animate(withDuration: 0.34, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 6,
                           options: [.allowUserInteraction]) {
                self.transform = .identity
            }
        }
    }

    // MARK: - 長押しプログレス（ゲージ＋opacity＋微増スケール）

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        hasUserInteracted = true               // 以後はタブバー再判定で勝手に動かさない。
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
    /// 配置するこの瞬間にホストのタブバー有無を一度だけ判定し、あれば下端を上げる。
    func place(in container: UIView, corner: FloatingButtonCorner) {
        extraBottomInset = Self.hostTabBarInset(in: container)   // 表示時の一回判定（動的追従なし）
        let bounds = container.bounds
        let inset = container.safeAreaInsets
        let half = Self.diameter / 2
        let minX = inset.left + Self.edgeMargin + half
        let maxX = bounds.width - inset.right - Self.edgeMargin - half
        let minY = inset.top + Self.edgeMargin + half
        let maxY = bounds.height - inset.bottom - extraBottomInset - Self.edgeMargin - half

        // 保存済みの位置（端＋高さ＋タック）があれば復元する。
        // 高さはクランプ範囲 [minY, maxY] に丸めるので、タブバー回避や safe area にも自然に従う。
        if let saved = FABPositionStore.load() {
            let y = min(max(CGFloat(saved.yFraction) * bounds.height, minY), maxY)
            if saved.tucked {
                // タック状態を復元: 端に半分隠した位置（peek だけ残す）で出す。
                isTucked = true
                tuckedAtMaxX = saved.edgeIsTrailing
                let peekX = saved.edgeIsTrailing ? bounds.width + half - Self.peek : -half + Self.peek
                center = CGPoint(x: peekX, y: y)
                alpha = idleAlpha
                accessibilityHint = "タップで表示"
                applyAppearance()
            } else {
                center = CGPoint(x: saved.edgeIsTrailing ? maxX : minX, y: y)
            }
            return
        }

        switch corner {
        case .topLeading:     center = CGPoint(x: minX, y: minY)
        case .topTrailing:    center = CGPoint(x: maxX, y: minY)
        case .bottomLeading:  center = CGPoint(x: minX, y: maxY)
        case .bottomTrailing: center = CGPoint(x: maxX, y: maxY)
        }
    }

    /// 現在の端・高さ（割合）・タック状態を永続化する。`spring` 等での最終静止位置を渡す。
    private func savePosition(edgeIsTrailing: Bool, y: CGFloat, tucked: Bool, in parent: UIView) {
        let h = parent.bounds.height
        guard h > 0 else { return }
        FABPositionStore.save(edgeIsTrailing: edgeIsTrailing,
                              yFraction: Double(min(max(y / h, 0), 1)),
                              tucked: tucked)
    }

    /// 配置し、タブバーがまだ現れていなければ表示直後だけ短時間リトライ判定する。
    /// 起動直後（onAppear で start）はホストの `UITabBar` が階層に未追加なことがあるため、
    /// 表示の瞬間にタブバーが出てきたら一度だけ上げ直す。ユーザーが触れたら中断（勝手に動かさない）。
    func placeAvoidingTabBar(in container: UIView, corner: FloatingButtonCorner) {
        place(in: container, corner: corner)               // 即時表示（この時点でタブバーがあれば既に上がる）
        scheduleTabBarRecheck(in: container, corner: corner, retriesLeft: 8)
    }

    private func scheduleTabBarRecheck(in container: UIView, corner: FloatingButtonCorner, retriesLeft: Int) {
        guard retriesLeft > 0, extraBottomInset == 0, !hasUserInteracted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak container] in
            guard let self, let container, self.superview != nil,
                  !self.hasUserInteracted, self.extraBottomInset == 0 else { return }
            self.place(in: container, corner: corner)       // 再判定（place 内でタブバー有無を算出）
            if self.extraBottomInset == 0 {                 // まだ見つからなければ続けてリトライ
                self.scheduleTabBarRecheck(in: container, corner: corner, retriesLeft: retriesLeft - 1)
            }
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
        // タック中のタップは引き出す。
        if isTucked {
            if let parent = superview { unTuck(in: parent) }
            return
        }
        // 録画オフ（グレー＝寝てる）: タップで録画オン（起こす）。初見でも当たる導線。
        // 録画オン（オレンジ＝起きてる）: 短タップは無反応にせず長押しを促すヒントを出す。
        if recordingEnabled {
            onShortTapHint?()
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onWake?()
        }
    }

    /// VoiceOver の「アクティベート」（ダブルタップ）。長押しは VoiceOver では行いにくいため、
    /// 状態に応じた本来の操作（録画オフ＝録画オン / 録画オン＝レポート起動）へ直接橋渡しする。
    override func accessibilityActivate() -> Bool {
        if isTucked {
            if let parent = superview { unTuck(in: parent) }
            return true
        }
        if recordingEnabled {
            onTrigger?()
        } else {
            onWake?()
        }
        return true
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
                    applyAppearance()              // ヒントは録画状態に応じて applyAppearance が設定。
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
            let v = recognizer.velocity(in: parent)
            // タックのまま上下移動して離した場合は、縦フリックの勢いで上下に滑らせてから留まる
            //（x はタック位置のまま・y は慣性で移動して保存）。
            if isTucked {
                let projectedY = clampY(center.y + projectedOffset(v.y), in: parent)
                savePosition(edgeIsTrailing: tuckedAtMaxX, y: projectedY, tucked: true, in: parent)
                spring(to: CGPoint(x: center.x, y: projectedY), velocity: v, damping: 0.8, alpha: idleAlpha)
                setActive(false)
                return
            }
            finishDrag(in: parent, velocity: v)
            setActive(false)
        default:
            break
        }
    }

    /// ドラッグ終了時、**離した座標**で判定する。端の定位置より内側で離せば吸着、
    /// 端寄り（しきい値より外）で離せばタック。強いフリックでもその端へタックする。
    /// 端スナップ（左右）は x、滑走は y で扱う：縦フリックの勢いを慣性として y に乗せ、
    /// 勢いぶん先の高さへ滑らせてから止める。spring の初速にもフリック速度を渡す。
    private func finishDrag(in parent: UIView, velocity: CGPoint) {
        let leftRest = restMarginX(in: parent, maxEdge: false)
        let rightRest = restMarginX(in: parent, maxEdge: true)
        let flick: CGFloat = 1500   // pt/s。これ以上の勢いで弾いたら端へ投げてタック。
        let projectedY = clampY(center.y + projectedOffset(velocity.y), in: parent)
        if center.x < leftRest - Self.tuckThreshold || velocity.x < -flick {
            tuck(toMaxEdge: false, in: parent, velocity: velocity, projectedY: projectedY)
        } else if center.x > rightRest + Self.tuckThreshold || velocity.x > flick {
            tuck(toMaxEdge: true, in: parent, velocity: velocity, projectedY: projectedY)
        } else {
            snapToNearestEdge(in: parent, velocity: velocity, projectedY: projectedY)
        }
    }

    /// フリック速度（pt/s）から慣性で滑る追加距離（pt）。
    /// **閾値未満は 0**＝ゆっくり離せば離した位置にそのまま置ける（自由配置を維持）。
    /// 閾値を超えた“意図的なフリック分”だけを緩めに射影するので、勢いよく弾いた時だけ滑る。
    /// `clampY` で画面内に丸めるので、強く弾けば端で止まる。
    private func projectedOffset(_ velocity: CGFloat) -> CGFloat {
        let threshold: CGFloat = 350        // pt/s。これ未満は慣性を効かせない（配置の微調整を残す）。
        let magnitude = abs(velocity)
        guard magnitude > threshold else { return 0 }
        let rate: CGFloat = 0.99            // 0.998 より弱く＝滑りを抑える。
        let offset = ((magnitude - threshold) / 1000) * rate / (1 - rate)
        return velocity < 0 ? -offset : offset
    }

    /// 画面端へスッと隠し、`peek` 幅だけ残す（YouTube ミニプレーヤー風）。
    private func tuck(toMaxEdge: Bool, in parent: UIView, velocity: CGPoint = .zero, projectedY: CGFloat? = nil) {
        let half = Self.diameter / 2
        let targetX = toMaxEdge
            ? parent.bounds.width + half - Self.peek
            : -half + Self.peek
        let targetY = projectedY ?? center.y      // 縦フリックの勢いぶん滑らせた高さへ
        isTucked = true
        tuckedAtMaxX = toMaxEdge
        savePosition(edgeIsTrailing: toMaxEdge, y: targetY, tucked: true, in: parent)
        applyAppearance()                       // 色は録画状態のまま（タックは形状/alpha のみ）。
        accessibilityHint = "タップで表示"
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // 隠す側は跳ね返りが浅め（damping 高め）で「収まる」感じに。
        spring(to: CGPoint(x: targetX, y: targetY), velocity: velocity, damping: 0.78, alpha: idleAlpha)
    }

    /// タック状態から端のマージン位置へ引き出す。
    private func unTuck(in parent: UIView) {
        guard isTucked else { return }
        isTucked = false
        applyAppearance()                          // ヒントは録画状態に応じて applyAppearance が設定。
        let target = clampedCenter(CGPoint(x: tuckedAtMaxX ? .greatestFiniteMagnitude : -.greatestFiniteMagnitude,
                                           y: center.y), in: parent)
        savePosition(edgeIsTrailing: tuckedAtMaxX, y: target.y, tucked: false, in: parent)
        // 引き出しは弾みを強めに（damping 低め）でポンッと出す。
        spring(to: target, damping: 0.55, alpha: activeAlpha) { [weak self] in
            self?.setActive(false)
        }
    }

    /// 中心座標へ spring（跳ね）アニメーションで移動する共通処理。
    /// - Parameters:
    ///   - velocity: フリック速度ベクトル（pt/s）。2D の移動距離で正規化して spring 初速に渡す。
    ///   - damping: 0 に近いほどよく跳ね、1 に近いほど跳ねずに収まる。
    private func spring(to target: CGPoint,
                        velocity: CGPoint = .zero,
                        damping: CGFloat = 0.55,
                        alpha: CGFloat? = nil,
                        completion: (() -> Void)? = nil) {
        let distance = max(hypot(target.x - center.x, target.y - center.y), 0.001)
        let speed = hypot(velocity.x, velocity.y)
        let initialVelocity = distance > 1 ? min(speed / distance, 12) : 0
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
        let maxY = parent.bounds.height - inset.bottom - extraBottomInset - Self.edgeMargin - half
        return CGPoint(x: min(max(point.x, minX), maxX), y: min(max(point.y, minY), maxY))
    }

    /// y 座標だけ safe area 内に丸める（タック中の上下移動用）。
    private func clampY(_ y: CGFloat, in parent: UIView) -> CGFloat {
        let half = Self.diameter / 2
        let minY = parent.safeAreaInsets.top + Self.edgeMargin + half
        let maxY = parent.bounds.height - parent.safeAreaInsets.bottom - extraBottomInset - Self.edgeMargin - half
        return min(max(y, minY), maxY)
    }

    /// 左右いずれかの定位置（吸着位置）の x 座標。
    private func restMarginX(in parent: UIView, maxEdge: Bool) -> CGFloat {
        let half = Self.diameter / 2
        return maxEdge
            ? parent.bounds.width - parent.safeAreaInsets.right - Self.edgeMargin - half
            : parent.safeAreaInsets.left + Self.edgeMargin + half
    }

    // MARK: - ホストのタブバー判定（表示時の一回きり）

    /// ホストアプリに**今表示中のタブバー**があれば、被り回避に下端へ足すインセットを返す（無ければ 0）。
    /// SDK overlay は別ウィンドウのため safeArea にタブバーが含まれない。タブバー高さには下 safe area が
    /// 含まれるので、その分は二重計上しない。標準 `UITabBar` / SwiftUI `TabView` が対象（自作バーは非対象）。
    private static func hostTabBarInset(in container: UIView) -> CGFloat {
        let overlay = container.window
        let scene = overlay?.windowScene
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return 0 }
        // overlay（.alert+1）以外の通常レベル window からホストのタブバーを探す。
        for window in scene.windows where window !== overlay && window.windowLevel == .normal {
            guard let bar = findVisibleTabBar(in: window) else { continue }
            let frame = bar.convert(bar.bounds, to: window)
            // 画面下端に着いている可視のバーだけを対象に（push で外へ逃げたバー等を除外）。
            guard frame.height > 0, frame.maxY >= window.bounds.height - 0.5 else { continue }
            return max(0, frame.height - container.safeAreaInsets.bottom)
        }
        return 0
    }

    /// view 階層から可視の `UITabBar`（window 上・非 hidden・不透明）を再帰探索する。
    private static func findVisibleTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar, bar.window != nil, !bar.isHidden, bar.alpha > 0.01, bar.bounds.height > 0 {
            return bar
        }
        for sub in view.subviews {
            if let found = findVisibleTabBar(in: sub) { return found }
        }
        return nil
    }

    /// ドラッグ中のクランプ。x は端の壁を作らず、タック位置（画面端の外）まで指追従させる。
    /// 端で止まらないので「壁に当たる」違和感が出ない。y は safe area 内。
    private func dragClampedCenter(_ point: CGPoint, in parent: UIView) -> CGPoint {
        let half = Self.diameter / 2
        let xMin = -half + Self.peek
        let xMax = parent.bounds.width + half - Self.peek
        return CGPoint(x: min(max(point.x, xMin), xMax), y: clampY(point.y, in: parent))
    }

    /// 左右の近い端へ吸着させる。横は端へスナップ、縦はフリックの勢いで滑走（慣性）。
    private func snapToNearestEdge(in parent: UIView, velocity: CGPoint = .zero, projectedY: CGFloat? = nil) {
        let inset = parent.safeAreaInsets
        let half = Self.diameter / 2
        let minX = inset.left + Self.edgeMargin + half
        let maxX = parent.bounds.width - inset.right - Self.edgeMargin - half
        let targetX = (center.x - minX) < (maxX - center.x) ? minX : maxX
        let targetY = projectedY ?? center.y
        savePosition(edgeIsTrailing: targetX == maxX, y: targetY, tucked: false, in: parent)
        spring(to: CGPoint(x: targetX, y: targetY), velocity: velocity, damping: 0.6)
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
