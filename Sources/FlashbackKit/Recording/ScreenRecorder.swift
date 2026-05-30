#if canImport(ReplayKit)
import ReplayKit
import AVFoundation

/// ReplayKit のアプリ内キャプチャ上に作るリングバッファ。
///
/// 重要: ReplayKit は「遡って録画」できない。直前 N 秒を残すには
/// startBuffering から常時キャプチャを回し、直近 N 秒分だけを
/// ディスク上のセグメントとして保持し古いものを捨て続ける。
/// キャプチャ開始時にセッション毎 1 回、システムの許可プロンプトが出る。
///
/// 設計: `@MainActor` の本型は呼び出し側契約（RPScreenRecorder 操作・可用性ゲート）
/// だけを担い、実際のエンコードは非 MainActor の `SegmentRingWriter` が専用シリアル
/// キュー上で行う。非 Sendable な `CMSampleBuffer` はメインに跳ねず、キャプチャの
/// 背景ハンドラから直接 writer のキューへ渡す。
@MainActor
final class ScreenRecorder {
    private let recorder = RPScreenRecorder.shared()
    private var ring: SegmentRingWriter?
    private var isCapturing = false

    func startBuffering(seconds: TimeInterval) {
        guard !isCapturing else { return }                 // 冪等
        SegmentRingWriter.purgeTempFiles()                 // 前回の残骸を掃除

        guard recorder.isAvailable else {                  // Simulator / 未対応
            FlashbackLog.lifecycle.info("画面録画は利用不可（Simulator か未対応環境）。clip なしで継続。")
            return                                         // throw しない。export 側で recordingUnavailable
        }

        recorder.isMicrophoneEnabled = false               // 映像のみ（mic 権限不要）
        let ring = SegmentRingWriter(bufferSeconds: seconds)
        self.ring = ring
        isCapturing = true

        recorder.startCapture(handler: { @Sendable sampleBuffer, bufferType, error in
            // 背景スレッドで呼ばれる。@Sendable で main-actor 隔離を外すこと。
            // 付けないとクロージャが @MainActor 隔離を継承し、ReplayKit が背景スレッドで
            // 呼んだ瞬間に "Block was expected to execute on queue [main-thread]" で trap する。
            // CMSampleBuffer は非 Sendable なので ingest 内で box 化して serial queue へ渡す。
            guard error == nil else { return }
            ring.ingest(sampleBuffer, type: bufferType)
        }, completionHandler: { @Sendable error in
            guard let error else { return }
            FlashbackLog.lifecycle.error("startCapture 失敗: \(error.localizedDescription, privacy: .public)")
            Task { @MainActor [weak self] in
                self?.isCapturing = false
                self?.ring?.teardown()
                self?.ring = nil
            }
        })
    }

    func stopBuffering() {
        guard isCapturing else { return }                  // 冪等
        isCapturing = false
        recorder.stopCapture { _ in }
        ring?.teardown()
        ring = nil
    }

    /// 現在のバッファを一時 .mp4 に書き出して URL を返す。
    func exportBufferedClip() async throws -> URL {
        guard let ring, isCapturing else { throw FlashbackError.recordingUnavailable }
        return try await ring.export()
    }
}

/// 非 Sendable な値を並行境界（`queue.async`）越しに運ぶ局所的エスケープハッチ。
/// ReplayKit からは所有権ごと受け取り、単一シリアルキューにのみ渡して他スレッドから
/// は触れないため安全。
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
}

