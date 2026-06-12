#if canImport(UIKit)
import UIKit

/// Bookkeeping for "is any secure text field currently being edited?".
///
/// Fed by `UITextField` / `UITextView` begin/end editing notifications (app-wide; SwiftUI's
/// `SecureField` is backed by `UITextField`, so it is covered too). A field is counted at
/// begin-editing time when its `isSecureTextEntry` trait is set; it is removed at end-editing
/// **by identity regardless of the trait's value then** — a reveal ("eye") toggle can flip the
/// trait mid-edit, and the entry must still be released when editing ends.
///
/// `internal` so unit tests can drive it with real text fields on the Simulator (no ReplayKit
/// dependency — the capture pause/resume wiring lives in `ScreenRecorder`).
@MainActor
final class SecureEntryTracker {
    /// Identities of the secure fields currently being edited. A set (not a flag): focus can
    /// hop between two secure fields with the new field's begin arriving before the old
    /// field's end, and the pause must hold across that overlap.
    private var editingSecureFields = Set<ObjectIdentifier>()

    /// Whether at least one secure field is currently being edited.
    var isEditingSecure: Bool { !editingSecureFields.isEmpty }

    /// Notes a begin-editing notification. Returns `true` only on the 0 → 1 transition
    /// (the "pause now" edge); non-secure fields and already-tracked overlaps return `false`.
    func noteBeginEditing(_ object: Any?) -> Bool {
        guard Self.isSecure(object), let obj = object as? AnyObject else { return false }
        let wasEmpty = editingSecureFields.isEmpty
        editingSecureFields.insert(ObjectIdentifier(obj))
        return wasEmpty
    }

    /// Notes an end-editing notification. Returns `true` only when the set becomes empty
    /// (the "may resume now" edge); untracked objects return `false`.
    func noteEndEditing(_ object: Any?) -> Bool {
        guard let obj = object as? AnyObject else { return false }
        let removed = editingSecureFields.remove(ObjectIdentifier(obj)) != nil
        return removed && editingSecureFields.isEmpty
    }

    /// Whether the notification's object is a text input with `isSecureTextEntry` set.
    /// Checked concretely (UITextField / UITextView) rather than via the optional
    /// `UITextInputTraits` requirement, to keep the behavior obvious.
    private static func isSecure(_ object: Any?) -> Bool {
        if let field = object as? UITextField { return field.isSecureTextEntry }
        if let view = object as? UITextView { return view.isSecureTextEntry }
        return false
    }
}
#endif
