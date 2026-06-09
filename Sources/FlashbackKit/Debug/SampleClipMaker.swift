#if DEBUG && canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import UIKit

/// DEBUG-only: synthetic sample-clip generator for checking the trimming UX on the Simulator.
///
/// Real ReplayKit recording doesn't run on the Simulator, so no genuine clip is available.
/// This synthesizes a video that draws the elapsed seconds large and shifts the background
/// color over time, letting you visually confirm playback and trim-range behavior. Not
/// included in Release builds.
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

                // Progress bar (left -> right).
                UIColor.white.withAlphaComponent(0.85).setFill()
                let barX = CGFloat(t / Double(seconds)) * size.width
                ctx.fill(CGRect(x: barX - 4, y: 0, width: 8, height: size.height))

                // Elapsed-seconds text.
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
