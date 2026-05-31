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
        slackWebhookURL: URL(string: "https://hooks.slack.com/services/..."),
        savesClipToPhotos: true   // 既定 true: 直前クリップをカメラロールに保存
    )
)
```

### 必要な Info.plist キー

`savesClipToPhotos`（既定 true）で写真ライブラリに保存するため、**ホストアプリの
Info.plist に追記が必要**（無いと権限要求時にクラッシュする）:

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>不具合レポートの直前録画クリップをカメラロールに保存します。</string>
```

写真保存が不要なら `savesClipToPhotos: false` にすればこのキーは不要。

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
- 画面録画は画面上の全情報を含む → センシティブ View のマスキングは将来必須

## License

MIT
