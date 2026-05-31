#if canImport(AVFoundation)
import AVFoundation

/// 書き出し済みクリップを指定範囲へ切り出すヘルパー。
///
/// `AVAssetExportSession`(passthrough) で無劣化に切り出す。passthrough は
/// キーフレーム境界にスナップしうる（数フレームの誤差）が、再エンコードを避けて
/// 高速・無劣化を優先する PoC 方針に合う。
enum ClipTrimmer {

    /// 秒指定の利便版。`fromSeconds`〜`toSeconds` の範囲に切り出す。
    static func trim(_ source: URL, fromSeconds: Double, toSeconds: Double) async throws -> URL {
        let start = CMTime(seconds: max(0, fromSeconds), preferredTimescale: 600)
        let end = CMTime(seconds: max(fromSeconds, toSeconds), preferredTimescale: 600)
        return try await trim(source, to: CMTimeRange(start: start, end: end))
    }

    /// `source` を `range` の範囲に切り出した新しい mp4 を返す。
    /// 範囲が全体をほぼ覆う場合は切り出さず元の URL をそのまま返す（無駄な再書き出し回避）。
    static func trim(_ source: URL, to range: CMTimeRange) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let fullDuration = try await asset.load(.duration)

        // 実質フル選択（先頭付近開始＋終端付近終了）なら切り出さない。
        let epsilon = CMTime(value: 1, timescale: 2)   // 0.5s
        let startsAtHead = range.start <= epsilon
        let endsAtTail = CMTimeAdd(range.end, epsilon) >= fullDuration
        if startsAtHead && endsAtTail {
            return source
        }

        guard range.duration > .zero,
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw FlashbackError.clipTrimFailed
        }

        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flashback-trim-\(UUID().uuidString).mp4")
        session.outputURL = outURL
        session.outputFileType = .mp4
        session.timeRange = range

        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            throw session.error ?? FlashbackError.clipTrimFailed
        }
        return outURL
    }
}
#endif
