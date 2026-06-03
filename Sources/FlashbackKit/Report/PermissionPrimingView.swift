#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

/// 画面収録の許可プライミング（pre-permission）シート。
///
/// ReplayKit の許可システムアラートは本文・ボタンを**カスタムできない**（差し込めるのは
/// アプリ表示名のみ）。そこで OS 確認を出す“前”に本シートで意味を橋渡しし、理解と許可率を上げる。
///
/// 提示は `.sheet` + `.presentationDetents([.medium])`（おやすみ ReportView の上）。
/// 色ルール: まだ録画オフなのでヒーローマークは **Slate 中立**、唯一のオレンジは操作可能な CTA。
/// コピーは正本 priming.jsx の A 案（中立・説明型）。「不具合/バグ」表現は使わない。
struct PermissionPrimingView: View {
    /// 「許可へ進む」: 呼び出し側で hasPrimed を立て、シートを閉じて録画再試行（OS 確認）へ繋ぐ。
    let onProceed: () -> Void
    /// 「あとで」: シートを閉じておやすみへ戻る（トースト無し）。
    let onLater: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            // ヒーロー: Slate 中立の Time Slice マーク（まだ録画オフ）。
            TimeSliceMark.primingNeutral()
                .frame(width: 46, height: 46)
                .padding(.bottom, 16)

            Text("画面収録をオンにします")
                .font(.title3.weight(.bold))
                .foregroundStyle(FlashbackColor.label)
                .multilineTextAlignment(.center)

            Text("次に表示される iOS の確認で「許可」を選ぶと、アプリ内の直前の操作を自動で保持できます。")
                .font(.subheadline)
                .foregroundStyle(FlashbackColor.secondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
                .padding(.horizontal, 8)
                .frame(maxWidth: 280)

            Spacer(minLength: 16)

            // CTA: オレンジ塗り（録画を有効化する操作）。
            Button(action: onProceed) {
                Text("許可へ進む")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FlashbackColor.onAction)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(FlashbackColor.action, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("許可へ進む")
            .accessibilityHint("iOS の画面収録の確認が表示されます")

            // 「あとで」: 控えめなテキストボタン。
            Button(action: onLater) {
                Text("あとで")
                    .font(.callout)
                    .foregroundStyle(FlashbackColor.secondaryLabel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .padding(.top, 10)
            .accessibilityLabel("あとで")

            // ヒント: 次のタップで OS 確認が出ることを示す（mono・控えめ）。
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                Text("タップすると iOS の確認が表示されます")
                    .font(FlashbackFont.mono)
            }
            .foregroundStyle(FlashbackColor.tertiaryLabel)
            .padding(.top, 12)
            .accessibilityHidden(true)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(FlashbackColor.background)
    }
}

#if DEBUG
#Preview("Priming") {
    Color.gray.opacity(0.3)
        .sheet(isPresented: .constant(true)) {
            PermissionPrimingView(onProceed: {}, onLater: {})
                .presentationDetents([.medium])
        }
}
#endif
#endif
