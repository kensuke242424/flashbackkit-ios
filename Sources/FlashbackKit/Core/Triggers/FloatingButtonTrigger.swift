#if canImport(UIKit)
import UIKit

/// Trigger that launches the report UI from a small persistent floating button
/// (FAB) drawn as a Time Slice mark.
///
/// The FAB is a real, standalone view placed on the overlay, so
/// `PassthroughWindow.hitTest` only catches the button area and passes everything
/// else through to the host. Reliable launch path even on stationary devices where
/// shaking isn't an option.
///
/// Interaction (role depends on recording state):
/// - Recording off (gray = asleep): single tap turns recording on (wakes it). The
///   asleep state requires no long-press so first-time users hit it naturally.
/// - Recording on (orange = awake): long-press (0.4s) launches the report. A
///   progress ring fills around the mark while pressed, so a sleeve or light touch
///   won't false-trigger. A short tap shows a "long-press to launch the report" hint
///   instead of doing nothing.
/// - Drag to reposition; on release it snaps to / tucks against the nearer edge.
/// - Translucent and unobtrusive at rest, opaque only while touched.
/// - Initial corner is selectable via `FloatingButtonCorner`.
///
/// Appearance (README: orange = recording, gray = not recording):
/// - Recording: orange circle, white ring, white@0.5 wedge.
/// - Long-pressing: the above plus a progress ring.
/// - Tucked at edge: gray, orange@1.0 wedge (recording continues).
/// - Idle (recording off): gray, white@0.6 wedge.
@MainActor
final class FloatingButtonTrigger: TriggerDetecting {
    var onTrigger: (() -> Void)?
    /// Long-press start (gauge begins filling). Used to show the in-progress toast early.
    var onPressStart: (() -> Void)?
    /// Long-press aborted before firing (early release / turned into drag / cancel).
    /// Used to dismiss the early toast.
    var onPressCancel: (() -> Void)?
    /// Single tap while recording is off (gray). Turns recording on (wakes it).
    var onWake: (() -> Void)?
    /// Short tap while recording is on (orange). Shows a long-press hint instead of doing nothing.
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

    /// Toggle recording on/off (idle). Reflects Settings / permission state.
    func setRecordingEnabled(_ enabled: Bool) {
        button?.recordingEnabled = enabled
    }

    /// Exposes the host's visible tab-bar inset (used to avoid overlap) to callers
    /// such as toast positioning. Reuses the same detection as the FAB via `FloatingButtonView`.
    static func hostTabBarInset(in container: UIView) -> CGFloat {
        FloatingButtonView.hostTabBarInset(in: container)
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

/// Persists the FAB's last position (edge + vertical fraction + tuck state) on the device.
/// Stores "which edge" plus "vertical fraction" rather than absolute coordinates, so it
/// survives safe-area / tab-bar differences and other devices. Also keeps the tucked
/// (half-hidden at edge) state to restore the same look next time.
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
        guard d.object(forKey: yKey) != nil else { return nil }   // nil if never saved (use default corner)
        return (d.bool(forKey: edgeKey), d.double(forKey: yKey), d.bool(forKey: tuckedKey))
    }
}

/// The floating button itself: translucent, draggable, fires on long-press (pure UIKit).
/// The glyph is a Time Slice mark (ring + wedge + hub) drawn with CAShapeLayer.
@MainActor
private final class FloatingButtonView: UIView {
    var onTrigger: (() -> Void)?
    /// Long-press start (gauge begins filling) / abort (ended without firing).
    var onPressStart: (() -> Void)?
    var onPressCancel: (() -> Void)?
    /// Single tap while off (gray) = wake recording / short tap while on (orange) = hint.
    var onWake: (() -> Void)?
    var onShortTapHint: (() -> Void)?
    /// Whether this press already fired. Prevents a spurious cancel (toast dismissal) in touchesEnded.
    private var didFire = false
    /// Delays showing the in-progress toast slightly (avoids a flash when the gesture turns into a drag).
    private var pressStartWork: DispatchWorkItem?
    private static let toastDelay: CFTimeInterval = 0.18

