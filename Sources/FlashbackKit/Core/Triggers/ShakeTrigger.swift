#if canImport(UIKit) && canImport(CoreMotion)
import CoreMotion

/// 加速度センサ（`CMMotionManager`）でシェイクを検知し `onTrigger` を呼ぶ。
///
/// 設計判断: motion イベント（`UIWindow.motionEnded`）は **key window のレスポンダ
/// チェーン**にしか配送されない。FlashbackKit の overlay window は意図的に非 key
/// （ホスト干渉ゼロ）なので motionEnded では拾えない。さらに overlay を key 化すると
/// ホストのキーボード / shake-to-undo を奪い、モーダル提示中・テキスト編集中
/// （＝まさにバグ報告したい場面）でこそ発火しなくなる。CoreMotion はレスポンダ
/// チェーンに一切触れず、ホストの UI 状態によらず確実に発火するため採用した。
///
/// しきい値判定は `ShakeEvaluator`（純粋ロジック）へ分離し単体テスト可能にしている。
@MainActor
final class ShakeTrigger: TriggerDetecting {
    var onTrigger: (() -> Void)?

    private let motionManager = CMMotionManager()
    private let queue: OperationQueue
    private let evaluator = ShakeEvaluator()

    init() {
        let queue = OperationQueue()
        queue.name = "FlashbackKit.ShakeTrigger"
        queue.maxConcurrentOperationCount = 1   // 直列: evaluator の状態をこのキューに閉じ込める
        self.queue = queue
    }

    /// 加速度の購読を開始する。利用不可（Simulator 等）なら何もしない。
    func start() {
        guard motionManager.isAccelerometerAvailable else { return }
        guard !motionManager.isAccelerometerActive else { return }

        evaluator.reset()
        motionManager.accelerometerUpdateInterval = 1.0 / 20.0   // 20Hz

        // ハンドラは `queue`（非 MainActor・直列）で走る。evaluator はこのキュー内
        // からのみ触り、検知時だけ MainActor へホップして `onTrigger` を呼ぶ。
        //
        // 重要: `@Sendable` を**必ず**明示する。`CMAccelerometerHandler` は SDK 側で
        // @Sendable 型になっておらず、@MainActor クラス内で書くとクロージャが
        // @MainActor 隔離と推論される。すると CoreMotion が背景キューで呼んだ瞬間に
        // 「main で実行されるはず」と食い違い `dispatch_assert_queue` で即クラッシュ
        // する（ReplayKit startCapture と同型の罠。commit 64cdf9d 参照）。コンパイラは
        // 同一隔離で呼ぶ前提なので警告も出ず、実機でしか露見しない。
        motionManager.startAccelerometerUpdates(to: queue) { @Sendable [weak self, evaluator] data, _ in
            guard let data else { return }
            let a = data.acceleration
            guard evaluator.process(x: a.x, y: a.y, z: a.z, timestamp: data.timestamp) else { return }
            Task { @MainActor in self?.onTrigger?() }
        }
    }

    /// 購読を停止し、コールバックを解除する。
    func stop() {
        motionManager.stopAccelerometerUpdates()
        onTrigger = nil
    }
}

/// シェイク判定の純粋ロジック。`ShakeTrigger` の直列キューからのみ呼ばれる前提で
/// 内部状態を持つ（その不変条件のもとで `@unchecked Sendable`）。
///
/// 単発の衝撃（落下・タップ・ポケット出し入れ）での誤検知を避けるため、一定の時間窓
/// 内に複数回の加速度ピークが立ったときだけシェイクと判定し、発火後はクールダウンを
/// 置いて連続発火を防ぐ。しきい値はチューニング前提の控えめな既定値。
final class ShakeEvaluator: @unchecked Sendable {
    private let peakThreshold: Double   // この g を超えたら 1 ピークとみなす
    private let rearmThreshold: Double  // この g を下回ったら次のピークを数え始める
    private let window: TimeInterval    // ピークを数える時間窓（秒）
    private let cooldown: TimeInterval  // 発火後の無視期間（秒）
    private let requiredPeaks: Int      // シェイク成立に必要なピーク数

    private var armed = true
    private var peakCount = 0
    private var firstPeakAt: TimeInterval = 0
    private var lastFireAt: TimeInterval = -.greatestFiniteMagnitude

    init(
        peakThreshold: Double = 2.3,
        rearmThreshold: Double = 1.3,
        window: TimeInterval = 1.0,
        cooldown: TimeInterval = 1.5,
        requiredPeaks: Int = 2
    ) {
        self.peakThreshold = peakThreshold
        self.rearmThreshold = rearmThreshold
        self.window = window
        self.cooldown = cooldown
        self.requiredPeaks = requiredPeaks
    }

    /// 状態を初期化する（購読開始時に呼ぶ）。
    func reset() {
        armed = true
        peakCount = 0
        firstPeakAt = 0
        lastFireAt = -.greatestFiniteMagnitude
    }

    /// 加速度 1 サンプルを与え、シェイク成立で `true` を返す。
    /// - Parameters:
    ///   - x: X 軸加速度（g, 重力込み）。
    ///   - y: Y 軸加速度（g, 重力込み）。
    ///   - z: Z 軸加速度（g, 重力込み）。
    ///   - timestamp: 単調増加タイムスタンプ（秒）。`CMAccelerometerData.timestamp` 等。
    func process(x: Double, y: Double, z: Double, timestamp: TimeInterval) -> Bool {
        // 発火直後のクールダウン中は数えない（連続発火・反動ピークの抑制）。
        if timestamp - lastFireAt < cooldown { return false }

        let magnitude = (x * x + y * y + z * z).squareRoot()

        // 静止〜弱い加速度まで戻ったら次のピークを数えられるよう再武装する。
        if magnitude < rearmThreshold {
            armed = true
            return false
        }

        // ピーク未満、または同一ピークの継続（再武装前）は無視。
        guard magnitude >= peakThreshold, armed else { return false }
        armed = false

        // 時間窓を超えていたら数え直す。
        if peakCount == 0 || timestamp - firstPeakAt > window {
            peakCount = 1
            firstPeakAt = timestamp
        } else {
            peakCount += 1
        }

        if peakCount >= requiredPeaks {
            lastFireAt = timestamp
            peakCount = 0
            return true
        }
        return false
    }
}
#else
final class ShakeTrigger: TriggerDetecting {
    var onTrigger: (() -> Void)?
    func start() {}
    func stop() {}
}
#endif
