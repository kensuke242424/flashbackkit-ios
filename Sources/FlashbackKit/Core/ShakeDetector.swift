#if canImport(UIKit)
import UIKit

@MainActor
final class ShakeDetector {
    var onShake: (() -> Void)?

    func start() {
        // TODO: シェイク検知。候補:
        // - UIWindow.motionEnded(_:with:) を swizzling
        // - 専用 UIWindow サブクラス
        // - CMMotionManager で閾値検出
    }

    func stop() {
        onShake = nil
    }
}
#else
final class ShakeDetector {
    var onShake: (() -> Void)?
    func start() {}
    func stop() {}
}
#endif