    /// Recording on (orange) / off (gray idle). Updates appearance on change.
    /// Plays the time-slice fill/fold transition (color crossfade + wedge 0°⇄66° + pop +
    /// haptic) only when the state actually changes while on screen; otherwise (init / refresh)
    /// it snaps instantly.
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
    private static let markDiameter: CGFloat = 36  // mark diameter inside the button (ratio ≈ 0.64)
    private static let edgeMargin: CGFloat = 16
    private static let peek: CGFloat = 22          // width left visible at the screen edge when tucked
    private static let tuckThreshold: CGFloat = 24 // pushing past this far into the edge tucks
    private static let pressDuration: CFTimeInterval = 0.4   // long-press: short enough to feel responsive, long enough to avoid false triggers
    private static let pressScale: CGFloat = 1.14            // growth at gauge completion (tuned for tactile feel)
    private let idleAlpha: CGFloat = 0.5   // opacity at rest (same while tucked)
    private let activeAlpha: CGFloat = 1.0

    private static let action = FlashbackColor.actionUIColor
    private static let slate = FlashbackColor.slateUIColor

    private let ringLayer = CAShapeLayer()
    private let wedgeLayer = CAShapeLayer()
    private let handLayer = CAShapeLayer()
    private let hubLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    /// Direction chevron shown when tucked (points the way it pulls out). Left-tuck = ▶ / right-tuck = ◀.
    private let chevronLayer = CAShapeLayer()

