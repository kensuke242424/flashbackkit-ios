import Foundation
#if canImport(UIKit) && canImport(SwiftUI)
import UIKit
import SwiftUI

/// Stands up an SDK-owned overlay `UIWindow` and shows the debug triggers (FAB)
/// and report UI without touching the host app's view hierarchy.
///
/// The host only needs `Flashback.start()`.
///
/// Design note: the FAB is not part of the root hosting view; it rides on its own
/// small subview (a dedicated hosting controller). That way `hitTest` only catches
/// taps on the button area and passes everything else through to the host. SwiftUI
/// buttons have no backing UIView of their own, so mixing them into a full-screen
/// hosting view would pull their hit testing into the passthrough.
@MainActor
final class FlashbackPresenter {
    /// The report's half (collapsed) detent. Slightly taller than `.medium` so the
    /// title input below peeks through.
    static let halfDetentID = UISheetPresentationController.Detent.Identifier("flashbackHalf")

    /// Minimum point height for the half detent, used as a floor under the 0.58 ratio.
    ///
    /// The half detent is sized as a fraction (0.58) of the available height. On tall phones
    /// (e.g. iPhone 16, ~852pt screen → ~483pt) that fraction is enough to show the whole clip
    /// content: the preview, the filmstrip at full height, the capture (camera) button just
    /// below it, and the title section peeking through underneath. But on short phones (iPhone SE,
    /// 667pt screen → maximumDetentValue ≈ 647 → 0.58 ≈ 375pt) the same fraction collapses the
    /// sheet so much that the filmstrip is clipped at the bottom edge, the capture button is off
    /// screen entirely, and the title is far out of view — breaking the design intent.
    ///
    /// To fix that, the resolved height takes `max(0.58 × max, floor)` (clamped to `max`). The
    /// floor only ever raises short phones up to a usable height; on tall phones the 0.58 fraction
    /// already exceeds the floor, so they are unchanged. The value is set to iPhone 16's current
    /// 0.58 height so that anything at or below it leaves iPhone 16 (and taller) untouched.
    static let halfDetentFloor: CGFloat = 483

    /// Peak opacity of the self-drawn report backdrop at full `.large` expansion.
    ///
    /// Since the report sheet disables UIKit's own `UIDimmingView` (see
    /// `largestUndimmedDetentIdentifier` in `presentReport`), the window backdrop is the *only*
    /// scrim, so it must match the brightness UIKit's dim would have produced rather than going to
    /// fully black. This value is the measured alpha of a standard `UIDimmingView`: lldb-read on a
    /// plain dimmed sheet (system dim left on) reported `backgroundColor` alpha ≈ 0.12 on
    /// iPhone 16 / iOS 18.4. Using it makes the host show faintly through at `.large`, matching a
    /// stock dimmed sheet instead of a black-out.
    static let backdropMaxAlpha: CGFloat = 0.12

    private let model = OverlayModel()
    private var window: UIWindow?
    private weak var reportHost: UIViewController?
    /// Report sheet detent state (medium = collapsed / large = expanded). Shared
    /// between the delegate and SwiftUI.
    private var reportDetent: SheetDetentModel?
    /// Delegate observing the sheet's detent changes. Strongly retained to keep it alive.
    private var reportSheetDelegate: ReportSheetDelegate?

    /// Drives the report-window backdrop from the sheet's *live* height every frame while the
    /// report is presented (nil otherwise). Started on present, stopped on every dismiss path.
    ///
    /// Why a display link instead of the detent-change delegate: the earlier event-driven sync
    /// (issue #20 follow-up) only fired on `sheetPresentationControllerDidChangeSelectedDetentIdentifier`,
    /// which lands **once, at settle**. The presenting card, however, recedes continuously in step
    /// with the drag, so the black backdrop snapped in at the end while the card-shrink artifact was
    /// already visible mid-drag — a verified mismatch in a real screen recording. Reading the sheet's
    /// presentation-layer frame each frame makes the backdrop track the recede progress instead.
    private var backdropDisplayLink: CADisplayLink?
    /// Weak proxy target for the display link, so the link never retains the presenter
    /// (CADisplayLink retains its target; routing through a weak proxy avoids the retain cycle and
    /// the proxy is harmless if a stop is ever missed).
    private var backdropLinkProxy: DisplayLinkProxy?
    /// Resolved height of the half (collapsed) detent, captured in the custom detent resolver.
    /// `nil` until the first resolve. Re-captured on every layout (rotation / size change).
    private var reportHalfDetentHeight: CGFloat?
    /// The sheet's maximum detent value (`.large` height), captured in the custom detent resolver
    /// alongside the half height so progress is evaluated against the live geometry.
    private var reportMaxDetentValue: CGFloat?
    /// Generation counter for auto-dismissing info toasts, so a stale timer never
    /// clears a newer toast.
    private var infoToastGeneration = 0
    /// Toast bottom constraint, updated at display time for the host's tab bar height.
    private var toastBottomConstraint: NSLayoutConstraint?

