#if canImport(ReplayKit)
import ReplayKit
import AVFoundation
import UIKit

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
final class ScreenRecorder: NSObject, RPScreenRecorderDelegate {
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

    /// 録画オンの意思（host/ユーザが録画したい状態か）。明示停止で false。割り込み復帰の自動再開判定に使う。
    private var wantsRecording = false
    /// OS 録画/ミラーリング等の割り込みで一時停止中か。復帰時の自動再開はこのフラグが立っている時だけ。
    private var interruptedBySystem = false
    /// 直近に要求された保持秒数。割り込み復帰の自動再開で同じ秒数で開始するため保持する。
    private var desiredBufferSeconds: TimeInterval = 0

    /// フレーム供給を監視するウォッチドッグ。外部キャプチャ中に供給が途切れたら割り込みとして停止する。
    private var watchdog: Task<Void, Never>?
    /// 映像フレームが途切れて「割り込み」とみなすまでの無入力秒数。外部キャプチャ中だけ判定する門番つき
    /// なので短くても安全（実機で静止画面でもフレームは途切れず age≈0、外部キャプチャ重畳でのみ急増する）。
    /// 0.3s：即応性と、通常操作の一時的フレーム途切れによる誤検知/churn 回避のバランス点。
    private static let stallThreshold: Double = 0.3
    /// アプリ内録画自体が `UIScreen.isCaptured` を立てるか（端末/iOS 依存）。録画開始直後に一度だけ probe。
    /// `false` と分かれば「`isCaptured` が true へ変化＝外部キャプチャ開始」と確定でき、即座に割り込める。
    private var inAppMarksCaptured: Bool?

