#if canImport(ReplayKit)
import XCTest
import AVFoundation
import CoreMedia
import ReplayKit
@testable import FlashbackKit

/// ReplayKit（録画ソース）は Simulator で動かないが、その先の
/// 「AVAssetWriter セグメント回転 → composition マージ → passthrough 書き出し」は
/// AVFoundation だけで完結するため Simulator 上で検証できる。
///
/// 合成フレーム（色が変わる CVPixelBuffer + 連続 PTS）を `SegmentRingWriter` に流し、
/// 再生可能な mp4 が実際に書き出されることを確認する。
final class ScreenRecorderPipelineTests: XCTestCase {

    func testExportProducesPlayableClip() async throws {
        let writer = SegmentRingWriter(bufferSeconds: 3)   // segmentDuration=2, maxSegments=3

        // 10fps で 3 秒分（30 フレーム）。2 秒境界でセグメント回転が 1 回起きる。
        // expectsMediaDataInRealTime=true（ライブ供給向け）に合わせ、実機同様に
        // 実時間ペースで流す（一気に詰めると isReadyForMoreMediaData で大量ドロップする）。
        let fps = 10
        let total = 30
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        for i in 0..<total {
            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            let pixelBuffer = try makePixelBuffer(width: 64, height: 64, frameIndex: i)
            let sampleBuffer = try makeSampleBuffer(pixelBuffer: pixelBuffer, pts: pts, duration: frameDuration)
            writer.ingest(sampleBuffer, type: .video)
            try await Task.sleep(nanoseconds: 100_000_000)   // ≒ フレーム間隔
        }

        // ingest は writer のシリアルキューへ async 投入。export も同じキューで
        // finalize/snapshot するため、投入済み append の後に直列実行される。
        let url = try await writer.export()

        // 1) ファイルが実在する
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "書き出しファイルが無い")

        // 2) 再生可能な mp4（video トラックあり・実体のある尺）
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty, "video トラックが無い")
        let seconds = CMTimeGetSeconds(try await asset.load(.duration))
        XCTAssertGreaterThan(seconds, 1.0, "尺が短すぎる（セグメント回転/マージ失敗の疑い）: \(seconds)s")

        // 3) リングが効いていて bufferSeconds(+セグメント1本) 程度に収まる
        XCTAssertLessThan(seconds, 8.0, "尺が想定より長い（リング trim が効いていない疑い）: \(seconds)s")

        writer.teardown()
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 合成フレーム生成

    private func makePixelBuffer(width: Int, height: Int, frameIndex: Int) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb
        )
        guard status == kCVReturnSuccess, let pixelBuffer = pb else {
            throw XCTSkip("CVPixelBuffer を生成できない環境")
        }

        // フレーム毎に色を変える（中身が同一だと一部エンコーダが省略しうるため）。
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let value = UInt8(truncatingIfNeeded: frameIndex * 4)
            memset(base, Int32(value), bytesPerRow * height)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }

    private func makeSampleBuffer(pixelBuffer: CVPixelBuffer, pts: CMTime, duration: CMTime) throws -> CMSampleBuffer {
        var formatDesc: CMVideoFormatDescription?
        let fmtStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDesc
        )
        guard fmtStatus == noErr, let formatDesc else {
            throw XCTSkip("FormatDescription を生成できない環境")
        }

        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        let sbStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sbStatus == noErr, let sampleBuffer else {
            throw XCTSkip("CMSampleBuffer を生成できない環境")
        }
        return sampleBuffer
    }
}
#endif
