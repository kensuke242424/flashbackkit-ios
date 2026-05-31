#if canImport(AVFoundation)
import XCTest
import AVFoundation
@testable import FlashbackKit

/// `ClipTrimmer` の切り出し検証。合成フレームで素材 mp4 を作り、部分範囲に
/// 切り出した結果の尺が選択範囲に近いことを確認する（Simulator 上で完結）。
final class ClipTrimmerTests: XCTestCase {

    func testTrimProducesShorterClipForSubRange() async throws {
        let source = try await makeTestClip(seconds: 6, fps: 30)
        defer { try? FileManager.default.removeItem(at: source) }

        // 2.0s〜5.0s（3秒）に切り出す。
        let range = CMTimeRange(
            start: CMTime(seconds: 2, preferredTimescale: 600),
            duration: CMTime(seconds: 3, preferredTimescale: 600)
        )
        let trimmed = try await ClipTrimmer.trim(source, to: range)
        defer { if trimmed != source { try? FileManager.default.removeItem(at: trimmed) } }

        XCTAssertNotEqual(trimmed, source, "部分範囲なのに切り出されていない")
        let seconds = try await CMTimeGetSeconds(AVURLAsset(url: trimmed).load(.duration))
        // passthrough はキーフレーム境界にスナップしうるので緩めに判定。
        XCTAssertGreaterThan(seconds, 1.5, "切り出し尺が短すぎる: \(seconds)s")
        XCTAssertLessThan(seconds, 4.5, "切り出し尺が長すぎる（範囲が効いていない）: \(seconds)s")
    }

    func testFullRangeReturnsSourceUnchanged() async throws {
        let source = try await makeTestClip(seconds: 4, fps: 30)
        defer { try? FileManager.default.removeItem(at: source) }

        let full = try await CMTimeGetSeconds(AVURLAsset(url: source).load(.duration))
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: full, preferredTimescale: 600))
        let result = try await ClipTrimmer.trim(source, to: range)

        XCTAssertEqual(result, source, "フル選択では元 URL をそのまま返すべき")
    }

    // MARK: - 合成素材

    /// 単一トラックの mp4 を AVAssetWriter で合成する。
    private func makeTestClip(seconds: Int, fps: Int) async throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flashback-test-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw XCTSkip("AVAssetWriterInput を追加できない環境") }
        writer.add(input)
        guard writer.startWriting() else { throw XCTSkip("startWriting 失敗") }
        writer.startSession(atSourceTime: .zero)

        let total = seconds * fps
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        for i in 0..<total {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            let pixelBuffer = try makePixelBuffer(width: 64, height: 64, frameIndex: i)
            adaptor.append(pixelBuffer, withPresentationTime: pts)
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw XCTSkip("テスト素材の書き出し失敗: \(String(describing: writer.error))") }
        return url
    }

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
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let value = UInt8(truncatingIfNeeded: frameIndex * 4)
            memset(base, Int32(value), bytesPerRow * height)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }
}
#endif