    /// Called once when an install() deferred (no active scene yet) finally lands on
    /// scene connection. Lets the controller re-install `triggerHost`-dependent pieces
    /// (e.g. the FAB).
    var onDeferredInstall: (() -> Void)?

    /// Called when the overlay's size changes after initial layout (rotation / iPad
    /// multitasking). Lets the controller re-clamp the FAB into the new bounds.
    var onOverlaySizeChange: (() -> Void)?

    /// Observer that lives only while a deferred install() waits for scene connection/activation.
    private var sceneObserver: SceneConnectionObserver?

    /// Whether actual content (FAB / toast) is excluded from OS capture (screenshot /
    /// recording / mirroring / our own ReplayKit). Default true (hidden). Retained even
    /// if set before install and applied to root in `finishInstall`. The "show in
    /// screenshots/recordings" toggle off = true, on = false.
    private(set) var excludesContentFromCapture = true

    /// Installs the overlay window on the foreground scene. Each detector mounts its
    /// trigger UI (button / gesture) via `triggerHost`.
    ///
    /// In SceneDelegate apps called from `didFinishLaunching` (before scene connection),
    /// there's no active `UIWindowScene` yet, so the install is **deferred** and runs
    /// automatically once a scene connects. This makes the overlay come up regardless of
    /// call timing (didFinishLaunching / scene(_:willConnectTo:) / onAppear).
    func install() {
        guard window == nil else { return }
        guard let scene = Self.activeScene() else {
            observeSceneConnectionForDeferredInstall()
            return
        }
        finishInstall(in: scene)
    }

    /// Creates and installs the overlay window (shared path once a scene is available).
    private func finishInstall(in scene: UIWindowScene) {
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear

        // Use a secure root that excludes its content from OS capture. The FAB / toast
        // mount under it, so they never appear in screenshots / recordings / mirroring /
        // our own ReplayKit.
        let root = SecureOverlayRootController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        window.isHidden = false
        self.window = window

        root.view.layoutIfNeeded()          // resolve the secure canvas before adding content
        if let rootView = root.view as? SecureOverlayRootView {
            rootView.excludesFromCapture = excludesContentFromCapture
            rootView.onSizeChange = { [weak self] in self?.onOverlaySizeChange?() }
        }
        installStatusOverlay(in: root)
    }

    /// Toggles at runtime whether actual content (FAB / toast) is excluded from OS
    /// capture (settings toggle). `false` intentionally shows it in screenshots/recordings.
    /// Retains the value before install and applies it on install.
    func setExcludesContentFromCapture(_ exclude: Bool) {
        excludesContentFromCapture = exclude
        (window?.rootViewController?.view as? SecureOverlayRootView)?.excludesFromCapture = exclude
    }

    /// Defers install (no active scene) and waits for a scene connection/activation notification.
    private func observeSceneConnectionForDeferredInstall() {
        guard sceneObserver == nil else { return }                 // already waiting
        FlashbackLog.lifecycle.info("overlay 設置を保留：アクティブな UIWindowScene が未接続。シーン接続後に自動設置する（SceneDelegate アプリで didFinishLaunching から start() を呼んだ場合など）。")
        sceneObserver = SceneConnectionObserver { [weak self] in self?.tryDeferredInstall() }
    }

    /// Completes the deferred install as soon as an active scene is available, then
    /// calls onDeferredInstall once.
    private func tryDeferredInstall() {
        guard window == nil else {                                 // already installed via another path
            sceneObserver = nil
            return
        }
        guard let scene = Self.activeScene() else { return }       // not available yet (wait for next notification)
        finishInstall(in: scene)
        sceneObserver = nil                                        // stop observing (deinit removes the observer)
        FlashbackLog.lifecycle.info("シーン接続を検知し overlay を自動設置（保留分）。")
        onDeferredInstall?()
    }

    /// Overlay root view controller that trigger detectors mount UI (FAB) onto.
    /// Valid after `install()`.
    var triggerHost: UIViewController? {
        window?.rootViewController
    }

    /// Tears down the overlay window.
    func uninstall() {
        sceneObserver = nil                                        // cancel any pending scene-wait observation
        stopReportBackdropTracking()                               // stop the link + clear the window before teardown
        reportHost?.dismiss(animated: false)
        reportHost = nil
        reportSheetDelegate = nil
        reportDetent = nil
        window?.isHidden = true
        window = nil
    }

