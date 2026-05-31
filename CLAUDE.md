# FlashbackKit

モバイルQA向けのAIバグレポートSDK（iOS）。不具合発生“前”の文脈
（直前録画・コメント・端末情報）を保存し、AIがレポート化してSlackへ送る。

## ステータス
PoC / WIP。本番一般ユーザー向けではなく Debug / Staging / TestFlight / 社内QA 用途。
設計の綺麗さより「QAが使いたくなるか・再現性が上がるか」を優先する。

## 技術スタック
- Swift 6 / iOS 16+ / SwiftUI / ReplayKit
- パッケージ管理: SPM（Package.swift）
- **依存ゼロが鉄則**: Firebase / Alamofire / RxSwift 等の外部依存を絶対に追加しない。
  通信は URLSession。SDK導入障壁を下げるため。新規依存を足す提案はしないこと。

## ビルド・テスト
- `swift build` は使わない（macOSホスト向けに走って UIKit 周りでコケる）。
- iOSビルド:
  `xcodebuild -scheme FlashbackKit -destination 'generic/platform=iOS' build`
- テスト:
  `xcodebuild test -scheme FlashbackKit -destination 'platform=iOS Simulator,name=iPhone 16'`

## ディレクトリ構成
- `Sources/FlashbackKit/Flashback.swift` — 公開API（`Flashback.start()`）
- `Core/` — Controller / Configuration / Error / FlashbackTrigger(OptionSet)
- `Core/Triggers/` — TriggerDetecting + 各トリガ実装（ShakeTrigger / MultiFingerHoldTrigger / FloatingButtonTrigger）
- `Recording/ScreenRecorder` — ReplayKit リングバッファ
- `Report/` — ReportView(SwiftUI) / FlashbackReport
- `AI/ReportGenerator` — protocol + 実装
- `Slack/SlackNotifier`
- `Device/DeviceInfo`

## 設計上の制約（前提として守る。回避できない案を提案しない）
1. **ReplayKitは遡って録画できない**。直前N秒は「常時バッファ録画＋リング保持」で実現する。
   録画していなかった分を後から取得する案は物理的に不可能。
2. **Slack Incoming Webhookは動画/ファイルを送れない**（テキスト/Block Kitのみ）。
   動画添付は別ホスト＋リンク、または Botトークン＋files.getUploadURLExternal/completeUploadExternal。
3. **Claude/OpenAI APIは動画を直接解析できない**（テキスト+画像のみ）。
   動画解析が要るならキーフレーム抽出、または動画ネイティブモデル（Gemini）。

## コーディング規約
- public API には doc コメントを付ける。
- UI / 録画 / シェイク検知に触れる型は `@MainActor`。
- 公開型は明示的アクセス修飾子を付ける。

## セキュリティ
- Slack Webhook URL / APIキー等のシークレットはコミットしない。Configuration 経由で注入する。
- 画面録画はセンシティブ情報を含む。ログやレポートに生データを残さない。
