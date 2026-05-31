#if DEBUG && canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import UIKit

/// DEBUG 専用: トリミング UX を Simulator で確認するための合成サンプル動画ジェネレータ。
///
/// ReplayKit の実録画は Simulator で動かないため、本物のクリップが手に入らない。
/// 経過秒を大きく描画し背景色を時間で変える動画を合成することで、再生・トリム範囲の
/// 効きを目視で確認できる。Release ビルドには含まれない。
enum SampleClipMaker {

    static func make(seconds: Int = 12, fps: Int = 15) async throws -> URL {
        let size = CGSize(width: 540, height: 960)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flashback-sample-\(UUID().uuidString).mp4")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw FlashbackError.clipTrimFailed }
        writer.add(input)
        guard writer.startWriting() else { throw FlashbackError.clipTrimFailed }
        writer.startSession(atSourceTime: .zero)

        let total = seconds * fps
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let renderer = UIGraphicsImageRenderer(size: size)

        for i in 0..<total {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            let t = Double(i) / Double(fps)
            let image = renderer.image { ctx in
                let hue = CGFloat((t.truncatingRemainder(dividingBy: 6)) / 6)
                UIColor(hue: hue, saturation: 0.55, brightness: 0.92, alpha: 1).setFill()
                ctx.fill(CGRect(origin: .zero, size: size))

                // 進行バー（左→右）。
                UIColor.white.withAlphaComponent(0.85).setFill()
                let barX = CGFloat(t / Double(seconds)) * size.width
                ctx.fill(CGRect(x: barX - 4, y: 0, width: 8, height: size.height))

                // 経過秒テキスト。
                let text = String(format: "%.1fs", t) as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 110, weight: .bold),
                    .foregroundColor: UIColor.black,
                ]
                let ts = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2),
                          withAttributes: attrs)
            }
            guard let pb = Self.pixelBuffer(from: image, size: size) else { continue }
            adaptor.append(pb, withPresentationTime: CMTimeMultiply(frameDuration, multiplier: Int32(i)))
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? FlashbackError.clipTrimFailed
        }
        return url
    }

    private static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, Int(size.width), Int(size.height),
            kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pb
        )
        guard status == kCVReturnSuccess, let pixelBuffer = pb, let cg = image.cgImage else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(origin: .zero, size: size))
        return pixelBuffer
    }
}
#endif
