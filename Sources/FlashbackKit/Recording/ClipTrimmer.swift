#if canImport(AVFoundation)
import AVFoundation

/// Helper that cuts an exported clip down to a given range.
///
/// Uses `AVAssetExportSession` (passthrough) for a lossless cut. Passthrough may snap to
/// keyframe boundaries (a few frames of error), but avoiding re-encode keeps it fast and
/// lossless, which suits the PoC. Also supports burning in metadata (title, etc.) and a custom output name.
enum ClipTrimmer {

    /// Convenience seconds-based variant. Cuts the `fromSeconds`...`toSeconds` range.
    static func trim(
        _ source: URL,
        fromSeconds: Double,
        toSeconds: Double,
        metadata: [AVMetadataItem] = [],
        outputName: String? = nil
    ) async throws -> URL {
        let start = CMTime(seconds: max(0, fromSeconds), preferredTimescale: 600)
        let end = CMTime(seconds: max(fromSeconds, toSeconds), preferredTimescale: 600)
        return try await trim(source, to: CMTimeRange(start: start, end: end),
                              metadata: metadata, outputName: outputName)
    }

    /// Returns a new mp4 with `source` cut down to `range`.
    /// - If `metadata` is empty and the range covers nearly the whole asset, returns the source URL unchanged (avoids a pointless re-export).
    /// - If `metadata` is provided, always exports (even for the full range) to burn it in.
    /// - `outputName` (without extension) becomes the output file name, used as the share file name.
    static func trim(
        _ source: URL,
        to range: CMTimeRange,
        metadata: [AVMetadataItem] = [],
        outputName: String? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let fullDuration = try await asset.load(.duration)

        // Whether this is effectively a full selection (starts near head, ends near tail).
        let epsilon = CMTime(value: 1, timescale: 2)   // 0.5s
        let startsAtHead = range.start <= epsilon
        let endsAtTail = CMTimeAdd(range.end, epsilon) >= fullDuration
        let isFullRange = startsAtHead && endsAtTail

        // No cut needed and no metadata: return the source without re-exporting.
        if isFullRange && metadata.isEmpty {
            return source
        }

        guard range.duration > .zero,
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw FlashbackError.clipTrimFailed
        }

        let name = outputName.map(sanitizedFileName) ?? "flashback-trim-\(UUID().uuidString)"
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name).mp4")
        try? FileManager.default.removeItem(at: outURL)   // avoid same-name collision

        session.outputURL = outURL
        session.outputFileType = .mp4
        if !isFullRange {
            session.timeRange = range
        }
        if !metadata.isEmpty {
            session.metadata = metadata
        }

        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            throw session.error ?? FlashbackError.clipTrimFailed
        }
        return outURL
    }

    /// Builds title / description as mp4 common metadata.
    /// title shows up in the QuickTime inspector and Spotlight (`kMDItemTitle`).
    static func metadata(title: String?, description: String?) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        if let title, !title.isEmpty {
            items.append(makeItem(.commonIdentifierTitle, title))
        }
        if let description, !description.isEmpty {
            items.append(makeItem(.commonIdentifierDescription, description))
        }
        return items
    }

    private static func makeItem(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }

    /// Sanitizes a string for use as a file name: strips path separators / newlines etc. and clamps the length.
    /// Falls back to a default name when the result is empty (callers may override if needed).
    static func sanitizedFileName(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = raw.components(separatedBy: illegal)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = String(cleaned.prefix(60))
        return trimmed.isEmpty ? "Flashback" : trimmed
    }

    /// File-name fallback when no title was entered. Combines kind ("video" / "screenshot") with a timestamp
    /// so the artifact type is obvious at a glance and multiple shares on the same day don't collide
    /// (e.g. `flashback-video-20260606-153045`).
    static func fallbackName(kind: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "flashback-\(kind)-\(f.string(from: Date()))"
    }
}
#endif
