#if canImport(AVFoundation)
import AVFoundation

/// 書き出し済みクリップを指定範囲へ切り出すヘルパー。
///
/// `AVAssetExportSession`(passthrough) で無劣化に切り出す。passthrough は
/// キーフレーム境界にスナップしうる（数フレームの誤差）が、再エンコードを避けて
/// 高速・無劣化を優先する PoC 方針に合う。
/// タイトル等のメタデータ焼き込みや、出力ファイル名の指定にも対応する。
enum ClipTrimmer {

    /// 秒指定の利便版。`fromSeconds`〜`toSeconds` の範囲に切り出す。
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

    /// `source` を `range` の範囲に切り出した新しい mp4 を返す。
    /// - `metadata` が空かつ範囲が全体をほぼ覆う場合は、切り出さず元の URL を返す（無駄な再書き出し回避）。
    /// - `metadata` を渡した場合は、フル範囲でもメタデータ焼き込みのため必ず書き出す。
    /// - `outputName` を渡すと出力ファイル名（拡張子なし）に使う。共有時のファイル名になる。
    static func trim(
        _ source: URL,
        to range: CMTimeRange,
        metadata: [AVMetadataItem] = [],
        outputName: String? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let fullDuration = try await asset.load(.duration)

        // 実質フル選択（先頭付近開始＋終端付近終了）かどうか。
        let epsilon = CMTime(value: 1, timescale: 2)   // 0.5s
        let startsAtHead = range.start <= epsilon
        let endsAtTail = CMTimeAdd(range.end, epsilon) >= fullDuration
        let isFullRange = startsAtHead && endsAtTail

        // 切り出し不要かつメタデータも無いなら、再書き出しせず元を返す。
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
        try? FileManager.default.removeItem(at: outURL)   // 同名衝突を避ける

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

    /// タイトル / 説明を mp4 共通メタデータとして組み立てる。
    /// title は QuickTime インスペクタや Spotlight(`kMDItemTitle`) に表示される。
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

    /// 文字列をファイル名向けに無害化する。パス区切り/改行などを除き、長すぎる場合は丸める。
    /// 空になる場合は時刻入りの既定名へフォールバック（呼び出し側で必要なら差し替え可）。
    static func sanitizedFileName(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = raw.components(separatedBy: illegal)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = String(cleaned.prefix(60))
        return trimmed.isEmpty ? "Flashback" : trimmed
    }

    /// タイトル未入力時のファイル名フォールバック。種別（"video" / "screenshot"）と日時で、
    /// 何の共有物か一目で分かり、かつ同日複数でも被らないようにする（例: `flashback-video-20260606-153045`）。
    static func fallbackName(kind: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "flashback-\(kind)-\(f.string(from: Date()))"
    }
}
#endif