    /// 画面録画が利用可能か（Simulator / 通話中 / 別アプリ録画中などは false）。
    /// 事前照会できる権限 API は無いため、設定画面の権限表示はこの可用性を用いる。
    ///
    /// Simulator は ReplayKit 実録画が物理的に不可。**新しい Sim（iOS 18 系）では
    /// `RPScreenRecorder.isAvailable` が `true` を返す**ため、可用性を `RPScreenRecorder`
    /// 任せにすると ReportView が「録画不可」でなく「録画はオフです（CTA 付き）」を誤表示する。
    /// よって Sim ではコンパイル時に false へ固定する。
    var isAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        recorder.isAvailable
        #endif
    }

    /// 実際に録画が走っている（許可確定済み）か。`isCapturing`（試行中）ではなく**確定**状態を返す。
    /// 許可ダイアログ応答前は false（楽観的に true にしない）。UI の録画中表示・発火可否の真値。
    var isRecording: Bool { captureConfirmed }

    /// 録画の確定状態が変わるたびに `@MainActor` で呼ばれる永続フック（全 start 経路共通）。
    /// 成功確定→true / 停止・失敗→false。設定画面の「録画中/停止中」を監視更新するのに使う。
    /// （retry 一回限りの `onCaptureStarted` とは別。こちらは start() で一度だけ配線し常駐。）
    var onRecordingStateChanged: ((Bool) -> Void)?

    /// 外部キャプチャ（OS画面収録/ミラーリング/通話等）による**中断**と**自動再開**だけを通知する
    /// `@MainActor` フック。`true`=中断（割り込みで停止）/`false`=再開。手動の on/off とは別経路で、
    /// 中断/再開のトースト表示に使う。
    var onExternalCaptureInterrupt: ((Bool) -> Void)?

    /// `startCapture` の確定結果を通知するフック（録画オン直後の justEnabled 判定用）。
    /// `@MainActor` 上で呼ばれる。`true` = 取り込み開始成功、`false` = 失敗（権限拒否など）。
    /// retryRecording 経由でのみ設定し、成功で一度使ったら呼び出し側で解除する想定。
    /// ※ ReplayKit の `@Sendable` ハンドラへクロージャを渡すと過剰解放クラッシュの恐れがあるため、
    ///   ハンドラ内では `self` のこのプロパティを参照して通知する（クロージャを box 化しない）。
    var onCaptureStarted: ((Bool) -> Void)?

    override init() {
        super.init()
        // 可用性変化（通話など）と、外部キャプチャ（OS画面収録/ミラーリング）の開始終了を監視する。
        recorder.delegate = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenCaptureStateChanged),
            name: UIScreen.capturedDidChangeNotification, object: nil)
        #if DEBUG
        // 放置→フォアグラウンド復帰の瞬間の録画状態を固定観察するための診断（DEBUG のみ）。
        NotificationCenter.default.addObserver(
            self, selector: #selector(debugCaptureWakeSnapshot),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        #endif
    }

    func startBuffering(seconds: TimeInterval) {
        guard !isCapturing else { return }                 // 冪等
        wantsRecording = true                              // 録画オンの意思（割り込み復帰の自動再開判定用）
        desiredBufferSeconds = seconds
        inAppMarksCaptured = nil                            // 端末特性は今回のセッションで取り直す
        SegmentRingWriter.purgeTempFiles()                 // 前回の残骸を掃除

        guard isAvailable else {                           // Simulator / 未対応（Sim は上の可用性ゲートで false 固定）
            FlashbackLog.lifecycle.info("画面録画は利用不可（Simulator か未対応環境）。clip なしで継続。")
            onCaptureStarted?(false)                       // 録画オンにできず（おやすみ維持）
            return                                         // throw しない。export 側で recordingUnavailable
        }

        recorder.isMicrophoneEnabled = false               // 映像のみ（mic 権限不要）
        let ring = SegmentRingWriter(bufferSeconds: seconds)
        self.ring = ring
        ringHolder.set(ring)
        ringHolder.resetClock()                            // フレーム時計を初期化（誤検知防止）
        isCapturing = true

        // self を捕捉しないよう holder を local に束ねて渡す（holder は Sendable）。
        let holder = ringHolder
        recorder.startCapture(handler: { @Sendable sampleBuffer, bufferType, error in
            // 背景スレッドで呼ばれる。@Sendable で main-actor 隔離を外すこと。
            // 付けないとクロージャが @MainActor 隔離を継承し、ReplayKit が背景スレッドで
            // 呼んだ瞬間に "Block was expected to execute on queue [main-thread]" で trap する。
            // CMSampleBuffer は非 Sendable なので ingest 内で box 化して serial queue へ渡す。
            // ring は holder 経由で読む（保持秒数変更で差し替わっても・停止後 nil でも安全）。
            if let error { holder.noteError(error); return }   // DEBUG 計装: CC 奪取等でエラーが来るか観察
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
                    self.startWatchdog()                   // フレーム供給の途絶（割り込み）を監視開始
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
        // 明示停止：以降は割り込み復帰でも自動再開しない。
        wantsRecording = false
        interruptedBySystem = false
        teardownCapture(notify: true)
    }

    /// capture を停止し ring を破棄する（録画オフ確定通知つき）。明示停止と割り込み一時停止で共用。
    /// `wantsRecording` / `interruptedBySystem` は変更しない（呼び出し側が用途に応じて設定する）。
    private func teardownCapture(notify: Bool) {
        guard isCapturing else { return }                  // 冪等
        watchdog?.cancel(); watchdog = nil                 // フレーム監視を停止
        isCapturing = false
        let wasConfirmed = captureConfirmed
        captureConfirmed = false
        ringHolder.set(nil)                                // 在庫サンプルを以降ドロップ（破棄済み ring を触らせない）
        // completion は背景スレッドで呼ばれる。@Sendable 必須（無いと @MainActor 隔離を継承し
        // 背景実行の瞬間に "Block was expected to execute on queue [main-thread]" で trap する）。
        recorder.stopCapture { @Sendable _ in }
        ring?.teardown()
        ring = nil
        if notify && wasConfirmed { onRecordingStateChanged?(false) }  // 確定: 録画オフ
    }

    /// 現在のバッファを一時 .mp4 に書き出して URL を返す。
    func exportBufferedClip() async throws -> URL {
        guard let ring, isCapturing else { throw FlashbackError.recordingUnavailable }
        return try await ring.export()
    }

    #if DEBUG
    /// DEBUG: 直近映像フレームからの経過秒（nil=未受信）。割り込み検知しきい値の調整用。
    var debugFrameAge: Double? { ringHolder.secondsSinceLastVideo() }
    /// DEBUG: 画面が外部キャプチャ中か（`UIScreen.isCaptured`）。
    var debugScreenIsCaptured: Bool { Self.screenIsCaptured() }
    /// DEBUG: このセッションでアプリ内録画自体が isCaptured を立てたか（probe 結果。nil=未判定）。
    var debugInAppMarksCaptured: Bool? { inAppMarksCaptured }
    /// DEBUG: システム側 `RPScreenRecorder.isRecording`（アプリ内 `captureConfirmed` とは別物）。
    /// CC 画面収録に奪われた時に false へ落ちるか実機で観察するための窓。
    var debugSystemIsRecording: Bool { recorder.isRecording }
    /// DEBUG: capture handler に来たエラー件数。
    var debugCaptureErrorCount: Int { ringHolder.errorSnapshot().count }
    /// DEBUG: 直近の didBecomeActive（フォアグラウンド復帰）時点の録画状態スナップショット。
    /// 復帰直後にウォッチドッグが値を書き換える前の「戻ってきた瞬間の状態」を観察するため。
    private(set) var debugWakeSnapshot = "—"

    /// didBecomeActive で呼ばれ、復帰瞬間の状態を同期的に採取する（ウォッチドッグの非同期補正より前）。
    @objc private func debugCaptureWakeSnapshot() {
        let age = ringHolder.secondsSinceLastVideo().map { String(format: "%.1f", $0) } ?? "—"
        debugWakeSnapshot = "rec=\(captureConfirmed ? "ON" : "off") sysRec=\(recorder.isRecording ? "ON" : "off") age=\(age) errs=\(ringHolder.errorSnapshot().count)"
    }
    #endif

    // MARK: - 外部キャプチャ（OS画面収録/ミラーリング/通話）との競合

    /// アプリ内キャプチャと OS の画面収録/ミラーリングは排他で、外部キャプチャが始まるとアプリ内
    /// キャプチャのフレーム供給が止まり（＝バッファが凍り）、しかも完了ハンドラも呼ばれずセッションも
    /// 復帰しない。そこで **外部キャプチャ中にフレームが途切れたら割り込みとみなして完全停止**
    /// （OFF・凍ったバッファ破棄）し、**外部キャプチャが終わったら自動再開**する。
    ///
    /// 検知＝フレーム供給ウォッチドッグ ＋ `UIScreen.isCaptured` 門番（外部キャプチャが在る時だけ割り込み
    /// 扱い。静止画面でフレームが疎な時の誤検知を防ぐ）。復帰＝`UIScreen.capturedDidChangeNotification`
    /// と `RPScreenRecorder` 可用性で拾う。

    /// 外部キャプチャによる割り込み：完全停止して凍ったバッファを捨てる。`isCapturing=false` にするので、
    /// 復帰時の `startBuffering` 自動再開・ユーザの手動再オンが効く（セッション維持だと冪等ガードで弾かれる）。
    private func interruptForExternalCapture(reason: String) {
        guard isCapturing else { return }
        FlashbackLog.lifecycle.info("\(reason, privacy: .public)。録画を停止し凍ったバッファを破棄（割り込み）。")
        interruptedBySystem = true                         // 復帰時に自動再開する目印
        teardownCapture(notify: true)                      // OFF 確定（FAB グレー）＋ セッション停止＋ ring 破棄
        onExternalCaptureInterrupt?(true)                  // 中断トースト
    }

    /// 外部キャプチャ終了 / 可用性復帰時の自動再開。録画意思が残り・二重開始でなく・外部キャプチャが
    /// もう無い時だけ実行する。
    private func attemptResume(reason: String) {
        guard interruptedBySystem, wantsRecording, !isCapturing, !Self.screenIsCaptured() else { return }
        interruptedBySystem = false
        FlashbackLog.lifecycle.info("\(reason, privacy: .public)。録画を自動再開。")
        startBuffering(seconds: desiredBufferSeconds)
        onExternalCaptureInterrupt?(false)                 // 再開トースト
    }

    /// 画面が外部からキャプチャ（OS画面収録 / AirPlay / ミラーリング）されているか。
    private static func screenIsCaptured() -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.isCaptured ?? false
    }

    private func handleAvailabilityChange(available: Bool) {
        if available { attemptResume(reason: "画面録画が利用可能に復帰") }
        else { interruptForExternalCapture(reason: "画面録画が利用不可に（通話/別アプリ等）") }
    }

    /// ReplayKit の可用性変化コールバック（背景スレッドで来うるため `nonisolated`）。
    /// 値は読まず `@MainActor` へ hop し、`self`（MainActor 隔離・Sendable）経由で処理する。
    nonisolated func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {
        let available = screenRecorder.isAvailable
        Task { @MainActor [weak self] in self?.handleAvailabilityChange(available: available) }
    }

    /// `UIScreen.capturedDidChangeNotification`（外部キャプチャの開始/終了）。**復帰のトリガにのみ使う**
    /// （開始の検知はウォッチドッグが担当：アプリ内キャプチャ自身が `isCaptured` を立てる端末でも
    /// 自分の録画開始を誤って割り込み扱いしないため）。main で来うるが Swift6 のため hop する。
    @objc nonisolated private func screenCaptureStateChanged() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if Self.screenIsCaptured() {
                // アプリ内録画が isCaptured を立てない端末では、true への変化＝外部キャプチャ開始が確定。
                // 録画開始とほぼ同時に即グレーへ。立てる端末/未判定は watchdog に委ねる（誤爆防止）。
                if self.inAppMarksCaptured == false {
                    self.interruptForExternalCapture(reason: "外部キャプチャ（画面収録/ミラーリング）開始を検知")
                }
            } else {
                self.attemptResume(reason: "外部キャプチャが終了")
            }
        }
    }

    // MARK: - フレーム供給ウォッチドッグ（割り込み検知）

    /// 取り込み中、**外部キャプチャがあるのに**映像フレームが `stallThreshold` 秒途切れたら割り込みと
    /// みなして停止する。コントロールセンターの画面収録など可用性 delegate が発火しない経路を拾う。
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)   // 0.1s 刻み（しきい値より細かく刻んで素早く検知）
                guard let self, self.isCapturing else { return }
                self.checkStall()
            }
        }
    }

    private func checkStall() {
        guard captureConfirmed else { return }
        let idle = ringHolder.secondsSinceLastVideo()
        // 端末特性 probe：録画開始後の最初のフレーム時点（＝通常は外部キャプチャ無し）で、アプリ内録画
        // 自体が UIScreen.isCaptured を立てるかを一度だけ記録する。
        if inAppMarksCaptured == nil, idle != nil {
            inAppMarksCaptured = Self.screenIsCaptured()
        }
        // バックアップ検知：外部キャプチャ中にフレームが stallThreshold 秒途切れたら割り込み。
        // （capturedDidChange を取りこぼす / isCaptured を立てる端末で true 通知が来ない場合の保険）
        //
        // ゲート `inAppMarksCaptured == false` 必須：`screenIsCaptured()` が「外部キャプチャ在り」を
        // 意味するのは、アプリ内録画が isCaptured を立てない端末だけ。立てる端末（==true）では録画中は
        // 常に isCaptured=true なので門番が効かず、静止画面（ReplayKit は画面変化時しかフレームを供給
        // しない＝正常な無入力）を誤って割り込み扱いし、停止→自動再開を反復してしまう（FAB ちらつき）。
        // 即時パス側（screenCaptureStateChanged）と同じゲートを掛けて対称にする。
        // ※ inAppMarksCaptured==true の端末（iPhone 15 Pro 等）はこの門番が効かないため、下の
        //   「システム録画停止」経路で別途拾う。
        if let idle, idle > Self.stallThreshold, inAppMarksCaptured == false, Self.screenIsCaptured() {
            interruptForExternalCapture(reason: "外部キャプチャ中にフレーム供給停止を検知")
        }
        // アプリ内録画が isCaptured を立てる端末（iPhone 15 Pro 等）向けの検知。`isCaptured` ではCC重畳と
        // 区別できないので、代わりに「フレーム途絶 AND システム側 `RPScreenRecorder.isRecording` が false」を
        // 外部キャプチャ奪取とみなす。静止画面では isRecording は true のままなので誤爆しない（CC 奪取で
        // false へ落ちる）。**実機（iPhone 15 Pro / iOS 26.5）で CC 画面収録の自動off＋復帰を確認済み。**
        if inAppMarksCaptured == true, captureConfirmed, wantsRecording,
           let idle, idle > Self.stallThreshold, !recorder.isRecording {
            interruptForExternalCapture(reason: "システム録画停止＋フレーム供給停止を検知（外部キャプチャ奪取）")
        }
    }
}