/// 直近 N 秒を覆う mp4 セグメントの環を専用シリアルキュー上で維持し、書き出し時に
/// マージして 1 本の mp4 にする。可変状態は全て `queue` 上でのみ触れるため
/// `@unchecked Sendable`（実質シリアルアクター）。
///
/// `internal`（テストから合成フレームを流して書き出しパイプラインを検証するため）。
/// ReplayKit を使わず AVFoundation の経路だけを Simulator 上で検証できる。
final class SegmentRingWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FlashbackKit.SegmentRingWriter")
    private let segmentDuration: TimeInterval
    private let maxSegments: Int

    // 以下は queue 上でのみアクセスする。
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var currentSegmentStart: CMTime = .invalid
    private var segmentURLs: [URL] = []

    init(bufferSeconds: TimeInterval) {
        let seg = max(2, bufferSeconds / 6)                // 窓を ~6 分割
        self.segmentDuration = seg
        self.maxSegments = Int((bufferSeconds / seg).rounded(.up)) + 1   // 常に N 秒以上を確保
    }

    // MARK: - 取り込み

    func ingest(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType) {
        guard type == .video else { return }               // 映像のみ
        let box = UncheckedSendableBox(value: sampleBuffer)
        queue.async { [self] in append(box.value) }
    }

    private func append(_ sb: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sb) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)

        if writer == nil {
            startNewSegment(firstSample: sb, at: pts)
        } else if CMTimeGetSeconds(CMTimeSubtract(pts, currentSegmentStart)) >= segmentDuration {
            finalizeCurrent()
            startNewSegment(firstSample: sb, at: pts)
        }

        guard let writer, writer.status == .writing,
              let input = videoInput, input.isReadyForMoreMediaData else { return }
        input.append(sb)                                   // 未準備時はフレーム破棄（PoC 許容）
    }

    // MARK: - セグメント

    private func startNewSegment(firstSample sb: CMSampleBuffer, at pts: CMTime) {
        guard let fmt = CMSampleBufferGetFormatDescription(sb) else { return }
        let dim = CMVideoFormatDescriptionGetDimensions(fmt)
        guard dim.width > 0, dim.height > 0 else { return }

        let url = Self.tempURL(prefix: "flashback-seg-")
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dim.width),
            AVVideoHeightKey: Int(dim.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard w.canAdd(input) else { return }
        w.add(input)
        guard w.startWriting() else { return }
        w.startSession(atSourceTime: pts)                  // 最初のサンプル PTS（.zero 不可）

        writer = w
        videoInput = input
        currentSegmentStart = pts
    }

    /// 現セグメントを確定し、完了後に URL を環へ追加して古いものを捨てる。
    private func finalizeCurrent(completion: (() -> Void)? = nil) {
        guard let writer, let input = videoInput else { completion?(); return }
        let url = writer.outputURL
        input.markAsFinished()
        self.writer = nil
        self.videoInput = nil
        self.currentSegmentStart = .invalid

        writer.finishWriting { [weak self] in
            guard let self else { completion?(); return }
            self.queue.async {
                if writer.status == .completed {
                    self.segmentURLs.append(url)
                    self.trimRing()
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
                completion?()
            }
        }
    }

    private func trimRing() {
        while segmentURLs.count > maxSegments {
            let old = segmentURLs.removeFirst()
            try? FileManager.default.removeItem(at: old)
        }
    }

    // MARK: - 書き出し / 後始末

    func export() async throws -> URL {
        let segments = try await finalizeAndSnapshot()
        return try await Self.composeAndExport(segments: segments)
    }

    private func finalizeAndSnapshot() async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                finalizeCurrent {
                    let segs = self.segmentURLs
                    if segs.isEmpty {
                        continuation.resume(throwing: FlashbackError.recordingUnavailable)
                    } else {
                        continuation.resume(returning: segs)
                    }
                }
            }
        }
    }

    func teardown() {
        queue.async { [self] in
            finalizeCurrent {
                for url in self.segmentURLs {
                    try? FileManager.default.removeItem(at: url)
                }
                self.segmentURLs.removeAll()
            }
        }
    }

    /// セグメント群を 1 本の mp4 へ連結（passthrough・無劣化）。先頭トリムはしない。
    private static func composeAndExport(segments: [URL]) async throws -> URL {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw FlashbackError.recordingUnavailable
        }

        var cursor = CMTime.zero
        for url in segments {
            let asset = AVURLAsset(url: url)
            guard let assetTrack = try? await asset.loadTracks(withMediaType: .video).first,
                  let duration = try? await asset.load(.duration), duration > .zero else {
                continue
            }
            let range = CMTimeRange(start: .zero, duration: duration)
            try? track.insertTimeRange(range, of: assetTrack, at: cursor)
            cursor = CMTimeAdd(cursor, duration)
        }
        guard cursor > .zero else { throw FlashbackError.recordingUnavailable }

        let outURL = tempURL(prefix: "flashback-")
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw FlashbackError.recordingUnavailable
        }
        session.outputURL = outURL
        session.outputFileType = .mp4

        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            throw session.error ?? FlashbackError.recordingUnavailable
        }
        return outURL
    }

    // MARK: - 一時ファイル

    private static func tempURL(prefix: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)\(UUID().uuidString).mp4")
    }

    /// 前回起動の残骸（flashback-* / flashback-seg-*）を掃除する。
    static func purgeTempFiles() {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in items where url.lastPathComponent.hasPrefix("flashback-") {
            try? fm.removeItem(at: url)
        }
    }
}
#else
final class ScreenRecorder {
    func startBuffering(seconds: TimeInterval) {}
    func stopBuffering() {}
    func exportBufferedClip() async throws -> URL { throw FlashbackError.notImplemented }
}
#endif
