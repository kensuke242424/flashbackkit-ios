#if canImport(SwiftUI)
import SwiftUI

/// Typography tokens for the FlashbackKit UI.
///
/// Policy: define by **text style** rather than fixed pt so it follows Dynamic Type.
/// Tabular data (timecodes, device info, version strings) uses **SF Mono**
/// (`.monospaced`). The trailing comments are the approximate pt on the mocks.
enum FlashbackFont {

    /// Nav title "Flashback". 16–17 / semibold.
    static let navTitle = Font.headline

    /// Body section header. 16 / bold.
    static let sectionHeader = Font.headline

    /// Field label (e.g. "Title"). 13 / semibold.
    static let fieldLabel = Font.footnote.weight(.semibold)

    /// Body / line text. 14–15.
    static let body = Font.subheadline

    /// Section caption (e.g. "Environment"). 11 / semibold / used in gray.
    static let caption = Font.caption2.weight(.semibold)

    /// Device-info line (`iPhone 16` / `iOS 18.4` / `v1.0 (1)`). 13 / SF Mono.
    static let mono = Font.system(.footnote, design: .monospaced)

    /// Timecode (`0:00 ~ 0:12 (0:12)`). 13 / SF Mono / monospaced digits.
    static let timecode = Font.system(.footnote, design: .monospaced).monospacedDigit()
}
#endif
