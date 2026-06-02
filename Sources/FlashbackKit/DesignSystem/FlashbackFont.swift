#if canImport(SwiftUI)
import SwiftUI

/// FlashbackKit UI のタイポグラフィ・トークン。
///
/// 方針（README 準拠）: 固定 pt ではなく **text style** で定義し Dynamic Type に追従する。
/// 数表データ（タイムコード・端末情報・バージョン文字列）は **SF Mono**（`.monospaced`）。
/// 右側コメントは README の近似マッピング（mock 上の pt）。
enum FlashbackFont {

    /// ナビタイトル "Flashback"。16–17 / semibold。
    static let navTitle = Font.headline

    /// 本文セクションの見出し。16 / bold。
    static let sectionHeader = Font.headline

    /// フィールドラベル（"タイトル" など）。13 / semibold。
    static let fieldLabel = Font.footnote.weight(.semibold)

    /// 本文 / 行テキスト。14–15。
    static let body = Font.subheadline

    /// セクションキャプション（"環境情報" など）。11 / semibold / グレー運用。
    static let caption = Font.caption2.weight(.semibold)

    /// 端末情報の行（`iPhone 16` / `iOS 18.4` / `v1.0 (1)`）。13 / SF Mono。
    static let mono = Font.system(.footnote, design: .monospaced)

    /// タイムコード（`0:00 ~ 0:12 (0:12)`）。13 / SF Mono / 等幅数字。
    static let timecode = Font.system(.footnote, design: .monospaced).monospacedDigit()
}
#endif