/// capture ハンドラ（背景スレッド・`@Sendable`）から触れる「現在の ring」の保持箱。
/// ロックで ring の差し替えを原子化し、録画を止めずに保持秒数変更（ring 入れ替え）と
/// 停止後のサンプルドロップ（ring=nil）を安全に行えるようにする。
private final class RingHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var ring: SegmentRingWriter?
    /// 最後に**映像**サンプルを受け取った単調時刻（ns）。0 = まだ受けてない。
    /// OS録画等でフレーム供給が止まる割り込みを、ウォッチドッグで検知するのに使う。
    private var lastVideoNanos: UInt64 = 0
    /// capture handler に来たエラーの件数と直近メッセージ（DEBUG 計装用）。CC 奪取等で
    /// エラーが来るかを実機観察するために記録する。
    private var errorCount = 0
    private var lastErrorText: String?

    func set(_ newRing: SegmentRingWriter?) {
        lock.lock(); defer { lock.unlock() }
        ring = newRing
    }

    /// 新規キャプチャ開始時にフレーム時計・エラー計装をリセットする（前回の値で誤検知しないように）。
    func resetClock() {
        lock.lock(); lastVideoNanos = 0; errorCount = 0; lastErrorText = nil; lock.unlock()
    }

    /// capture handler（背景スレッド）に来たエラーを記録する。
    func noteError(_ error: Error) {
        lock.lock(); errorCount += 1; lastErrorText = error.localizedDescription; lock.unlock()
    }

    /// 記録したエラーの件数と直近メッセージのスナップショット。
    func errorSnapshot() -> (count: Int, last: String?) {
        lock.lock(); defer { lock.unlock() }
        return (errorCount, lastErrorText)
    }

    func ingest(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType) {
        lock.lock()
        let current = ring
        if type == .video { lastVideoNanos = DispatchTime.now().uptimeNanoseconds }
        lock.unlock()
        current?.ingest(sampleBuffer, type: type)
    }

    /// 最後の映像サンプルからの経過秒。まだ一度も受けてなければ nil。
    func secondsSinceLastVideo() -> Double? {
        lock.lock(); let last = lastVideoNanos; lock.unlock()
        guard last != 0 else { return nil }
        return Double(DispatchTime.now().uptimeNanoseconds &- last) / 1_000_000_000
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
    /// 目標保持長（秒）。リングは over-retain（N＋セグメント端数）するため、書き出し時に
    /// 直近この秒数へトリムして尺の上振れを無くす。録画が N 秒未満なら在庫全体を返す。
    private let bufferSeconds: TimeInterval

    // 以下は queue 上でのみアクセスする。
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var currentSegmentStart: CMTime = .invalid
    private var segmentURLs: [URL] = []
    /// teardown 済みフラグ。確定後に遅れて届くサンプルでセグメントを作り直さないためのガード。
    private var tornDown = false

    init(bufferSeconds: TimeInterval) {
        self.bufferSeconds = bufferSeconds
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
        return try await Self.composeAndExport(segments: segments, targetSeconds: bufferSeconds)
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

    /// セグメント群を 1 本の mp4 へ連結（passthrough・無劣化）し、直近 `targetSeconds` へトリムする。
    /// リングは over-retain（N＋セグメント端数）するので、書き出し時に末尾 N 秒だけを `session.timeRange`
    /// で切り出すと尺の上振れが消えて安定する（passthrough はキーフレーム境界へ数フレームの誤差で
    /// スナップしうる＝ClipTrimmer と同方針）。連結尺が N 未満なら全体を返す（在庫不足は埋められない）。
    private static func composeAndExport(segments: [URL], targetSeconds: TimeInterval) async throws -> URL {
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

        // 直近 targetSeconds だけを書き出す（over-retain した先頭超過分を落として尺を安定させる）。
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        if cursor > target {
            session.timeRange = CMTimeRange(start: CMTimeSubtract(cursor, target), duration: target)
        }

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
    #if DEBUG
    var debugFrameAge: Double? { nil }
    var debugScreenIsCaptured: Bool { false }
    var debugInAppMarksCaptured: Bool? { nil }
    #endif
}
#endif