    private var dragStartCenter: CGPoint = .zero
    private var lastRawCenter: CGPoint = .zero
    private var isTucked = false
    private var tuckedAtMaxX = false
    /// Inset added at the bottom to avoid overlapping the host's tab bar. Measured once at
    /// placement time and held (no dynamic tracking); 0 if there's no tab bar. Reused
    /// consistently for later clamping (drag lower bound).
    private var extraBottomInset: CGFloat = 0
    /// Whether the user has ever touched the button. Used to stop the post-display tab-bar
    /// recheck (re-placement) once they interact.
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
        applyAppearance()                          // also sets accessibilityHint per state here

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = Self.pressDuration
        longPress.cancelsTouchesInView = false
        addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)

        // For un-tucking from the edge. Taps in the normal state are ignored (avoid false triggers).
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Time Slice mark drawing

    private func setUpMarkLayers() {
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.strokeColor = UIColor.white.cgColor
        ringLayer.lineCap = .round
        handLayer.fillColor = UIColor.clear.cgColor
        handLayer.strokeColor = UIColor.white.cgColor       // hand matches ring/hub color (white on the FAB)
        handLayer.lineCap = .round
        hubLayer.fillColor = UIColor.white.cgColor
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        progressLayer.isHidden = true
        chevronLayer.fillColor = UIColor.clear.cgColor
        chevronLayer.strokeColor = UIColor.white.cgColor
        chevronLayer.lineCap = .round
        chevronLayer.lineJoin = .round
        chevronLayer.lineWidth = 2.6
        chevronLayer.isHidden = true               // shown only when tucked (toggled in applyAppearance)
        // Order: ring → wedge → hand → hub → progress → chevron.
        layer.addSublayer(ringLayer)
        layer.addSublayer(wedgeLayer)
        layer.addSublayer(handLayer)
        layer.addSublayer(hubLayer)
        layer.addSublayer(progressLayer)
        layer.addSublayer(chevronLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let k = Self.markDiameter / 64                 // scale from the 64 viewBox
        let radius = 20 * k
        ringLayer.lineWidth = 3.2 * k
        ringLayer.path = UIBezierPath(arcCenter: center, radius: radius,
                                      startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath

        // Wedge (time slice). Drawn at a fill ratio per recording state (off = 0° = folded/hidden, on = 66°).
        // State transitions animate via setWedgeSweep(animated:); here we only snap to the current state.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wedgeLayer.path = wedgePath(sweep: recordingEnabled ? 1 : 0)
        CATransaction.commit()

        // Hand: center → 12 o'clock (r=18, 2 inside the ring). Round cap.
        let hand = UIBezierPath()
        hand.move(to: center)
        hand.addLine(to: CGPoint(x: center.x, y: center.y - 18 * k))
        handLayer.lineWidth = 3.2 * k
        handLayer.path = hand.cgPath

        let hubRadius = 2.6 * k
        hubLayer.path = UIBezierPath(arcCenter: center, radius: hubRadius,
                                     startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath

        // Progress ring: fills counter-clockwise from 12 o'clock just inside the button's edge
        // (counter-clockwise conveys rewinding time).
        let progressRadius = bounds.width / 2 - 2
        progressLayer.lineWidth = 3
        progressLayer.path = UIBezierPath(arcCenter: center, radius: progressRadius,
                                          startAngle: -.pi / 2, endAngle: -.pi / 2 - 2 * .pi,
                                          clockwise: false).cgPath

        // Tuck direction chevron. Placed on the visible side (peek area), pointing the way it pulls out.
        // Left-tuck (tuckedAtMaxX=false) = right side visible → ▶ (pull right) / right-tuck = left visible → ◀.
        let peekHalf = Self.peek / 2
        let cx = tuckedAtMaxX ? peekHalf : bounds.width - peekHalf
        let cw: CGFloat = 5, ch: CGFloat = 11
        let chevron = UIBezierPath()
        if tuckedAtMaxX {                                     // ◀ (pull left)
            chevron.move(to: CGPoint(x: cx + cw / 2, y: center.y - ch / 2))
            chevron.addLine(to: CGPoint(x: cx - cw / 2, y: center.y))
            chevron.addLine(to: CGPoint(x: cx + cw / 2, y: center.y + ch / 2))
        } else {                                             // ▶ (pull right)
            chevron.move(to: CGPoint(x: cx - cw / 2, y: center.y - ch / 2))
            chevron.addLine(to: CGPoint(x: cx + cw / 2, y: center.y))
            chevron.addLine(to: CGPoint(x: cx - cw / 2, y: center.y + ch / 2))
        }
        chevronLayer.path = chevron.cgPath
    }

    /// Sets background color and wedge from recording state only (tuck doesn't affect color).
    /// Instant snap, no animation. Color rule: recording = orange / stopped = gray. When stopped,
    /// the time-slice wedge folds away so the absence of a slice reads as "not recording". The
    /// tucked state is distinguished by shape (half-pill) and alpha instead.
    private func applyAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundColor = recordingEnabled ? Self.action : Self.slate
        wedgeLayer.fillColor = UIColor.white.withAlphaComponent(0.5).cgColor
        wedgeLayer.path = wedgePath(sweep: recordingEnabled ? 1 : 0)
        // When tucked, hide the mark (ring/wedge/hand/hub) and show the direction chevron. Color (half-pill) stays.
        ringLayer.isHidden = isTucked
        wedgeLayer.isHidden = isTucked
        handLayer.isHidden = isTucked
        hubLayer.isHidden = isTucked
        chevronLayer.isHidden = !isTucked
        CATransaction.commit()
        setNeedsLayout()                            // redraw chevron position/direction for the tuck state
        if !isTucked {
            accessibilityHint = recordingEnabled ? "長押しでレポートを起動" : "タップで録画を開始"
        }
    }

    /// Recording on/off transition (the time slice filling in). Color crossfade + wedge 0°⇄66°
    /// sweep + spring pop + haptic (on = firm / off = soft).
    private func animateRecordingTransition(to on: Bool) {
        UIImpactFeedbackGenerator(style: on ? .medium : .soft).impactOccurred()
        wedgeLayer.fillColor = UIColor.white.withAlphaComponent(0.5).cgColor
        UIView.animate(withDuration: 0.3, delay: 0, options: [.allowUserInteraction, .curveEaseInOut]) {
            self.backgroundColor = on ? Self.action : Self.slate
        }
        setWedgeSweep(on ? 1 : 0, animated: true)
        if !UIAccessibility.isReduceMotionEnabled {
            popToggle()
            if on { emitPingRing(color: Self.action) }   // recording armed = outward ping ripple (on only)
        }
        // During the on animation, temporarily go fully opaque, then return to the resting idleAlpha.
        if on, !isTucked {
            UIView.animate(withDuration: 0.16, delay: 0, options: [.allowUserInteraction]) {
                self.alpha = self.activeAlpha
            }
            UIView.animate(withDuration: 0.35, delay: 0.6, options: [.allowUserInteraction]) {
                self.alpha = self.idleAlpha
            }
        }
        if !isTucked {
            accessibilityHint = on ? "長押しでレポートを起動" : "タップで録画を開始"
        }
    }

    /// On recording start, expands one ripple ring out from the button's edge and fades it (radar ping).
    /// To avoid the button's circular clip, the temp layer is placed in the parent behind the FAB and
    /// removed on completion.
    private func emitPingRing(color: UIColor) {
        guard let host = superview else { return }
        let side = Self.diameter
        let ring = CAShapeLayer()
        ring.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        ring.position = center                         // FAB center in parent coordinates
        ring.path = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: side - 2, height: side - 2)).cgPath
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = color.withAlphaComponent(0.65).cgColor
        ring.lineWidth = 2.5
        ring.opacity = 0                               // final state (animates 0.7→0)
        host.layer.insertSublayer(ring, below: layer)  // emerges from behind the FAB

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

    /// Sets the wedge (time slice) fill ratio (0 = folded / 1 = full 66°).
    /// When `animated`, the path is interpolated (filling = easeOut / folding = easeIn);
    /// the point count is constant so it interpolates smoothly.
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

    /// Wedge filled `sweep × 66°` counter-clockwise from 12 o'clock. Fixed point count (for
    /// interpolation); sweep=0 degenerates to invisible.
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

    /// Toggle bounce (swells slightly and settles). A gentler scale than the fire pop (1.25).
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

    // MARK: - Long-press progress (gauge + opacity + slight scale-up)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        hasUserInteracted = true               // from here, the tab-bar recheck won't move it
        didFire = false
        // Touches while tucked are for un-tucking; don't show progress.
        guard !isTucked else { return }
        beginPressRamp()
        // Show the in-progress toast slightly delayed (cancelled before it appears if this becomes a drag).
        schedulePressStart()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        clearPress(restoreActive: false)
        cancelPressStart()
        if !didFire { onPressCancel?() }       // released without firing = dismiss the early toast
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        clearPress(restoreActive: false)
        cancelPressStart()
        if !didFire { onPressCancel?() }
    }

    /// Shows the in-progress toast once the press lasts `toastDelay` (a drag conversion cancels it first).
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

    /// Press start: ramps opacity (rest → opaque) and a slight scale-up (→ `pressScale`) over
    /// `pressDuration`, synced with the gauge fill. All three peak together at the fire moment.
    private func beginPressRamp() {
        progressLayer.isHidden = false
        layer.removeAnimation(forKey: "opacity")

        if UIAccessibility.isReduceMotionEnabled {
            // Reduce Motion: no animation; jump to full gauge and full opacity.
            progressLayer.strokeEnd = 1
            alpha = activeAlpha
            return
        }

        // Fill the gauge (outer ring) linearly over pressDuration.
        progressLayer.strokeEnd = 1
        let fill = CABasicAnimation(keyPath: "strokeEnd")
        fill.fromValue = 0
        fill.toValue = 1
        fill.duration = Self.pressDuration
        fill.timingFunction = CAMediaTimingFunction(name: .linear)
        progressLayer.add(fill, forKey: "press")

        // Sync opacity and the slight scale-up to the gauge (linear, peaking at completion).
        UIView.animate(withDuration: Self.pressDuration, delay: 0,
                       options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]) {
            self.alpha = self.activeAlpha
            self.transform = CGAffineTransform(scaleX: Self.pressScale, y: Self.pressScale)
        }
    }

    /// On fire: clear the gauge. Opacity/scale stay at their completed peak for `popScale` to take over.
    private func endPressGauge() {
        progressLayer.removeAnimation(forKey: "press")
        progressLayer.isHidden = true
        progressLayer.strokeEnd = 0
    }

    /// Press abort (early release / cancel / turned into drag): clear the gauge and quickly
    /// restore opacity and scale.
    /// - Parameter restoreActive: when becoming a drag, go to active (opaque); otherwise to the resting alpha.
    private func clearPress(restoreActive: Bool) {
        endPressGauge()
        UIView.animate(withDuration: 0.18, delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.alpha = restoreActive ? self.activeAlpha : self.idleAlpha
            self.transform = .identity
        }
    }

    /// Initial placement at the given corner.
    /// Detects the host tab bar once at this moment and, if present, raises the bottom edge.
    func place(in container: UIView, corner: FloatingButtonCorner) {
        extraBottomInset = Self.hostTabBarInset(in: container)   // one-shot check at display time (no dynamic tracking)
        let bounds = container.bounds
        let inset = container.safeAreaInsets
        let half = Self.diameter / 2
        let minX = inset.left + Self.edgeMargin + half
        let maxX = bounds.width - inset.right - Self.edgeMargin - half
        let minY = inset.top + Self.edgeMargin + half
        let maxY = bounds.height - inset.bottom - extraBottomInset - Self.edgeMargin - half

        // Restore the saved position (edge + height + tuck) if any.
        // Height is clamped to [minY, maxY], so it naturally respects tab-bar avoidance and safe area.
        if let saved = FABPositionStore.load() {
            let y = min(max(CGFloat(saved.yFraction) * bounds.height, minY), maxY)
            if saved.tucked {
                // Restore tucked: place half-hidden at the edge (only peek showing).
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

    /// Persists the current edge, height (fraction), and tuck state. Pass the final resting
    /// position (e.g. the spring target).
    private func savePosition(edgeIsTrailing: Bool, y: CGFloat, tucked: Bool, in parent: UIView) {
        let h = parent.bounds.height
        guard h > 0 else { return }
        FABPositionStore.save(edgeIsTrailing: edgeIsTrailing,
                              yFraction: Double(min(max(y / h, 0), 1)),
                              tucked: tucked)
    }

    /// Places the button, and if the tab bar hasn't appeared yet, briefly retries the check
    /// just after display. Right at launch (start from onAppear) the host's `UITabBar` may not
    /// be in the hierarchy yet, so if it shows up we raise the button once. Aborts once the user
    /// touches the button (don't move it under them).
    func placeAvoidingTabBar(in container: UIView, corner: FloatingButtonCorner) {
        place(in: container, corner: corner)               // immediate display (already raised if a tab bar exists now)
        scheduleTabBarRecheck(in: container, corner: corner, retriesLeft: 8)
    }

    private func scheduleTabBarRecheck(in container: UIView, corner: FloatingButtonCorner, retriesLeft: Int) {
        guard retriesLeft > 0, extraBottomInset == 0, !hasUserInteracted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak container] in
            guard let self, let container, self.superview != nil,
                  !self.hasUserInteracted, self.extraBottomInset == 0 else { return }
            self.place(in: container, corner: corner)       // re-check (place computes tab-bar presence)
            if self.extraBottomInset == 0 {                 // still not found: keep retrying
                self.scheduleTabBarRecheck(in: container, corner: corner, retriesLeft: retriesLeft - 1)
            }
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            // Even when tucked, a long-press un-tucks and continues straight through to launching
            // the report (no early `return`). Pull-out via tap/drag stays as before.
            if isTucked, let parent = superview {
                unTuck(in: parent)
            }
            didFire = true                     // fire confirmed; touchesEnded won't treat this as a cancel
            endPressGauge()                    // completion = fire; gauge fills then clears (opacity/scale kept)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            popScale()                         // hand off from the ramp scale-up to the fire pop
            onTrigger?()
        case .ended, .cancelled, .failed:
            break                              // alpha/scale cleanup is handled by touchesEnded/Cancelled
        default:
            break
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        // A tap while tucked pulls it out.
        if isTucked {
            if let parent = superview { unTuck(in: parent) }
            return
        }
        // Recording off (gray = asleep): tap wakes recording. A path first-timers hit naturally.
        // Recording on (orange = awake): a short tap shows a long-press hint instead of doing nothing.
        if recordingEnabled {
            onShortTapHint?()
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onWake?()
        }
    }

    /// VoiceOver "activate" (double tap). Long-press is hard under VoiceOver, so bridge directly
    /// to the intended action per state (recording off = wake recording / on = launch report).
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
            // Dragging isn't a long-press. Fold the gauge/scale and return to opaque (active).
            clearPress(restoreActive: true)
            cancelPressStart()                  // cancel the pending toast before it appears (drag-only case)
            if !didFire { onPressCancel?() }    // dismiss it if it already appeared
            dragStartCenter = center
            lastRawCenter = center
        case .changed:
            let t = recognizer.translation(in: parent)
            if isTucked {
                // Pulling far enough away from the edge un-tucks it.
                let pullOut = tuckedAtMaxX ? -t.x : t.x
                if pullOut > 40 {
                    isTucked = false
                    applyAppearance()              // applyAppearance sets the hint per recording state
                    // Hand off smoothly to a normal drag from the current (off-edge) position.
                    dragStartCenter = center
                    lastRawCenter = center
                    recognizer.setTranslation(.zero, in: parent)
                    return
                }
                // Stay tucked, move vertically (x fixed at tuck position, only y follows).
                center = CGPoint(x: center.x, y: clampY(dragStartCenter.y + t.y, in: parent))
                return
            }
            lastRawCenter = CGPoint(x: dragStartCenter.x + t.x, y: dragStartCenter.y + t.y)
            center = dragClampedCenter(lastRawCenter, in: parent)
        case .ended, .cancelled:
            let v = recognizer.velocity(in: parent)
            // If released while still tucked and moved vertically, glide with the flick's
            // momentum then settle (x stays at the tuck position; y moves by inertia and is saved).
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

    /// On drag end, decides based on the release coordinate. Release inside the resting edge
    /// position snaps; release past the threshold tucks. A strong flick also tucks to that edge.
    /// Edge snap (left/right) uses x, glide uses y: vertical flick momentum is carried as inertia
    /// on y, gliding to a height ahead before stopping. Flick speed is also passed as the spring's
    /// initial velocity.
    private func finishDrag(in parent: UIView, velocity: CGPoint) {
        let leftRest = restMarginX(in: parent, maxEdge: false)
        let rightRest = restMarginX(in: parent, maxEdge: true)
        let flick: CGFloat = 1500   // pt/s. A flick faster than this throws it to the edge and tucks.
        let projectedY = clampY(center.y + projectedOffset(velocity.y), in: parent)
        if center.x < leftRest - Self.tuckThreshold || velocity.x < -flick {
            tuck(toMaxEdge: false, in: parent, velocity: velocity, projectedY: projectedY)
        } else if center.x > rightRest + Self.tuckThreshold || velocity.x > flick {
            tuck(toMaxEdge: true, in: parent, velocity: velocity, projectedY: projectedY)
        } else {
            snapToNearestEdge(in: parent, velocity: velocity, projectedY: projectedY)
        }
    }

    /// Extra distance (pt) the button glides by inertia, from flick speed (pt/s).
    /// Below the threshold it returns 0, so a slow release leaves it exactly where dropped
    /// (free placement preserved). Only the intentional flick beyond the threshold is projected,
    /// gently, so it glides only on a deliberate fling. `clampY` keeps it on screen, so a hard
    /// fling stops at the edge.
    private func projectedOffset(_ velocity: CGFloat) -> CGFloat {
        let threshold: CGFloat = 350        // pt/s. Below this, no inertia (keeps fine placement).
        let magnitude = abs(velocity)
        guard magnitude > threshold else { return 0 }
        let rate: CGFloat = 0.99            // damps the glide (lower than 0.998)
        let offset = ((magnitude - threshold) / 1000) * rate / (1 - rate)
        return velocity < 0 ? -offset : offset
    }

    /// Slips the button off the screen edge, leaving only `peek` width (YouTube mini-player style).
    private func tuck(toMaxEdge: Bool, in parent: UIView, velocity: CGPoint = .zero, projectedY: CGFloat? = nil) {
        let half = Self.diameter / 2
        let targetX = toMaxEdge
            ? parent.bounds.width + half - Self.peek
            : -half + Self.peek
        let targetY = projectedY ?? center.y      // to the height glided by vertical flick momentum
        isTucked = true
        tuckedAtMaxX = toMaxEdge
        savePosition(edgeIsTrailing: toMaxEdge, y: targetY, tucked: true, in: parent)
        applyAppearance()                       // color stays per recording state (tuck only changes shape/alpha)
        accessibilityHint = "タップで表示"
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Tucking uses a shallower bounce (higher damping) so it "settles" into place.
        spring(to: CGPoint(x: targetX, y: targetY), velocity: velocity, damping: 0.78, alpha: idleAlpha)
    }

    /// Pulls the button out from tucked to the edge margin position.
    private func unTuck(in parent: UIView) {
        guard isTucked else { return }
        isTucked = false
        applyAppearance()                          // applyAppearance sets the hint per recording state
        let target = clampedCenter(CGPoint(x: tuckedAtMaxX ? .greatestFiniteMagnitude : -.greatestFiniteMagnitude,
                                           y: center.y), in: parent)
        savePosition(edgeIsTrailing: tuckedAtMaxX, y: target.y, tucked: false, in: parent)
        // Pull-out uses a stronger bounce (lower damping) so it pops out.
        spring(to: target, damping: 0.55, alpha: activeAlpha) { [weak self] in
            self?.setActive(false)
        }
    }

    /// Shared spring (bounce) animation to move the center to a target.
    /// - Parameters:
    ///   - velocity: flick velocity vector (pt/s). Normalized by the 2D travel distance and passed as the spring's initial velocity.
    ///   - damping: closer to 0 bounces more, closer to 1 settles without bouncing.
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

    /// Clamps the center so the button stays within the safe area.
    private func clampedCenter(_ point: CGPoint, in parent: UIView) -> CGPoint {
        let inset = parent.safeAreaInsets
        let half = Self.diameter / 2
        let minX = inset.left + Self.edgeMargin + half
        let maxX = parent.bounds.width - inset.right - Self.edgeMargin - half
        let minY = inset.top + Self.edgeMargin + half
        let maxY = parent.bounds.height - inset.bottom - extraBottomInset - Self.edgeMargin - half
        return CGPoint(x: min(max(point.x, minX), maxX), y: min(max(point.y, minY), maxY))
    }

    /// Clamps only the y coordinate within the safe area (for vertical moves while tucked).
    private func clampY(_ y: CGFloat, in parent: UIView) -> CGFloat {
        let half = Self.diameter / 2
        let minY = parent.safeAreaInsets.top + Self.edgeMargin + half
        let maxY = parent.bounds.height - parent.safeAreaInsets.bottom - extraBottomInset - Self.edgeMargin - half
        return min(max(y, minY), maxY)
    }

    /// The x coordinate of the left or right resting (snap) position.
    private func restMarginX(in parent: UIView, maxEdge: Bool) -> CGFloat {
        let half = Self.diameter / 2
        return maxEdge
            ? parent.bounds.width - parent.safeAreaInsets.right - Self.edgeMargin - half
            : parent.safeAreaInsets.left + Self.edgeMargin + half
    }

    // MARK: - Host tab-bar detection (once, at display time)

    /// If the host app currently shows a tab bar, returns the inset to add at the bottom to
    /// avoid overlap (0 otherwise). The SDK overlay is a separate window, so its safeArea
    /// doesn't include the tab bar. The tab-bar height already includes the bottom safe area,
    /// so that part isn't double-counted. Targets a standard `UITabBar` / SwiftUI `TabView`
    /// (custom bars aren't covered). internal because it's reused for toast positioning too.
    static func hostTabBarInset(in container: UIView) -> CGFloat {
        let overlay = container.window
        let scene = overlay?.windowScene
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return 0 }
        // Look for the host's tab bar in normal-level windows other than the overlay (.alert+1).
        for window in scene.windows where window !== overlay && window.windowLevel == .normal {
            guard let bar = findVisibleTabBar(in: window) else { continue }
            let frame = bar.convert(bar.bounds, to: window)
            // Only count a visible bar pinned to the bottom edge (excludes bars pushed off-screen).
            guard frame.height > 0, frame.maxY >= window.bounds.height - 0.5 else { continue }
            return max(0, frame.height - container.safeAreaInsets.bottom)
        }
        return 0
    }

    /// Recursively searches the view hierarchy for a visible `UITabBar` (on a window, not hidden, opaque).
    private static func findVisibleTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar, bar.window != nil, !bar.isHidden, bar.alpha > 0.01, bar.bounds.height > 0 {
            return bar
        }
        for sub in view.subviews {
            if let found = findVisibleTabBar(in: sub) { return found }
        }
        return nil
    }

    /// Clamp during dragging. x has no edge wall: the finger can drag all the way to the tuck
    /// position (off the screen edge), so there's no jarring "hitting a wall". y stays in the safe area.
    private func dragClampedCenter(_ point: CGPoint, in parent: UIView) -> CGPoint {
        let half = Self.diameter / 2
        let xMin = -half + Self.peek
        let xMax = parent.bounds.width + half - Self.peek
        return CGPoint(x: min(max(point.x, xMin), xMax), y: clampY(point.y, in: parent))
    }

    /// Snaps to the nearer left/right edge. Horizontal snaps to the edge; vertical glides with flick momentum (inertia).
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

    /// Scale that briefly swells and bounces on fire. Tactile tap feedback.
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
    /// Preview only: sets state directly (tuck / long-press progress).
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

/// Wrapper for inspecting the FAB's four states in an Xcode preview.
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
        FABStatePreview(recording: true)                          // recording
        FABStatePreview(recording: true, pressProgress: 0.65)     // long-pressing
        FABStatePreview(recording: true, tucked: true)            // tucked at edge
        FABStatePreview(recording: false)                         // idle
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