    /// Presents the report input UI as a half-modal (a custom half detent, swipe up for `.large`).
    ///
    /// At half height it shows the video preview plus the clip bar (trimmer); share (↑) lives
    /// in the nav bar so you can **share without leaving half**. Swiping up (`.large`) reveals
    /// the title and device info. The preview is small at half and large at `.large`, so the
    /// half height never collapses the clip bar.
    /// - Parameters:
    ///   - clipURL: the most recent clip (shows preview + trimming if present); otherwise an idle notice.
    ///   - onShare: share action. Trims, commits, and returns the final clip URL for the share sheet.
    ///   - settings: settings screen store (pushed from the gear / "turn recording on").
    func presentReport(
        clipURL: URL?,
        onShare: @escaping (String, ClosedRange<Double>?) async -> URL?,
        settings: FlashbackSettingsStore
    ) {
        guard let root = window?.rootViewController, root.presentedViewController == nil else { return }

        let detent = SheetDetentModel()
        let report = ReportView(
            clipURL: clipURL,
            device: .current(),                           // @MainActor capture (this method is @MainActor)
            onShare: onShare,
            onCancel: { [weak self] in self?.dismissReport() },
            onRequestExpand: { [weak self] in self?.expandReportSheet() },
            settings: settings,
            detent: detent
        )
        // Present in a host that defers bottom system gestures, so dragging the bottom-edge
        // capture button doesn't get captured by the OS gestures.
        let host = DeferBottomGesturesHostingController(rootView: report)
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            // Standard .medium gets exactly filled by the recording view + trimmer, fully
            // hiding the title input below so there's no hint of "more below". A slightly
            // taller custom detent lets it peek through (and also lifts the bottom capture
            // button clear of the bottom system-gesture band).
            let halfDetent = UISheetPresentationController.Detent.custom(identifier: Self.halfDetentID) { [weak self] context in
                // 0.58 of the available height, but never below `halfDetentFloor` (so the filmstrip,
                // capture button, and title peek stay visible on short phones like iPhone SE), and
                // never above the maximum. On tall phones 0.58 already wins, so they don't change.
                let resolved = min(context.maximumDetentValue, max(context.maximumDetentValue * 0.58, Self.halfDetentFloor))
                // Stash the resolved half height and the max (`.large`) value for the backdrop
                // progress math. The resolver is re-invoked on every layout (rotation / size change),
                // so these stay current without any extra observers.
                self?.reportHalfDetentHeight = resolved
                self?.reportMaxDetentValue = context.maximumDetentValue
                return resolved
            }
            sheet.detents = [halfDetent, .large()]
            sheet.selectedDetentIdentifier = Self.halfDetentID   // start at half (height that peeks the title)
            sheet.prefersGrabberVisible = true            // grabber hinting that it opens on swipe up
            // Disable the system dim for *every* detent of the report sheet (report-only; other
            // sheets — priming / settings — keep their default dim). The system dim is the
            // `UIDimmingView` UIKit attaches to the presenting card; on `.pageSheet` `.large` that
            // card recedes/scales and the dim recedes/scales with it. On our transparent overlay
            // window that produced the "grey shrinking card" artifact (the dim painting a faint
            // grey over the transparent receded card, lldb-confirmed). With the dim disabled there
            // is no UIKit scrim to recede, so the artifact's source is gone; the scrim is now fully
            // self-drawn by the window backdrop (`updateReportBackdrop`), which paints the *whole*
            // window — not a shrinking card — at an OS-matched alpha. Setting it to `.large` (the
            // largest detent) means no detent is dimmed, so half stays clear (host shows through,
            // unchanged) and `.large` is scrimmed by our backdrop instead of UIKit's.
            sheet.largestUndimmedDetentIdentifier = .large
            // The delegate now only mirrors the detent into SheetDetentModel (its original role).
            // The window backdrop is driven separately, every frame, by the display link.
            let delegate = ReportSheetDelegate(
                model: detent,
                onDidDismiss: { [weak self] in self?.stopReportBackdropTracking() }
            )
            sheet.delegate = delegate
            reportSheetDelegate = delegate
        }
        reportDetent = detent
        reportHost = host
        // Initial detent is half (undimmed): leave the window clear so the host shows
        // through as intended. The backdrop darkens continuously as the sheet recedes toward
        // `.large`, driven by the display link started below.
        root.present(host, animated: true)
        startReportBackdropTracking()
    }

    // MARK: - Report backdrop tracking (progress-driven)

    /// Synchronizes the overlay window's backdrop opacity with the report sheet's *live* height.
    ///
    /// Why this is needed: the SDK presents from a transparent overlay `UIWindow`
    /// (`PassthroughWindow`, `backgroundColor == .clear`) so the host shows through where no
    /// overlay content sits. A `.pageSheet` at `.large` shrinks the *presenting* view into a
    /// receded card and attaches its dim to that card — it never paints the whole window. In a
    /// normal app the area around the card reads as black because the presenting window itself
    /// has an opaque (black) backdrop. Our window is transparent, so there is no such backdrop:
    /// at `.large` the receded card and the host window behind it both show through, which is the
    /// "card shrinks, host bleeds through" bug (issue #20).
    ///
    /// Why this is *progress-driven*, not event-driven: the first fix dimmed the window black only
    /// while the detent-change delegate reported `.large`. That delegate fires once, at settle, but
    /// the presenting card recedes continuously in step with the drag — so the black backdrop
    /// snapped in only after the drag finished, while the card-shrink artifact was already on screen
    /// mid-drag (a mismatch verified in a real screen recording). Instead, a display link samples the
    /// sheet's presentation-layer frame every frame and sets the backdrop alpha from how far the
    /// sheet has receded between the half height and `.large`. This makes drag-follow, cancelled
    /// swipes (progress runs back down), programmatic expand (smooth via the presentation layer),
    /// swipe-dismiss (fades out as it drops), and slide-in (clear below the half height) all correct
    /// for free.
    private func startReportBackdropTracking() {
        guard backdropDisplayLink == nil else { return }
        let proxy = DisplayLinkProxy { [weak self] in self?.updateReportBackdrop() }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)             // .common so it keeps firing during tracking/scroll run loops
        backdropLinkProxy = proxy
        backdropDisplayLink = link
        updateReportBackdrop()                            // seed the initial color without waiting a frame
    }

    /// Stops the display link and resets the backdrop to clear. Called on every dismiss path
    /// (programmatic, swipe-complete via `presentationControllerDidDismiss`, and teardown), so the
    /// window is never left blacked out and the link never outlives the presentation.
    private func stopReportBackdropTracking() {
        backdropDisplayLink?.invalidate()
        backdropDisplayLink = nil
        backdropLinkProxy = nil
        reportHalfDetentHeight = nil
        reportMaxDetentValue = nil
        window?.backgroundColor = .clear
    }

    /// One display-link tick: reads the sheet's live presented-view frame and paints the overlay
    /// window black in proportion to how far the sheet has receded toward `.large`.
    ///
    /// `progress = (h_now - h_half) / (h_max - h_half)`, clamped to 0...1, where `h_now` is the live
    /// sheet height from the presentation-layer frame (so it tracks the in-flight animation, not the
    /// settled model value), and `h_half` / `h_max` come from the custom detent resolver.
    private func updateReportBackdrop() {
        guard let window,
              let presentationController = reportHost?.presentationController,
              let containerView = presentationController.containerView,
              let presentedView = presentationController.presentedView,
              let half = reportHalfDetentHeight,
              let max = reportMaxDetentValue,
              max > half else { return }

        // Use the presentation layer so the height reflects the in-flight animation position
        // (drag / spring), not the settled geometry; fall back to the model layer. Convert the
        // layer's top-left into the container layer's coordinate space (robust across any wrapper
        // layers between the presented view and the container), then derive the visible sheet
        // height as the distance from that top edge to the container's bottom.
        let layer = presentedView.layer.presentation() ?? presentedView.layer
        let topInContainer = containerView.layer.convert(CGPoint(x: 0, y: 0), from: layer)
        let heightNow = containerView.bounds.height - topInContainer.y

        // Scale the recede progress (0...1) by the OS-matched peak alpha so the backdrop tops out at
        // a standard dim level (host faintly visible at `.large`) instead of fully black.
        let progress = ((heightNow - half) / (max - half)).clampedToUnitInterval()
        window.backgroundColor = UIColor.black.withAlphaComponent(progress * Self.backdropMaxAlpha)
    }

    /// Expands the report sheet to `.large`. Used before transitions that feel cramped at
    /// half (e.g. pushing settings). The backdrop follows the expansion automatically via the
    /// display link tracking the presentation-layer frame — no manual dimming needed here.
    private func expandReportSheet() {
        guard let sheet = reportHost?.sheetPresentationController else { return }
        sheet.animateChanges { sheet.selectedDetentIdentifier = .large }
        reportDetent?.isExpanded = true                   // reflect immediately without waiting for the delegate (enlarges the preview)
    }

    /// Dismisses the report input UI.
    func dismissReport() {
        // Stop the tracker and clear the window first so it doesn't flash black behind a sheet
        // animating away. Swipe-dismiss (which bypasses this path) is covered by
        // `presentationControllerDidDismiss` → `stopReportBackdropTracking`.
        stopReportBackdropTracking()
        reportHost?.dismiss(animated: true)
        reportHost = nil
        reportSheetDelegate = nil
        reportDetent = nil
    }

    /// Presents the permission priming sheet (`.medium`) on the overlay. Inserts a screen
    /// explaining why screen-recording permission is needed before the OS prompt, even on
    /// paths that don't open the report (e.g. greyed FAB taps). Close / swipe dismiss via
    /// the shared `dismissReport`.
    func presentPriming(onProceed: @escaping () -> Void, onLater: @escaping () -> Void) {
        guard let root = window?.rootViewController, root.presentedViewController == nil else { return }
        let host = UIHostingController(rootView: PermissionPrimingView(onProceed: onProceed, onLater: onLater))
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        reportHost = host
        root.present(host, animated: true)
    }

    /// Presents the "shake twice to launch" hint (a center alert-style card) frontmost.
    /// Expected to fire once right after the FAB is turned off. Overlays a transparent host
    /// with a dimming scrim via `.overFullScreen` + `.crossDissolve`; OK dismisses it.
    /// Skipped if something is already presented (avoid double presentation).
    func presentShakeHint() {
        guard let root = window?.rootViewController else { return }
        let top = Self.topmost(from: root)
        guard top.presentedViewController == nil else { return }

        // Inject the reference after creation so the OK handler can dismiss itself.
        let box = WeakVCBox()
        let host = UIHostingController(
            rootView: ShakeHintHostView(onDismiss: { [box] in box.vc?.dismiss(animated: true) })
        )
        box.vc = host
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        host.view.backgroundColor = .clear
        top.present(host, animated: true)
    }

    /// Progress toast (orange spinner). Shown during export.
    func showProgress(_ message: String) {
        positionToastAboveHostTabBar()
        model.toast = .progress(message)
    }

    /// Failure toast (red icon + blue "retry"). Does not auto-dismiss.
    func showFailure(_ message: String, onRetry: @escaping () -> Void) {
        positionToastAboveHostTabBar()
        model.toast = .failure(message: message, onRetry: onRetry)
    }

    /// Info toast (operation hint). Auto-dismisses after a delay. For transient guidance that
    /// requires no active action (e.g. a long-press hint shown after a quick FAB tap). The
    /// generation counter clears it only while this auto-dismiss's own info is still showing,
    /// so a later toast (e.g. progress) isn't cleared by mistake.
    func showInfo(_ message: String, duration: TimeInterval = 1.8) {
        positionToastAboveHostTabBar()
        infoToastGeneration += 1
        let generation = infoToastGeneration
        model.toast = .info(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.infoToastGeneration == generation else { return }
            if case .info = self.model.toast { self.model.toast = nil }
        }
    }

    /// Hides the toast.
    func hideToast() {
        model.toast = nil
    }

    /// Hides only the progress toast. Used to cancel the early-shown long-press progress
    /// toast. Leaves info (operation hints) and failure alone, so a hint shown on a short tap
    /// isn't swept away right after by the same finger-up's `onPressCancel`.
    func hideProgressToast() {
        if case .progress = model.toast { model.toast = nil }
    }

    #if DEBUG
    /// DEBUG only: presents the settings screen standalone (in its own NavigationStack) for
    /// visual checks. In production it's pushed from ReportView's gear and backs out via the
    /// report nav bar, but the standalone presentation has no parent, so a "close" button is
    /// added to avoid a dead end (does not affect the production SettingsView).
    func debugPresentSettings(store: FlashbackSettingsStore) {
        guard let root = window?.rootViewController, root.presentedViewController == nil else { return }
        let view = NavigationStack {
            SettingsView(store: store)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { [weak self] in self?.dismissReport() }
                    }
                }
        }
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .fullScreen
        reportHost = host
        root.present(host, animated: true)
    }

    /// DEBUG only: expands the currently-presented report sheet to `.large` (animated). Used by
    /// the `FLASHBACK_EXPAND_DEMO` env hook to verify the `.large` backdrop without a manual swipe.
    /// No-op if no report sheet is up.
    func debugExpandReport() {
        guard reportHost?.sheetPresentationController != nil else { return }
        expandReportSheet()
    }

    #endif

    // MARK: - Install

    private func installStatusOverlay(in root: UIViewController) {
        let overlay = UIHostingController(rootView: StatusOverlay(model: model))
        overlay.view.backgroundColor = .clear
        overlay.view.translatesAutoresizingMaskIntoConstraints = false
        // Mount just the toast at bottom center (content-sized). Interaction stays enabled so
        // the failure toast's "retry" is tappable. It covers no area outside the toast, so it
        // never blocks the host or FAB.
        root.addChild(overlay)
        root.view.addSubview(overlay.view)
        let guide = root.view.safeAreaLayoutGuide
        // Base 36pt above the bottom. If the host has a tab bar, lift it further by that height
        // at display time (below).
        let bottom = overlay.view.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -Self.toastBaseBottomMargin)
        toastBottomConstraint = bottom
        NSLayoutConstraint.activate([
            overlay.view.centerXAnchor.constraint(equalTo: root.view.centerXAnchor),
            bottom,
            overlay.view.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 16),
            overlay.view.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -16),
        ])
        overlay.didMove(toParent: root)
    }

    private static let toastBaseBottomMargin: CGFloat = 36

    /// Just before display, adds the tab bar height to the bottom offset so the toast doesn't
    /// overlap the host's tab bar (stays at base if there's no tab bar). The tab bar lives in a
    /// separate window, so this reuses the same detection as the FAB.
    private func positionToastAboveHostTabBar() {
        guard let container = window?.rootViewController?.view else { return }
        let inset = FloatingButtonTrigger.hostTabBarInset(in: container)
        toastBottomConstraint?.constant = -(Self.toastBaseBottomMargin + inset)
    }

    /// Walks the presentation chain to the frontmost view controller.
    private static func topmost(from vc: UIViewController) -> UIViewController {
        var top = vc
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    /// Finds the active foreground scene.
    private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

/// Box for injecting a view controller reference after creation, so a closure can weakly dismiss it.
@MainActor
private final class WeakVCBox {
    weak var vc: UIViewController?
}

/// Waits for a scene connection/activation notification to drive the deferred install when no
/// active scene exists. Split out into an NSObject because `NotificationCenter`'s selector target
/// needs an ObjC-capable object (`FlashbackPresenter` itself isn't NSObject). Notifications are
/// delivered on main, but for Swift 6 we hop to `@MainActor` before notifying the host.
@MainActor
private final class SceneConnectionObserver: NSObject {
    private let onConnect: () -> Void

    init(onConnect: @escaping () -> Void) {
        self.onConnect = onConnect
        super.init()
        let nc = NotificationCenter.default
        // Catch on whichever fires first, willConnect or didActivate. tryDeferredInstall guards
        // "already installed / no scene yet" idempotently, so a double fire is harmless.
        nc.addObserver(self, selector: #selector(sceneConnected),
                       name: UIScene.willConnectNotification, object: nil)
        nc.addObserver(self, selector: #selector(sceneConnected),
                       name: UIScene.didActivateNotification, object: nil)
    }

    /// Notification callback (nonisolated since it may arrive off the main thread). Ignores the
    /// payload and hops to `@MainActor`.
    @objc nonisolated private func sceneConnected() {
        Task { @MainActor [weak self] in self?.onConnect() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

/// Tells SwiftUI whether the report half-modal is open all the way to `.large` (expanded). Used
/// e.g. to enlarge the video preview. `ReportSheetDelegate` updates it on detent changes.
@MainActor
final class SheetDetentModel: ObservableObject {
    /// Whether it's expanded to `.large` (false = the half detent).
    @Published var isExpanded: Bool = false
}

/// Delegate observing the sheet's selected-detent changes and reflecting them into
/// `SheetDetentModel` (its sole job — e.g. enlarging the video preview at `.large`). The overlay
/// window's backdrop is **no longer** driven from here: it follows the sheet's live height via a
/// display link (see `FlashbackPresenter.updateReportBackdrop`), because the detent-change callback
/// only fires at settle and so couldn't track the continuous card recede. `@MainActor` since UIKit
/// calls it on main.
///
/// `UISheetPresentationControllerDelegate` refines `UIAdaptivePresentationControllerDelegate`, so
/// the swipe-dismiss callback (`…DidDismiss`) lands here too — used to stop the backdrop tracker on
/// an interactive dismiss, which never goes through `dismissReport()`.
@MainActor
private final class ReportSheetDelegate: NSObject, UISheetPresentationControllerDelegate {
    private let model: SheetDetentModel
    /// Called once the sheet has actually been dismissed (incl. swipe-completed) so the presenter
    /// can stop the display link and clear the window — that path bypasses `dismissReport()`.
    private let onDidDismiss: () -> Void

    init(
        model: SheetDetentModel,
        onDidDismiss: @escaping () -> Void
    ) {
        self.model = model
        self.onDidDismiss = onDidDismiss
    }

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheet: UISheetPresentationController) {
        model.isExpanded = sheet.selectedDetentIdentifier == .large
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onDidDismiss()
    }
}

/// Weak relay between `CADisplayLink` (which retains its target) and the presenter, so the link
/// never forms a retain cycle with the presenter. If a stop is ever missed the proxy simply calls
/// into a deallocated weak reference (a no-op) rather than keeping the presenter alive.
@MainActor
private final class DisplayLinkProxy {
    private let onTick: () -> Void
    init(onTick: @escaping () -> Void) { self.onTick = onTick }
    @objc func tick() { onTick() }
}

private extension CGFloat {
    /// Clamps the value into `0...1`. Used for the backdrop recede progress.
    func clampedToUnitInterval() -> CGFloat { Swift.min(1, Swift.max(0, self)) }
}

/// A `UIWindow` that passes touches outside concrete subviews (e.g. buttons) through to the host app.
///
/// `internal` (not `private`) only so unit tests can drive `hitTest` end-to-end through the real
/// window → secure-root structure (the iPad passthrough bug lives at this layer); not public API.
@MainActor
final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // Hit the window itself = empty area → pass through to the host (unless a scrim is up; see
        // `passthroughOrScrim`).
        guard let hit, hit !== self else { return passthroughOrScrim() }

        // If the resolved view is inside our overlay root's subtree, trust the root's own decision:
        // `SecureOverlayRootView.hitTest` only catches `contentHost`'s real descendants (the mounted
        // FAB / toast) and returns nil for everything else.
        //
        // Why this layer matters on iPad: the secure field's render canvas hosts a full-bounds,
        // interactive `contentHost`, and `UIWindow`'s built-in hit-testing descends straight into it,
        // returning `contentHost` (or the field's internal views) even where nothing is mounted. The
        // old denylist here ("window / root view" → nil) didn't recognize those, so every empty-area
        // tap (host tabs / buttons) got swallowed. Re-asking the root view collapses the answer to
        // "real content or pass-through" on every idiom / iOS version. Real content (FAB / toast)
        // still wins here — only a *nil* (empty) result falls through to the scrim gate.
        if let root = rootViewController?.view {
            if hit.isDescendant(of: root) {
                if let inner = root.hitTest(convert(point, to: root), with: event) { return inner }
                return passthroughOrScrim()
            }
            // `UIWindow` may resolve an empty point to the root view's *container* chain (the VC
            // wrapper / `UIDropShadowView`) rather than into the root itself. That's still empty
            // overlay → pass through to the host (or hold for the scrim).
            if root.isDescendant(of: hit) { return passthroughOrScrim() }
        }
        // A presented report / settings / priming sheet lives in its own transition container — a
        // separate subtree from the overlay root. Keep the default result so it stays interactive.
        return hit
    }

    /// Decides what an otherwise-empty (pass-through) point should return.
    ///
    /// Normally the overlay window is transparent and empty taps fall through to the host (returns
    /// `nil`). But the report's `.large` scrim is self-drawn onto this window's `backgroundColor`
    /// (see `FlashbackPresenter.updateReportBackdrop`) because the sheet disables UIKit's own
    /// `UIDimmingView`. UIKit's dim used to intercept taps in the top gap above the sheet; with it
    /// gone, those taps would pass straight through the (now visibly scrimmed) window to the host
    /// behind it — a tap landing on something the user can't even see. So while the backdrop is
    /// painted (alpha > a hair above 0), swallow the tap by returning the window itself instead of
    /// `nil`. At alpha ~0 (half detent / no sheet) it returns `nil` exactly as before, leaving the
    /// established pass-through behavior unchanged.
    private func passthroughOrScrim() -> UIView? {
        if let alpha = backgroundColor?.cgColor.alpha, alpha > 0.01 { return self }
        return nil
    }
}

/// Overlay root view that excludes its content from OS screenshot/recording/mirroring and our own
/// ReplayKit. A secure `isSecureTextEntry` `UITextField` keeps an internal render canvas that the OS
/// excludes from capture, so we re-parent the added content (FAB / toast) onto that canvas
/// (**undocumented, iOS-version-dependent**). If the canvas can't be obtained, it works as a normal
/// view (no-exclusion fallback). Since the canvas lives under `secureField`, `secureField` is also
/// made interactive so its descendants are hit-testable, and empty areas return nil from `hitTest`
/// to keep passing through to the host.
///
/// `internal` (not `private`) only so unit tests can exercise `hitTest` passthrough
/// directly (iPad's secure-field internals add views that mustn't swallow host taps);
/// not part of the public API.
@MainActor
final class SecureOverlayRootView: UIView {
    private let secureField = UITextField()
    /// Permanent container for the actual content (FAB / toast). Re-parenting this whole container
    /// between the excluded canvas and the normal view toggles capture exclusion at runtime while
    /// preserving the children's state.
    private let contentHost = UIView()
    /// `secureField`'s internal render canvas (nil if unobtainable = no-exclusion fallback).
    private var canvas: UIView?

    /// Fired when the overlay's size changes after the initial layout (rotation / iPad
    /// multitasking), so mounted content (the FAB) can re-clamp itself into the new bounds.
    var onSizeChange: (() -> Void)?
    /// Last laid-out size. `nil` until the first `layoutSubviews`, which only records the
    /// baseline (initial placement is the trigger's job, not a "change").
    private var lastLaidOutSize: CGSize?

    /// Whether the content is excluded from OS capture. `true` (default) = mount on the excluded
    /// canvas; `false` = mount on the normal view to intentionally show it. If the canvas isn't
    /// obtained, exclusion is impossible and content mounts on the normal view.
    var excludesFromCapture: Bool = true {
        didSet { guard excludesFromCapture != oldValue else { return }; applyContentPlacement() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        secureField.isSecureTextEntry = true
        secureField.isUserInteractionEnabled = true       // make descendants (canvas/contentHost) hit-testable
        secureField.backgroundColor = .clear
        super.addSubview(secureField)                     // bypass our addSubview override
        secureField.frame = bounds
        secureField.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        contentHost.backgroundColor = .clear
        contentHost.frame = bounds
        contentHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        resolveCanvasIfNeeded()
        applyContentPlacement()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Resolves `secureField`'s internal render canvas (once, when it becomes available).
    private func resolveCanvasIfNeeded() {
        guard canvas == nil, let c = secureField.subviews.first else { return }
        c.isUserInteractionEnabled = true
        c.frame = bounds
        c.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        c.subviews.forEach { $0.removeFromSuperview() }   // strip existing subviews (caret etc.)
        canvas = c
        applyContentPlacement()                            // canvas now available; apply desired placement
    }

    /// Re-parents `contentHost` to the canvas (excluded) or self (visible) per the exclusion setting.
    private func applyContentPlacement() {
        if excludesFromCapture, let canvas {
            canvas.addSubview(contentHost)                 // under the excluded canvas = excluded from OS capture
        } else {
            super.addSubview(contentHost)                  // under the normal view = visible, frontmost
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resolveCanvasIfNeeded()                            // pick it up after layout if not yet created at init

        // Detect overlay size changes (rotation / iPad multitasking) and let mounted content
        // re-clamp. The first pass only records the baseline: initial placement is the trigger's
        // job, so we don't fire on it (would otherwise stomp the trigger's own first placement).
        let size = bounds.size
        if let last = lastLaidOutSize {
            if last != size {
                lastLaidOutSize = size
                onSizeChange?()
            }
        } else {
            lastLaidOutSize = size
        }
    }

    override func addSubview(_ view: UIView) {
        if view === secureField || view === contentHost {
            super.addSubview(view)
        } else {
            contentHost.addSubview(view)                   // actual content goes into the permanent container
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // Allowlist by ancestry: only catch the tap when it lands on a *true descendant* of
        // `contentHost` (our mounted FAB / toast). Everything else passes through to the host.
        //
        // A denylist (self / secureField / canvas / contentHost → nil) is unsafe: the secure
        // field's internal render views are undocumented and idiom/iOS-dependent. On iPad the
        // field nests extra full-bounds internal `UIView`s under its canvas; once real content is
        // mounted these can come out on top of empty areas, and a denylist returns them — swallowing
        // every host tap (tabs, buttons) across the whole screen. Anchoring on contentHost's subtree
        // is robust regardless of how many internal views the field adds.
        guard let hit, hit !== contentHost, hit.isDescendant(of: contentHost) else { return nil }
        return hit
    }
}

/// Overlay root controller whose `view` is the secure root view.
///
/// `internal` (not `private`) only so unit tests can reproduce the real overlay structure
/// (window → controller → secure root); not part of the public API.
@MainActor
final class SecureOverlayRootController: UIViewController {
    override func loadView() { view = SecureOverlayRootView() }
}

#if DEBUG
extension SecureOverlayRootView {
    /// Test-only: the secure `UITextField` whose excluded internal canvas hosts the content.
    /// Exposed to let tests dump its internal view hierarchy (which differs by iOS/idiom).
    var test_secureField: UITextField { secureField }
}
#endif

/// Toast content.
enum ToastContent {
    /// In progress (orange spinner).
    case progress(String)
    /// Failure (red icon + blue "retry"). Does not auto-dismiss.
    case failure(message: String, onRetry: () -> Void)
    /// Info (operation hint; auto-dismisses after a delay).
    case info(String)
}

/// Overlay UI state.
@MainActor
private final class OverlayModel: ObservableObject {
    @Published var toast: ToastContent?

    /// Key for animation diffing (since `ToastContent` isn't Equatable).
    var toastKey: String {
        switch toast {
        case .progress(let m): return "p:\(m)"
        case .failure(let m, _): return "f:\(m)"
        case .info(let m): return "i:\(m)"
        case nil: return ""
        }
    }
}

/// Overlay that shows the toast at bottom center. Only the failure toast's "retry" takes taps.
private struct StatusOverlay: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        Group {
            switch model.toast {
            case .progress(let message):
                ToastCapsule {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FlashbackColor.action)              // orange spinner
                    Text(message)
                }
            case .failure(let message, let onRetry):
                ToastCapsule {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(FlashbackColor.danger)   // red
                    Text(message)
                    Button(action: onRetry) {
                        HStack(spacing: 2) {
                            Text("再試行")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(FlashbackColor.settingsLink)   // blue
                    }
                    .accessibilityLabel("再試行")
                }
            case .info(let message):
                ToastCapsule {
                    Image(systemName: "hand.tap")
                        .foregroundStyle(FlashbackColor.action)   // orange (cue toward the long-press gesture)
                    Text(message)
                }
            case nil:
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toastKey)
    }
}

/// Toast's inverted background color (dynamic UIColor; follows live appearance changes via trait
/// resolution). bg: light = near-black (20,20,24 @0.92) / dark = near-white. fg is its inverse.
private enum ToastPalette {
    static let background = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.96, alpha: 1)
            : UIColor(red: 20 / 255, green: 20 / 255, blue: 24 / 255, alpha: 0.92)
    }
    static let foreground = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 20 / 255, green: 20 / 255, blue: 24 / 255, alpha: 1)
            : .white
    }
}

