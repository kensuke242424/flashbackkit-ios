# FlashbackKit

> Recall the moment before the bug.

不具合発生“前”の文脈を取り戻す、モバイル QA 向けの AI レポート SDK（iOS）。
端末をシェイク → 直前 30 秒の録画・コメント・端末情報をまとめ、AI がレポート化して Slack へ送る。

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

## MVP Scope

シェイク起動 / 直前録画 / コメント入力 / AI 要約 / Slack 送信

## Known Constraints（実装前に要注意）

- **ReplayKit は遡って録画できない** → 常時バッファ録画が前提（起動毎に録画許可プロンプトが出る／発熱・電池負荷あり）
- **Slack Incoming Webhook は動画を送れない**（テキスト / リンクのみ。動画は Bot トークン + files.getUploadURLExternal/completeUploadExternal が必要）
- **Claude / OpenAI は動画を直接解析できない**（キーフレーム抽出 or 動画ネイティブモデルが必要）
- 画面録画は画面上の全情報を含む → センシティブ View のマスキングは将来必須

## License

MIT
