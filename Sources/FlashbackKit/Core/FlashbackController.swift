import Foundation

/// 各責務（録画 / シェイク検知 / レポート / 送信）を束ねる調整役。
@MainActor
final class FlashbackController {
    static let shared = FlashbackController()

    private var configuration = FlashbackConfiguration()
    private let recorder = ScreenRecorder()
    private let shakeDetector = ShakeDetector()

    private init() {}

    func start(configuration: FlashbackConfiguration) {
        self.configuration = configuration
        guard configuration.isEnabled else { return }

        recorder.startBuffering(seconds: configuration.bufferSeconds)
        shakeDetector.onShake = { [weak self] in
            self?.handleShake()
        }
        shakeDetector.start()
    }

    func stop() {
        shakeDetector.stop()
        recorder.stopBuffering()
    }

    private func handleShake() {
        // TODO: 直前 N 秒を書き出し -> ReportView 表示
        //       -> ReportGenerator -> SlackNotifier へ受け渡す
    }
}
