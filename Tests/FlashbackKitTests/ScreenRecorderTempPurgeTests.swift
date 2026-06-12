#if canImport(ReplayKit)
import XCTest
@testable import FlashbackKit

/// 一時ファイル purge のライフサイクル検証。
///
/// `purgeTempFiles()` は「前回起動の残骸（flashback-*）掃除」が目的だが、かつて
/// `startBuffering` 経由で**復帰のたび**走っていたため、バックグラウンド復帰の再開
/// （didBecomeActive → startBuffering）が表示中 ReportView の書き出し済みクリップまで
/// 削除し、保存・共有が死んだ URL を掴むバグがあった。purge はプロセスごとに 1 回だけ
/// であることを検証する。
///
/// Simulator では ReplayKit が動かず `isAvailable` は false だが、purge は availability
/// ガードより前に実行されるため、この検証は Simulator 上で完結する。
final class ScreenRecorderTempPurgeTests: XCTestCase {

    /// 復帰時の再開（2 回目以降の startBuffering）が、書き出し済みクリップを消さないこと。
    @MainActor
    func testResumeRestartDoesNotPurgeExportedClip() throws {
        let recorder = ScreenRecorder()

        // 1 回目の startBuffering（プロセス初回の purge をここで消費する。
        // 他テストが先に消費済みでも、以降の検証は同じ意味で成立する）。
        recorder.startBuffering(seconds: 5)
        recorder.stopBuffering()

        // export 済みクリップ（ReportView が掴んでいる想定）を模したファイルを置く。
        let clip = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flashback-\(UUID().uuidString).mp4")
        try Data("clip".utf8).write(to: clip)
        defer { try? FileManager.default.removeItem(at: clip) }

        // バックグラウンド復帰の再開に相当する 2 回目の startBuffering。
        recorder.startBuffering(seconds: 5)
        recorder.stopBuffering()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: clip.path),
            "復帰時の再開で書き出し済みクリップが purge された（保存・共有が壊れる）"
        )
    }
}
#endif
