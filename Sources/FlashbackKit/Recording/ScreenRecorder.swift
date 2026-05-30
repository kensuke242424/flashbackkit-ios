#if canImport(ReplayKit)
import ReplayKit

/// ReplayKit のアプリ内キャプチャ上に作るリングバッファ。
///
/// 重要: ReplayKit は「遡って録画」できない。直前 N 秒を残すには
/// startBuffering から常時キャプチャを回し、直近 N 秒分の
/// CMSampleBuffer だけ保持して古いものは捨て続ける必要がある。
/// キャプチャ開始時にセッション毎 1 回、システムの許可プロンプトが出る。
@MainActor
final class ScreenRecorder {
    func startBuffering(seconds: TimeInterval) {
        // TODO: RPScreenRecorder.shared().startCapture(handler:) で
        //       直近 seconds 秒の CMSampleBuffer をリング保持。
    }

    func stopBuffering() {
        // TODO: RPScreenRecorder.shared().stopCapture()
    }

    /// 現在のバッファを一時 .mp4 に書き出して URL を返す。
    func exportBufferedClip() async throws -> URL {
        // TODO: 保持中の sample buffer を AVAssetWriter で書き出し。
        throw FlashbackError.notImplemented
    }
}
#else
final class ScreenRecorder {
    func startBuffering(seconds: TimeInterval) {}
    func stopBuffering() {}
    func exportBufferedClip() async throws -> URL { throw FlashbackError.notImplemented }
}
#endif
