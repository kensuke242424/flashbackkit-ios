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
    /// 現在の ring（@MainActor 側の参照。書き出し / 後始末用）。
    private var ring: SegmentRingWriter?
    /// capture ハンドラ（背景スレッド）が触れる「現在の ring」の保持箱。
    /// ring をロック越しに原子的に差し替えられるので、**ReplayKit を止めずに**保持秒数を
    /// 変更できる（古い stop→即 start の churn を避ける）。
    private let ringHolder = RingHolder()
    /// startCapture を試行中か（許可ダイアログ応答前も含む）。idempotency / ring 寿命管理用の内部状態。
    private var isCapturing = false
    /// 取り込みが**確定**したか（startCapture 成功＝許可後だけ true）。UI の「録画中/停止中」はこちら。
    private var captureConfirmed = false

    /// 画面録画が利用可能か（Simulator / 通話中 / 別アプリ録画中などは false）。
    /// 事前照会できる権限 API は無いため、設定画面の権限表示はこの可用性を用いる。
    var isAvailable: Bool { recorder.isAvailable }

    /// 実際に録画が走っている（許可確定済み）か。`isCapturing`（試行中）ではなく**確定**状態を返す。
    /// 許可ダイアログ応答前は false（楽観的に true にしない）。UI の録画中表示・発火可否の真値。
    var isRecording: Bool { captureConfirmed }

    /// 録画の確定状態が変わるたびに `@MainActor` で呼ばれる永続フック（全 start 経路共通）。
    /// 成功確定→true / 停止・失敗→false。設定画面の「録画中/停止中」を監視更新するのに使う。
    /// （retry 一回限りの `onCaptureStarted` とは別。こちらは start() で一度だけ配線し常駐。）
    var onRecordingStateChanged: ((Bool) -> Void)?

    /// `startCapture` の確定結果を通知するフック（録画オン直後の justEnabled 判定用）。
    /// `@MainActor` 上で呼ばれる。`true` = 取り込み開始成功、`false` = 失敗（権限拒否など）。
    /// retryRecording 経由でのみ設定し、成功で一度使ったら呼び出し側で解除する想定。
    /// ※ ReplayKit の `@Sendable` ハンドラへクロージャを渡すと過剰解放クラッシュの恐れがあるため、
    ///   ハンドラ内では `self` のこのプロパティを参照して通知する（クロージャを box 化しない）。
    var onCaptureStarted: ((Bool) -> Void)?

    func startBuffering(seconds: TimeInterval) {
        guard !isCapturing else { return }                 // 冪等
        SegmentRingWriter.purgeTempFiles()                 // 前回の残骸を掃除

        guard recorder.isAvailable else {                  // Simulator / 未対応
            FlashbackLog.lifecycle.info("画面録画は利用不可（Simulator か未対応環境）。clip なしで継続。")
            onCaptureStarted?(false)                       // 録画オンにできず（おやすみ維持）
            return                                         // throw しない。export 側で recordingUnavailable
        }

        recorder.isMicrophoneEnabled = false               // 映像のみ（mic 権限不要）
        let ring = SegmentRingWriter(bufferSeconds: seconds)
        self.ring = ring
        ringHolder.set(ring)
        isCapturing = true

        // self を捕捉しないよう holder を local に束ねて渡す（holder は Sendable）。
        let holder = ringHolder
        recorder.startCapture(handler: { @Sendable sampleBuffer, bufferType, error in
            // 背景スレッドで呼ばれる。@Sendable で main-actor 隔離を外すこと。
            // 付けないとクロージャが @MainActor 隔離を継承し、ReplayKit が背景スレッドで
            // 呼んだ瞬間に "Block was expected to execute on queue [main-thread]" で trap する。
            // CMSampleBuffer は非 Sendable なので ingest 内で box 化して serial queue へ渡す。
            // ring は holder 経由で読む（保持秒数変更で差し替わっても・停止後 nil でも安全）。
            guard error == nil else { return }
            holder.ingest(sampleBuffer, type: bufferType)
        }, completionHandler: { @Sendable error in
            // ハンドラには weak self だけを捕捉し（クロージャを box 化しない）、結果は
            // @MainActor へ hop してから self のプロパティ経由で通知する。
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    FlashbackLog.lifecycle.error("startCapture 失敗: \(error.localizedDescription, privacy: .public)")
                    self.isCapturing = false
                    self.captureConfirmed = false
                    self.ring?.teardown()
                    self.ring = nil
                    self.onCaptureStarted?(false)
                    self.onRecordingStateChanged?(false)   // 確定: 録画オフ（拒否など）
                } else {
                    FlashbackLog.lifecycle.info("startCapture 開始成功（録画オン）")
                    self.captureConfirmed = true           // ここで初めて「録画中」確定（許可後）
                    self.onCaptureStarted?(true)           // retry 一回限り（justEnabled 用）
                    self.onRecordingStateChanged?(true)    // 確定: 録画オン（UI 監視更新）
                }
            }
        })
    }

    /// 保持秒数を変更する。**ReplayKit のキャプチャは止めず**、ring だけを差し替える。
    /// 録画中でなければ何もしない（次回の `startBuffering` が新しい秒数で開始する）。
    ///
    /// 旧実装の `stop→即 start`（ReplayKit を止めて即再開）は、停止が非同期なため
    /// 「停止完了前の再 start」「古いハンドラが破棄済み ring を触る」競合でクラッシュした。
    /// ring 差し替えなら capture は連続したまま、以降のサンプルが新 ring に流れる
    /// （差し替え時点のバッファはリセットされる＝保持長変更の挙動として妥当）。
    func changeBufferSeconds(_ seconds: TimeInterval) {
        guard isCapturing else { return }
        let old = ring
        let newRing = SegmentRingWriter(bufferSeconds: seconds)
        ring = newRing
        ringHolder.set(newRing)                            // 以降のサンプルは新 ring へ（原子的）
        old?.teardown()                                    // 旧 ring を確定・破棄（capture は止めない）
    }

    func stopBuffering() {
        guard isCapturing else { return }                  // 冪等
        isCapturing = false
        let wasConfirmed = captureConfirmed
        captureConfirmed = false
        ringHolder.set(nil)                                // 在庫サンプルを以降ドロップ（破棄済み ring を触らせない）
        // completion は背景スレッドで呼ばれる。@Sendable 必須（無いと @MainActor 隔離を継承し
        // 背景実行の瞬間に "Block was expected to execute on queue [main-thread]" で trap する）。
        recorder.stopCapture { @Sendable _ in }
        ring?.teardown()
        ring = nil
        if wasConfirmed { onRecordingStateChanged?(false) }  // 確定: 録画オフ
    }

    /// 現在のバッファを一時 .mp4 に書き出して URL を返す。
    func exportBufferedClip() async throws -> URL {
        guard let ring, isCapturing else { throw FlashbackError.recordingUnavailable }
        return try await ring.export()
    }
}

