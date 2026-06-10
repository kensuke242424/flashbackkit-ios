#if canImport(ReplayKit)
import XCTest
import AVFoundation
import CoreMedia
import ImageIO
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

    /// 寸法変化（回転）がセグメント境界をまたいで起きるケース。
    /// 64x64 を 2 秒（=セグメント境界）流した後に 120x64 へ切り替えると、
    /// 旧寸法セグメントは破棄され、出力は新寸法ぶんのみになる。
    func testSizeChangeAcrossSegmentBoundaryResetsRing() async throws {
        let writer = SegmentRingWriter(bufferSeconds: 3)   // segmentDuration=2, maxSegments=3
        let fps = 10
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        // 前半: 64x64 を 20 フレーム（2 秒 = セグメント境界ちょうど）。
        // 後半: 120x64 を 10 フレーム（1 秒）。PTS は通しで連続させる。
        let firstCount = 20
        let secondCount = 10
        for i in 0..<(firstCount + secondCount) {
            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            let isSecond = i >= firstCount
            let width = isSecond ? 120 : 64
            let pixelBuffer = try makePixelBuffer(width: width, height: 64, frameIndex: i)
            let sampleBuffer = try makeSampleBuffer(pixelBuffer: pixelBuffer, pts: pts, duration: frameDuration)
            writer.ingest(sampleBuffer, type: .video)
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let url = try await writer.export()
        defer { writer.teardown(); try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first, "video トラックが無い")
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 120, "naturalSize.width が新寸法でない: \(size.width)")
        XCTAssertEqual(size.height, 64, "naturalSize.height が新寸法でない: \(size.height)")

        // 旧 64x64 セグメントが捨てられている証拠として、尺は後半（≒1.0s）ぶんのみ。
        let seconds = CMTimeGetSeconds(try await asset.load(.duration))
        XCTAssertLessThan(seconds, 1.6, "旧寸法セグメントが残っている疑い（尺が長すぎ）: \(seconds)s")
    }

    /// 寸法変化が同一セグメント途中で起きるケース。
    /// 64x64 を 1 秒（セグメント未完）流した直後に 120x64 へ切り替えると、
    /// 書き込み中セグメントは cancel され、出力は新寸法のみになる。
    func testSizeChangeWithinSegmentResetsRing() async throws {
        let writer = SegmentRingWriter(bufferSeconds: 3)   // segmentDuration=2, maxSegments=3
        let fps = 10
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        let firstCount = 10                                // 1 秒（segmentDuration=2 未満 = セグメント途中）
        let secondCount = 10
        for i in 0..<(firstCount + secondCount) {
            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            let isSecond = i >= firstCount
            let width = isSecond ? 120 : 64
            let pixelBuffer = try makePixelBuffer(width: width, height: 64, frameIndex: i)
            let sampleBuffer = try makeSampleBuffer(pixelBuffer: pixelBuffer, pts: pts, duration: frameDuration)
            writer.ingest(sampleBuffer, type: .video)
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let url = try await writer.export()
        defer { writer.teardown(); try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first, "video トラックが無い")
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 120, "naturalSize.width が新寸法でない: \(size.width)")
        XCTAssertEqual(size.height, 64, "naturalSize.height が新寸法でない: \(size.height)")
    }

    /// 同寸法のまま orientation 添付だけが途中で .up→.right に変わるケース（実機の回転挙動）。
    /// ReplayKit は実機で寸法を変えず RPVideoSampleOrientationKey の値だけを切り替えるので、
    /// 寸法シグナルでは捕まらない。orientation 変化でリングがリセットされ（出力は後半ぶんのみ）、
    /// かつ出力トラックの preferredTransform が非 identity で「表示サイズの W/H が入れ替わる」ことを確認。
    func testOrientationChangeResetsRingAndAppliesUprightTransform() async throws {
        let writer = SegmentRingWriter(bufferSeconds: 3)   // segmentDuration=2, maxSegments=3
        let fps = 10
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        // 前半: 64x48 を 20 フレーム（2 秒）添付なし（= 実効 .up）。
        // 後半: 同寸 64x48 を 10 フレーム（1 秒）、orientation=.right を添付。
        // 寸法は終始同一なので、リセットの引き金になるのは orientation 変化のみ。
        let firstCount = 20
        let secondCount = 10
        let w = 64, h = 48
        for i in 0..<(firstCount + secondCount) {
            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            let isSecond = i >= firstCount
            let pixelBuffer = try makePixelBuffer(width: w, height: h, frameIndex: i)
            let orientation: CGImagePropertyOrientation? = isSecond ? .right : nil
            let sampleBuffer = try makeSampleBuffer(pixelBuffer: pixelBuffer, pts: pts,
                                                    duration: frameDuration, orientation: orientation)
            writer.ingest(sampleBuffer, type: .video)
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let url = try await writer.export()
        defer { writer.teardown(); try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first, "video トラックが無い")

        // 1) 旧 .up セグメントが捨てられている証拠として、尺は後半（≒1.0s）ぶんのみ。
        let seconds = CMTimeGetSeconds(try await asset.load(.duration))
        XCTAssertLessThan(seconds, 1.6, "orientation 変化前のセグメントが残っている疑い（尺が長すぎ）: \(seconds)s")

        // 2) preferredTransform が .right の正立化（90°回転）になっている＝非 identity。
        let transform = try await track.load(.preferredTransform)
        XCTAssertNotEqual(transform, .identity, "orientation 変化後も transform が identity のまま（正立化されていない）")

        // 3) naturalSize に transform を適用した「表示サイズ」が W/H 入れ替わる（64x48 → 48x64 相当）。
        let natural = try await track.load(.naturalSize)
        let displayed = natural.applying(transform)
        XCTAssertEqual(abs(displayed.width), CGFloat(h), accuracy: 0.5, "表示幅が H と入れ替わっていない")
        XCTAssertEqual(abs(displayed.height), CGFloat(w), accuracy: 0.5, "表示高さが W と入れ替わっていない")

        // 4) 期待の回転行列（+90°）であることを固定。a≈0, b≈1, c≈-1, d≈0。
        XCTAssertEqual(transform.a, 0, accuracy: 0.001)
        XCTAssertEqual(transform.b, 1, accuracy: 0.001)
        XCTAssertEqual(transform.c, -1, accuracy: 0.001)
        XCTAssertEqual(transform.d, 0, accuracy: 0.001)
    }

    /// 全フレーム .up（添付あり）のケース。orientation が一定なのでリセットは起きず、
    /// 出力トラックの preferredTransform は identity（= 既存の縦持ち録画の挙動が不変）。
    func testUprightOrientationKeepsIdentityTransform() async throws {
        let writer = SegmentRingWriter(bufferSeconds: 3)   // segmentDuration=2, maxSegments=3
        let fps = 10
        let total = 30                                     // 3 秒
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        for i in 0..<total {
            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            let pixelBuffer = try makePixelBuffer(width: 48, height: 64, frameIndex: i)
            let sampleBuffer = try makeSampleBuffer(pixelBuffer: pixelBuffer, pts: pts,
                                                    duration: frameDuration, orientation: .up)
            writer.ingest(sampleBuffer, type: .video)
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let url = try await writer.export()
        defer { writer.teardown(); try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first, "video トラックが無い")

        // 添付ありでも .up は identity（既存挙動不変）。
        let transform = try await track.load(.preferredTransform)
        XCTAssertEqual(transform, .identity, ".up なのに transform が identity でない（既存挙動が変わっている）")

        // リセットが起きていない＝尺が 3 秒ぶん（リング上限）程度に収まる。
        let seconds = CMTimeGetSeconds(try await asset.load(.duration))
        XCTAssertGreaterThan(seconds, 1.0, "尺が短すぎる（不要なリセットが起きた疑い）: \(seconds)s")
    }

    /// ClipTrimmer の passthrough 切り出しが preferredTransform を保持することの確認。
    /// 直接 asset を渡す timeRange export はトラックのメタデータ（transform 含む）を引き継ぐ。
    /// composeAndExport が焼いた正立 transform が、共有前のトリムで失われないことを担保する。
    func testClipTrimmerPreservesPreferredTransform() async throws {
        // composeAndExport を通って .right の正立 transform を持つクリップを作る。
        let writer = SegmentRingWriter(bufferSeconds: 3)
        let fps = 10
        let total = 20                                     // 2 秒
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        for i in 0..<total {
            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            let pixelBuffer = try makePixelBuffer(width: 64, height: 48, frameIndex: i)
            let sampleBuffer = try makeSampleBuffer(pixelBuffer: pixelBuffer, pts: pts,
                                                    duration: frameDuration, orientation: .right)
            writer.ingest(sampleBuffer, type: .video)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let source = try await writer.export()
        defer { writer.teardown(); try? FileManager.default.removeItem(at: source) }

        let sourceTransform = try await AVURLAsset(url: source)
            .loadTracks(withMediaType: .video).first!.load(.preferredTransform)
        XCTAssertNotEqual(sourceTransform, .identity, "前提: 元クリップは非 identity transform を持つはず")

        // 部分範囲に切り出す（passthrough）。transform が保持されることを確認。
        let trimmed = try await ClipTrimmer.trim(source, fromSeconds: 0.3, toSeconds: 1.3)
        defer { if trimmed != source { try? FileManager.default.removeItem(at: trimmed) } }
        XCTAssertNotEqual(trimmed, source, "部分範囲なのに切り出されていない")

        let trimmedTransform = try await AVURLAsset(url: trimmed)
            .loadTracks(withMediaType: .video).first!.load(.preferredTransform)
        XCTAssertEqual(trimmedTransform, sourceTransform, "トリム後に preferredTransform が失われている")
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

    /// `orientation` を渡すと RPVideoSampleOrientationKey 添付（CGImagePropertyOrientation
    /// rawValue の NSNumber）を `CMSetAttachment` で付与する。nil なら添付なし（= 実効 .up）。
    /// ReplayKit は Simulator でも import できるため、添付キーの利用自体は Sim 上で検証できる。
    private func makeSampleBuffer(pixelBuffer: CVPixelBuffer, pts: CMTime, duration: CMTime,
                                  orientation: CGImagePropertyOrientation? = nil) throws -> CMSampleBuffer {
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
        if let orientation {
            CMSetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString,
                            value: NSNumber(value: orientation.rawValue),
                            attachmentMode: kCMAttachmentMode_ShouldPropagate)
        }
        return sampleBuffer
    }
}
#endif
