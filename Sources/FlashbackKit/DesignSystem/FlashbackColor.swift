#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// Color tokens for the FlashbackKit UI.
///
/// Policy:
/// - **Only the two brand colors** live in the Asset Catalog Color Sets (light/dark):
///   `action` (recording / interactive = orange) and `slate` (brand neutral).
/// - Everything else maps to **semantic system colors** (never hardcoded) so it follows
///   the device's light/dark and contrast settings automatically.
/// - `onAction` is the one exception with no system equivalent, and it's deliberately not
///   one of the two brand colors, so it's defined here as a single dynamic color (no hex
///   scattered across views).
///
/// Color semantics (important): **orange = recording / interactive; gray = not recording.**
/// The settings screen is the exception, using standard iOS colors (blue links, green
/// toggles) via `settingsLink` and friends.
enum FlashbackColor {

    // MARK: - Brand (Asset Catalog, light/dark)

    /// Action / control color (orange). Used for the logo wedge, "Kit", the recording FAB,
    /// and ReportView's functional controls (play / trim / ✕ / share / gear).
    static let action = Color("ActionOrange", bundle: .module)

    /// Brand neutral color (Slate).
    static let slate = Color("Slate", bundle: .module)

    /// Foreground color placed on top of the action surface (glyphs/text on orange).
    /// Light = white, dark = deep brown (for legibility on the lighter dark-mode orange).
    /// Defined dynamically in code since there's no system equivalent.
    static let onAction = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x2A / 255, green: 0x1B / 255, blue: 0x08 / 255, alpha: 1)
            : .white
    })

    // MARK: - Background / surface (system semantic)

    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    /// Background for input fields / grouped cells.
    static let field = Color(uiColor: .secondarySystemBackground)
    static let separator = Color(uiColor: .separator)

    // MARK: - Text (system semantic)

    static let label = Color(uiColor: .label)
    static let secondaryLabel = Color(uiColor: .secondaryLabel)
    static let tertiaryLabel = Color(uiColor: .tertiaryLabel)

    // MARK: - Status (system semantic)

    static let success = Color(uiColor: .systemGreen)
    static let warning = Color(uiColor: .systemOrange)
    static let danger = Color(uiColor: .systemRed)

    /// Link / nav color for the settings screen (standard iOS blue). The exception that
    /// makes settings feel like the Settings app.
    static let settingsLink = Color(uiColor: .systemBlue)

    // MARK: - Brand colors for UIKit (used in UIView/CALayer layers, e.g. the FAB)

    /// `UIColor` for the action color (orange), resolved from the Asset Catalog.
    static let actionUIColor = UIColor(named: "ActionOrange", in: .module, compatibleWith: nil) ?? .systemOrange
    /// `UIColor` for the brand neutral color (Slate).
    static let slateUIColor = UIColor(named: "Slate", in: .module, compatibleWith: nil) ?? .systemGray
}
#endif
