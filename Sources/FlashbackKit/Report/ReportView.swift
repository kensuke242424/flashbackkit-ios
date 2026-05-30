#if canImport(SwiftUI)
import SwiftUI

/// 最小のレポート入力 UI: コメント + 送信。
struct ReportView: View {
    @State private var comment: String = ""
    let onSend: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("何が起きた？")
                    .font(.headline)
                TextEditor(text: $comment)
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.secondary.opacity(0.3))
                    )
                Spacer()
            }
            .padding()
            .navigationTitle("Flashback")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送信") { onSend(comment) }
                        .disabled(comment.isEmpty)
                }
            }
        }
    }
}
#endif
