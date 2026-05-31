# FlashbackKit

> Recall the moment before the bug.

不具合発生“前”の文脈を取り戻す、モバイル QA 向けの AI レポート SDK（iOS）。
トリガ（端末を振る / 3本指で長押し / フローティングボタン）→ 直前 30 秒の録画・コメント・端末情報をまとめ、AI がレポート化して Slack へ送る。

> **Status: PoC / WIP.** 本番一般ユーザー向けではなく、Debug / Staging / TestFlight / 社内 QA 用途を想定。

## Requirements

- iOS 16+
- Swift 6 / Xcode 16+
- 依存ライブラリなし（Firebase / Alamofire / Rx 不使用）

## Installation (SPM)

```swift
.package(url: "https://github.com/<you>/flashbackkit-ios.git", from: "0.0.1")
```

```swift
.target(name: "YourApp", dependencies: ["FlashbackKit"])
```

## Quick Start

```swift
import FlashbackKit

// アプリ起動時に一度だけ
Flashback.start(
    configuration: .init(
        bufferSeconds: 30,
        slackWebhookURL: URL(string: "https://hooks.slack.com/services/...")
    )
)
```

トリガ → トリミング画面で、QA は右上の **共有（↑）** から OS 標準シート
（写真に保存 / ファイルに保存 / AirDrop / 他アプリ）を開く。出口はこの一つに集約。
共有するクリップはタイトル＝コメント・ファイル名＝コメントでメタデータが焼き込まれる。

### 成果物を受け取る（`onReport` ハンドオフ）

録画 → トリムまで終えた成果物 `FlashbackReport`（クリップ URL・端末情報・コメント）は、
保存 / 共有 を確定した時点で `onReport` でホストへ手渡される。AI 要約・自社 API・Jira
連携などホスト固有の処理はこのコールバックから自由にルーティングできる。
**SDK の責務は成果物を渡すところまで**。

```swift
Flashback.start(
    onReport: { report in
        // report.clipURL（トリム済みクリップ）, report.device, report.comment …
        myBackend.upload(report.clipURL)
    }
)
```

> `report.clipURL` は一時ファイル。残す場合はこのコールバック内でコピー／アップロードすること。

### 必要な Info.plist キー

共有シートの **「写真に保存」でカメラロールに保存する**ため、ホストアプリの Info.plist に
追記が必要（無いと権限要求時にクラッシュする）。「ファイルに保存」だけ使うなら不要:

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>不具合レポートの直前録画クリップをカメラロールに保存します。</string>
```

## Example アプリ

`Example/FlashbackExample.xcodeproj` に仮UIループ確認用のホストアプリがある。

- **Simulator**: そのままビルド可（署名不要）。ただし ReplayKit の画面キャプチャは
  Simulator では動かないため、録画は無効化され clip なしでループだけ動く。
- **実機**: コード署名が必要。Team ID はリポジトリに含めないので、各自で設定する:

  ```sh
  cp Example/Signing.example.xcconfig Example/Signing.xcconfig
  # Signing.xcconfig を開き DEVELOPMENT_TEAM に自分の Apple Developer Team ID を記入
  ```

  `Signing.xcconfig` は `.gitignore` 済み。`Config.xcconfig` が optional include で
  読み込むため、未作成でも Simulator ビルドは警告なく通る。

## MVP Scope

複数トリガ起動（シェイク / 多指長押し / フローティングボタン）/ 直前録画 / コメント入力 / AI 要約 / Slack 送信

## Known Constraints（実装前に要注意）

- **ReplayKit は遡って録画できない** → 常時バッファ録画が前提（起動毎に録画許可プロンプトが出る／発熱・電池負荷あり）
- **Slack Incoming Webhook は動画を送れない**（テキスト / リンクのみ。動画は Bot トークン + files.getUploadURLExternal/completeUploadExternal が必要）
- **Claude / OpenAI は動画を直接解析できない**（キーフレーム抽出 or 動画ネイティブモデルが必要）
- 画面録画は画面上の全情報を含む → **センシティブ情報のマスキングはホストアプリの責務**（後述）

## Privacy: センシティブ情報のマスキング

画面録画は画面上の全情報（顧客名・住所・在庫数・トークン等）を含む。これらのマスキングは
**ホストアプリの責務**であり、FlashbackKit は録画パイプラインに介入しない。

理由: ReplayKit のアプリ内キャプチャは「合成後の画面全体」を渡してくるため、SDK 側で特定 View
だけを隠すには座標追跡＋リアルタイムなピクセル書き換えが要る。座標変換・性能・実機限定検証の
コストが高い割に、結局「どこが機密か」はホストしか知らない。依存ゼロ・PoC の方針からも、
マスキングはホスト側の View 技法に倒すのが筋。

### パスワード等は iOS が自動で除外する

`isSecureTextEntry = true` の `UITextField` は、iOS が ReplayKit / スクリーンショットから
**自動的に除外**する。パスワード欄は追加対応なしで録画に映らない。

### それ以外の機密 View はホスト側で隠す

顧客情報など secure フィールド以外を隠したい場合、ホスト側で対象 View を覆う／消す:

- **確実な方法**: QA 対象ビルドでは機密画面をダミーデータにする、または録画中はその画面を出さない運用。
- **セキュアレイヤー・トリック（非公式）**: `isSecureTextEntry` なテキストフィールドのレイヤーに
  コンテンツを載せると、ユーザーには見えたまま録画からは除外される。iOS バージョンで挙動が
  変わりうる非公式手法のため、確実性が要る場面では上記運用を優先する。

  ```swift
  // ホストアプリ側のユーティリティ例（FlashbackKit には含めない）。
  // secure な UITextField のコンテンツレイヤーへ対象 View を載せ、録画から除外する。
  extension UIView {
      func hideFromScreenCapture(_ content: UIView) {
          let field = UITextField()
          field.isSecureTextEntry = true
          guard let secureLayer = field.layer.sublayers?.first else { return }
          secureLayer.addSublayer(content.layer)
      }
  }
  ```

> 補足: 端末保存や共有でクリップを写真ライブラリへ保存すると iCloud にも乗りうる。
> 機密を含みうる点に留意する（保存先は QA が保存／共有時に選ぶ）。

## License

MIT
