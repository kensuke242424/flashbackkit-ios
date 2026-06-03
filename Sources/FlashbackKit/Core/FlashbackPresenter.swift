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

    /// トリガ detector が UI（フローティングボタン）を載せるための
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

    /// レポート入力 UI をモーダル（フルスクリーン）で表示する。
    /// - Parameters:
    ///   - clipURL: 直前クリップ（あればプレビュー＋トリミングを表示）。無ければ「おやすみ」案内。
    ///   - onShare: 共有アクション。切り出し→commit し、共有シート用の最終クリップ URL を返す。
    ///   - settings: 設定画面のストア（歯車 / 「録画をオンにする」から push）。
    func presentReport(
        clipURL: URL?,
        onShare: @escaping (String, ClosedRange<Double>?) async -> URL?,
        settings: FlashbackSettingsStore
    ) {
        guard let root = window?.rootViewController, root.presentedViewController == nil else { return }

        let report = ReportView(
            clipURL: clipURL,
            device: .current(),                           // @MainActor 採取（本メソッドは @MainActor）
            onShare: onShare,
            onCancel: { [weak self] in self?.dismissReport() },
            settings: settings
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

    /// 進行中トースト（オレンジのスピナー）。書き出し中に出す。例:「記憶を辿っています…」。
    func showProgress(_ message: String) {
        model.toast = .progress(message)
    }

    /// 失敗トースト（赤アイコン＋青「再試行」）。自動では閉じない。
    func showFailure(_ message: String, onRetry: @escaping () -> Void) {
        model.toast = .failure(message: message, onRetry: onRetry)
    }

    /// トーストを消す。
    func hideToast() {
        model.toast = nil
    }

    #if DEBUG
    /// DEBUG 専用: 設定画面を単体（自前の NavigationStack）で提示する（見た目確認用）。
    /// 本番は ReportView の歯車から push され「‹ レポート」で戻れるが、単体提示は親が無いため
    /// 「閉じる」を足して手詰まりにならないようにする（本番の SettingsView には影響しない）。
    func debugPresentSettings(store: FlashbackSettingsStore) {
        guard let root = window?.rootViewController, root.presentedViewController == nil else { return }
        let view = NavigationStack {
            SettingsView(store: store)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { [weak self] in self?.dismissReport() }
                    }
                }
        }
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .fullScreen
        reportHost = host
        root.present(host, animated: true)
    }

    /// DEBUG 専用: 許可プライミングのシート（.medium）を単体で提示する（見た目確認用）。
    func debugPresentPriming(onProceed: @escaping () -> Void, onLater: @escaping () -> Void) {
        guard let root = window?.rootViewController, root.presentedViewController == nil else { return }
        let host = UIHostingController(rootView: PrimingDebugHost(onProceed: onProceed, onLater: onLater))
        host.modalPresentationStyle = .overFullScreen
        host.view.backgroundColor = .clear
        reportHost = host
        root.present(host, animated: false)
    }
    #endif

    // MARK: - 設置

    private func installStatusOverlay(in root: UIViewController) {
        let overlay = UIHostingController(rootView: StatusOverlay(model: model))
        overlay.view.backgroundColor = .clear
        overlay.view.translatesAutoresizingMaskIntoConstraints = false
        // 下中央にトースト分だけ載せる（コンテンツサイズ）。失敗トーストの「再試行」を
        // タップできるよう操作は有効。トースト以外の領域は覆わないのでホスト/FAB を妨げない。
        root.addChild(overlay)
        root.view.addSubview(overlay.view)
        let guide = root.view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            overlay.view.centerXAnchor.constraint(equalTo: root.view.centerXAnchor),
            overlay.view.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -36),
            overlay.view.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 16),
            overlay.view.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -16),
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

/// トーストの内容（README 準拠で2種のみ）。
enum ToastContent {
    /// 進行中（オレンジのスピナー）。例:「記憶を辿っています…」。
    case progress(String)
    /// 失敗（赤アイコン＋青「再試行」）。自動では閉じない。
    case failure(message: String, onRetry: () -> Void)
}

/// overlay UI の状態。
@MainActor
private final class OverlayModel: ObservableObject {
    @Published var toast: ToastContent?

    /// アニメーション差分用キー（`ToastContent` は Equatable でないため）。
    var toastKey: String {
        switch toast {
        case .progress(let m): return "p:\(m)"
        case .failure(let m, _): return "f:\(m)"
        case nil: return ""
        }
    }
}

/// 画面下中央にトーストを出す overlay。失敗トーストの「再試行」だけタップを受ける。
private struct StatusOverlay: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        Group {
            switch model.toast {
            case .progress(let message):
                ToastCapsule {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FlashbackColor.action)              // オレンジのスピナー
                    Text(message)
                }
            case .failure(let message, let onRetry):
                ToastCapsule {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(FlashbackColor.danger)   // 赤
                    Text(message)
                    Button(action: onRetry) {
                        HStack(spacing: 2) {
                            Text("再試行")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(FlashbackColor.settingsLink)   // 青
                    }
                    .accessibilityLabel("再試行")
                }
            case nil:
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toastKey)
    }
}

/// トーストの反転背景色（dynamic UIColor・trait 解決でライブ切替に追従）。
/// bg: ライト=ほぼ黒(20,20,24 @0.92) / ダーク=近白。fg はその反転。
private enum ToastPalette {
    static let background = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.96, alpha: 1)
            : UIColor(red: 20 / 255, green: 20 / 255, blue: 24 / 255, alpha: 0.92)
    }
    static let foreground = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 20 / 255, green: 20 / 255, blue: 24 / 255, alpha: 1)
            : .white
    }
}

/// トーストの共通カプセル（角丸20相当のピル・12pt・反転背景）。
private struct ToastCapsule<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(uiColor: ToastPalette.foreground))
            .lineLimit(1)
            .fixedSize()                       // hosting view の横潰れ＝テキスト切れを防ぐ
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color(uiColor: ToastPalette.background), in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }
}

#if DEBUG
/// DEBUG 専用: 透明ホスト上に許可プライミングのシートを即提示する（見た目確認用）。
private struct PrimingDebugHost: View {
    let onProceed: () -> Void
    let onLater: () -> Void
    @State private var show = true

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .sheet(isPresented: $show) {
                PermissionPrimingView(onProceed: onProceed, onLater: onLater)
                    .presentationDetents([.medium])
            }
    }
}
#endif
#else
/// UIKit / SwiftUI が無い環境（macOS ホストビルド等）向けの no-op スタブ。
final class FlashbackPresenter {
    func install() {}
    func uninstall() {}
    func presentReport(
        clipURL: URL?,
        onShare: @escaping (String, ClosedRange<Double>?) async -> URL?,
        settings: FlashbackSettingsStore
    ) {}
    func dismissReport() {}
    func showProgress(_ message: String) {}
    func showFailure(_ message: String, onRetry: @escaping () -> Void) {}
    func hideToast() {}
}
#endif