/// Shared toast capsule (fully-rounded pill via `Capsule`, 12pt, inverted background).
private struct ToastCapsule<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(uiColor: ToastPalette.foreground))
            .lineLimit(1)
            .fixedSize()                       // prevent the hosting view's horizontal squish = text clipping
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color(uiColor: ToastPalette.background), in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }
}

/// Hosting controller that delays the bottom-edge system gestures (home-indicator side swipe = app
/// switching, and the up swipe) by one beat. Lets the capture button at the bottom of the report's
/// trimmer be scrubbed via bottom-edge dragging without the OS hijacking the gesture (it requires a
/// second swipe to fire).
private final class DeferBottomGesturesHostingController<Content: View>: UIHostingController<Content> {
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }
}

#else
/// No-op stub for environments without UIKit / SwiftUI (e.g. macOS host builds).
final class FlashbackPresenter {
    var onDeferredInstall: (() -> Void)?
    func install() {}
    func uninstall() {}
    func presentReport(
        clipURL: URL?,
        onShare: @escaping (String, ClosedRange<Double>?) async -> URL?,
        settings: FlashbackSettingsStore
    ) {}
    func dismissReport() {}
    func presentPriming(onProceed: @escaping () -> Void, onLater: @escaping () -> Void) {}
    func presentShakeHint() {}
    func showProgress(_ message: String) {}
    func showFailure(_ message: String, onRetry: @escaping () -> Void) {}
    func showInfo(_ message: String, duration: TimeInterval = 1.8) {}
    func hideToast() {}
    func hideProgressToast() {}
}
#endif
