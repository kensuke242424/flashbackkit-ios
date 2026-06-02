#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// FlashbackKit UI のカラートークン（"Quiet" 確定版）。
///
/// 方針（README トークン表準拠）:
/// - **ブランド2色のみ** Asset Catalog の Color Set（ライト/ダーク両対応）で持つ。
///   `action`（録画中 / 操作可能 = オレンジ）と `slate`（ブランド中立）。
/// - それ以外はすべて **semantic system color** に寄せる（ハードコードしない）。
///   端末のライト/ダーク・コントラスト設定へ自動追従させるため。
/// - `onAction` だけは system 等価が無く、かつ「ブランド2色」にも含めない約束のため、
///   ここでコード定義の dynamic color として一元管理する（View に hex を撒かない）。
///
/// 色の意味づけ（重要）: **オレンジ = 録画中 / 操作可能。グレー = 非録画。**
/// 設定画面だけは例外で、標準 iOS カラー（青リンク・緑トグル）を使う＝`settingsLink` 等。
enum FlashbackColor {

    // MARK: - ブランド（Asset Catalog / ライト・ダーク）

    /// アクション / コントロール色（オレンジ）。ロゴのくさび・"Kit"・録画中 FAB・
    /// ReportView の機能コントロール（再生 / トリム / ✕ / 共有 / 歯車）に使う。
    static let action = Color("ActionOrange", bundle: .module)

    /// ブランド中立色（Slate）。
    static let slate = Color("Slate", bundle: .module)

    /// アクション面の上に乗せる前景色（オレンジ上のグリフ/テキスト）。
    /// ライト = 白、ダーク = 濃いブラウン（明るいダークオレンジ上での可読性確保）。
    /// system 等価が無いためコードで dynamic 定義する。
    static let onAction = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x2A / 255, green: 0x1B / 255, blue: 0x08 / 255, alpha: 1)
            : .white
    })

    // MARK: - 背景 / サーフェス（system semantic）

    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    /// 入力フィールド / グルーピングされたセルの背景。
    static let field = Color(uiColor: .secondarySystemBackground)
    static let separator = Color(uiColor: .separator)

    // MARK: - テキスト（system semantic）

    static let label = Color(uiColor: .label)
    static let secondaryLabel = Color(uiColor: .secondaryLabel)
    static let tertiaryLabel = Color(uiColor: .tertiaryLabel)

    // MARK: - ステータス（system semantic）

    static let success = Color(uiColor: .systemGreen)
    static let warning = Color(uiColor: .systemOrange)
    static let danger = Color(uiColor: .systemRed)

    /// 設定画面のリンク / ナビ（標準 iOS の青）。設定は「設定.app 然」とするための例外。
    static let settingsLink = Color(uiColor: .systemBlue)

    // MARK: - UIKit 用ブランド色（FAB など UIView/CALayer レイヤで使う）

    /// アクション色（オレンジ）の `UIColor`。Asset Catalog から解決する。
    static let actionUIColor = UIColor(named: "ActionOrange", in: .module, compatibleWith: nil) ?? .systemOrange
    /// ブランド中立色（Slate）の `UIColor`。
    static let slateUIColor = UIColor(named: "Slate", in: .module, compatibleWith: nil) ?? .systemGray
}
#endif
