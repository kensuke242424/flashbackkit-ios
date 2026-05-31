import Foundation
#if canImport(UIKit) && canImport(SwiftUI)
import UIKit
import SwiftUI

/// SDK 専用の overlay `UIWindow` を立て、ホストアプリの view 階層に干渉せず
/// デバッグトリガ（フローティングボタン）とレポート UI を表示する。
///
/// ホスト側のコードは `Flashback.start()` のみで完結する。
///
/// 設計メモ: フローティングボタンは root の hosting view の一部にせず、
/// 独立した小さな subview（専用 hosting controller）として載せる。
/// こうすると `hitTest` でボタン領域だけタップを拾い、それ以外はホストへ
/// パススルーできる（SwiftUI のボタンは固有の UIView を持たないため、
/// 全画面 hosting view に混ぜるとタップ判定がパススルーに巻き込まれる）。
@MainActor
final class FlashbackPresenter {
    private let model = OverlayModel()
    private var window: UIWindow?
    private weak var reportHost: UIViewController?

    /// overlay window を前面シーンに設置する。トリガ用の UI（ボタン / ジェスチャ）は
    /// `triggerHost` を介して各 detector が載せる。
    func install() {
        guard window == nil, let scene = Self.activeScene() else { return }

        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear

        let root = UIViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        window.isHidden = false
        self.window = window

        installStatusOverlay(in: root)
    }

    /// トリガ detector が UI（フローティングボタン / 多指キャプチャ view）を載せるための
    /// overlay root view controller。`install()` 後に有効。
    var triggerHost: UIViewController? {
        window?.rootViewController
    }

    /// overlay window を撤去する。
    func uninstall() {
        reportHost?.dismiss(animated: false)
        reportHost = nil
        window?.isHidden = true
        window = nil
    }

    /// レポート入力 UI をモーダルで表示する。
    /// - Parameters:
    ///   - clipURL: 直前クリップ（あればプレビュー＋トリミングを表示）。無ければコメントのみ。
    ///   - onSend: 送信ボタン押下時に（コメント, 選択範囲秒）を受け取る。範囲はクリップ無しなら nil。
    func presentReport(clipURL: URL?, onSend: @escaping (String, ClosedRange<Double>?) -> Void) {
        guard let root = window?.rootViewController, root.presentedViewController == nil else { return }

        let report = ReportView(
            clipURL: clipURL,
            device: .current(),                           // @MainActor 採取（本メソッドは @MainActor）
            onSend: { onSend($0, $1) },                   // 後段（dismiss / status）は呼び出し側が制御
            onCancel: { [weak self] in self?.dismissReport() }
        )
        let host = UIHostingController(rootView: report)
        host.modalPresentationStyle = .fullScreen
        reportHost = host
        root.present(host, animated: true)
    }

    /// レポート入力 UI を閉じる。
    func dismissReport() {
        reportHost?.dismiss(animated: true)
        reportHost = nil
    }

    /// 画面上に一時的なステータス文言（トースト）を出す。送信中／結果表示に使う。
    /// 空文字を渡すと非表示にする。
    func showStatus(_ message: String) {
        model.status = message.isEmpty ? nil : message
    }

    // MARK: - 設置

    private func installStatusOverlay(in root: UIViewController) {
        let overlay = UIHostingController(rootView: StatusOverlay(model: model))
        overlay.view.backgroundColor = .clear
        // トーストはタップを奪わない（常に背面でパススルー）。
        overlay.view.isUserInteractionEnabled = false
        overlay.view.translatesAutoresizingMaskIntoConstraints = false

        root.addChild(overlay)
        root.view.addSubview(overlay.view)
        NSLayoutConstraint.activate([
            overlay.view.topAnchor.constraint(equalTo: root.view.topAnchor),
            overlay.view.bottomAnchor.constraint(equalTo: root.view.bottomAnchor),
            overlay.view.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            overlay.view.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
        ])
        overlay.didMove(toParent: root)
    }

    /// アクティブな foreground シーンを探す。
    private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

/// 実体のある subview（ボタン等）以外のタッチをホストアプリへ通す `UIWindow`。
@MainActor
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // window 自身 / root view（透明な背景）に当たった = 何も載っていない領域。
        // ホストへパススルーするため nil を返す。
        if hit == self || hit == rootViewController?.view {
            return nil
        }
        return hit
    }
}

/// overlay UI の状態。
@MainActor
private final class OverlayModel: ObservableObject {
    @Published var status: String?
}

/// 送信ステータス（トースト）を画面下中央に出す非インタラクティブ overlay。
private struct StatusOverlay: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        VStack {
            Spacer()
            if let status = model.status {
                StatusToast(text: status)
                    .padding(.bottom, 120)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.default, value: model.status)
    }
}

/// 送信中／結果を伝える軽量トースト。
private struct StatusToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.8), in: Capsule())
    }
}
#else
/// UIKit / SwiftUI が無い環境（macOS ホストビルド等）向けの no-op スタブ。
final class FlashbackPresenter {
    func install() {}
    func uninstall() {}
    func presentReport(clipURL: URL?, onSend: @escaping (String, ClosedRange<Double>?) -> Void) {}
    func dismissReport() {}
    func showStatus(_ message: String) {}
}
#endif