/// capture ハンドラ（背景スレッド・`@Sendable`）から触れる「現在の ring」の保持箱。
/// ロックで ring の差し替えを原子化し、録画を止めずに保持秒数変更（ring 入れ替え）と
/// 停止後のサンプルドロップ（ring=nil）を安全に行えるようにする。
private final class RingHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var ring: SegmentRingWriter?

    func set(_ newRing: SegmentRingWriter?) {
        lock.lock(); defer { lock.unlock() }
        ring = newRing
    }

    func ingest(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType) {
        lock.lock(); let current = ring; lock.unlock()
        current?.ingest(sampleBuffer, type: type)
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
    /// teardown 済みフラグ。確定後に遅れて届くサンプルでセグメントを作り直さないためのガード。
    private var tornDown = false

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
        guard !tornDown else { return }                    // 確定後の遅延サンプルは捨てる
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

        // finishWriting / queue.async のクロージャは @Sendable 扱い。writer(AVAssetWriter) と
        // completion は非 Sendable だが、この確定フローは単一論理スレッド（finishWriting 完了 →
        // 自前 serial queue）で writer をここでしか触れず completion も一度だけ呼ぶため安全。
        // 値を box 化すると ARC 経路が変わりブロックの過剰解放でクラッシュするため、捕捉する
        // local に nonisolated(unsafe) を付けて「並行境界越しでも安全」と明示するに留める。
        nonisolated(unsafe) let finishedWriter = writer
        nonisolated(unsafe) let finishCompletion = completion
        finishedWriter.finishWriting { [weak self] in
            guard let self else { finishCompletion?(); return }
            self.queue.async {
                if finishedWriter.status == .completed {
                    self.segmentURLs.append(url)
                    self.trimRing()
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
                finishCompletion?()
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
            tornDown = true
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
    var isAvailable: Bool { false }
    var isRecording: Bool { false }
    var onCaptureStarted: ((Bool) -> Void)?
    var onRecordingStateChanged: ((Bool) -> Void)?
    func startBuffering(seconds: TimeInterval) {}
    func changeBufferSeconds(_ seconds: TimeInterval) {}
    func stopBuffering() {}
    func exportBufferedClip() async throws -> URL { throw FlashbackError.notImplemented }
}
#endif
