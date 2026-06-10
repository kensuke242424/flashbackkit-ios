#if canImport(UIKit) && canImport(SwiftUI)
import XCTest
import UIKit
import SwiftUI
@testable import FlashbackKit

/// 不具合「iPad（iPadOS 18）で Example のタブ等ホスト UI のタップが効かない」の回帰テスト。
///
/// SDK の overlay は `PassthroughWindow`（全画面・最前面）→ `SecureOverlayRootController`
/// → `SecureOverlayRootView`（secure UITextField の内部キャンバスに contentHost を載せて
/// OS キャプチャから除外）という構造。実機タップは **window** を入口に hitTest される。
///
/// iPad では secure field の内部キャンバス配下に全画面の `contentHost`（interaction 有効）が
/// 居り、`UIWindow` 既定の hitTest がそこへ直接降りて `contentHost` を返してしまう。旧実装は
/// window 側で「window / root view」だけを素通し判定する拒否リストだったため、`contentHost`
/// を認識できず**空き領域のタップを全部飲み込んでいた**（= ホスト UI 全体が死ぬ）。
///
/// よって回帰テストは `root.hitTest` 単体ではなく **window 越し**で検証する（実タップ経路）。
@MainActor
final class SecureOverlayHitTestTests: XCTestCase {

    /// 本番と同じ overlay 構造（PassthroughWindow → SecureOverlayRootController）を組み、
    /// レイアウト＋RunLoop を回して secure field の内部ビューを実体化させる。
    /// 返り値の window は呼び出し側で保持（keyWindow を維持するため）。
    private func makeOverlay(size: CGSize) -> (PassthroughWindow, SecureOverlayRootView) {
        let window = PassthroughWindow(frame: CGRect(origin: .zero, size: size))
        let controller = SecureOverlayRootController()
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()

        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        // secure UITextField は内部レンダリングビューを遅延生成するので RunLoop を少し回す。
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        controller.view.layoutIfNeeded()

        // swiftlint:disable:next force_cast
        let root = controller.view as! SecureOverlayRootView
        return (window, root)
    }

    /// secure field 配下のビュー階層を再帰ダンプ（診断ログ。クラス名 / frame / interaction）。
    private func dump(_ view: UIView, depth: Int = 0, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)\(type(of: view)) frame=\(view.frame) uie=\(view.isUserInteractionEnabled)")
        for sub in view.subviews { dump(sub, depth: depth + 1, into: &lines) }
    }

    // MARK: - 回帰: 空き領域は window 越しでホストへ素通し（nil）

    /// iPad サイズ：コンテンツ未配置でも、本番 toast 相当のコンテンツサイズ hosting を載せても、
    /// 空き領域（複数点）の window.hitTest が nil（= ホストへ素通し）になること。
    func testIPadEmptyAreaPassesThroughWindow() {
        let size = CGSize(width: 1024, height: 1366)   // iPad Pro 11" portrait 相当
        let (window, root) = makeOverlay(size: size)
        defer { window.isHidden = true }

        // 本番 installStatusOverlay 相当：底辺中央にコンテンツサイズの toast を載せる（全画面でない）。
        let toastHost = UIHostingController(rootView: Text("toast").padding())
        toastHost.view.backgroundColor = .clear
        toastHost.view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toastHost.view)               // override で contentHost 配下へ
        NSLayoutConstraint.activate([
            toastHost.view.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            toastHost.view.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.bottomAnchor, constant: -36),
        ])
        root.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        // 診断ログ：secure field の内部ビュー階層（iPad 固有の内部構造を記録）。
        var lines: [String] = []
        dump(root.test_secureField, into: &lines)
        print("=== [iPad] secureField internal hierarchy ===\n" + lines.joined(separator: "\n"))

        // 空き領域の代表点（中央・上部タブ帯・四隅近辺）を window 越しに hitTest。
        let emptyPoints: [(String, CGPoint)] = [
            ("center", CGPoint(x: size.width / 2, y: size.height / 2)),
            ("topTabBand", CGPoint(x: size.width / 2, y: 60)),
            ("topLeft", CGPoint(x: 40, y: 40)),
            ("topRight", CGPoint(x: size.width - 40, y: 40)),
        ]
        for (name, p) in emptyPoints {
            let hit = window.hitTest(p, with: nil)
            print("=== [iPad] window.hitTest \(name) \(p) === \(hit.map { String(describing: type(of: $0)) } ?? "nil(passthrough)")")
            XCTAssertNil(hit, "iPad: 空き領域(\(name)) のタップが overlay に飲み込まれている（ホストへ素通しされない）")
        }
    }

    /// iPhone サイズでも空き領域が window 越しで素通しになること（対照）。
    func testIPhoneEmptyAreaPassesThroughWindow() {
        let size = CGSize(width: 393, height: 852)     // iPhone 16 portrait
        let (window, root) = makeOverlay(size: size)
        defer { window.isHidden = true }

        var lines: [String] = []
        dump(root.test_secureField, into: &lines)
        print("=== [iPhone] secureField internal hierarchy ===\n" + lines.joined(separator: "\n"))

        let p = CGPoint(x: size.width / 2, y: size.height / 2)
        let hit = window.hitTest(p, with: nil)
        XCTAssertNil(hit, "iPhone: 空き領域のタップが overlay に飲み込まれている")
    }

    // MARK: - 回帰: 実コンテンツ（FAB/toast 相当）の上は window 越しでちゃんと取れる

    /// contentHost に置いたダミー button の上を window 越しに hitTest すると、その button
    /// （の子孫）が返ること。= 修正で「全部素通し」になって操作性を壊していないことの保証。
    func testContentButtonIsHittableThroughWindow() {
        let size = CGSize(width: 1024, height: 1366)
        let (window, root) = makeOverlay(size: size)
        defer { window.isHidden = true }

        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 44)
        root.addSubview(button)                       // override で contentHost 配下へ
        root.layoutIfNeeded()

        let onButton = CGPoint(x: 160, y: 122)        // button の中
        let hit = window.hitTest(onButton, with: nil)
        XCTAssertNotNil(hit, "contentHost のボタン上で window.hitTest が nil（コンテンツが取れていない）")

        var node = hit
        var isButtonOrDescendant = false
        while let n = node {
            if n === button { isButtonOrDescendant = true; break }
            node = n.superview
        }
        XCTAssertTrue(isButtonOrDescendant,
                      "button 上の hit が button（の子孫）でない: \(String(describing: hit.map { type(of: $0) }))")
    }

    /// 修正が presented なシート（レポート/設定/プライミング）を壊さないこと。presented なシートは
    /// overlay root の**外側**（window 直下の別サブツリー）に居る。これを模して window 直下に別 view
    /// を載せ、その上の window.hitTest がその view を**返す**（= 素通しされない）ことを確認する。
    ///
    /// 注: 実 modal present はユニットテスト環境では window へ接続されない（シーン未接続のため
    /// presented.view.window == nil）。よって「root の外の別サブツリー」を直接構築して
    /// `PassthroughWindow.hitTest` の分岐を決定的に検証する。実シートの操作性は Example 実機確認で担保。
    func testViewOutsideOverlayRootStaysHittable() {
        let size = CGSize(width: 1024, height: 1366)
        let (window, root) = makeOverlay(size: size)
        defer { window.isHidden = true }

        // overlay root とは別系統の、window 直下サブツリー（presented シート相当）。
        let sheet = UIView(frame: window.bounds)
        sheet.backgroundColor = .black.withAlphaComponent(0.3)   // 透明でも interaction 有効
        window.addSubview(sheet)                                 // root の外側（前面）
        window.layoutIfNeeded()

        XCTAssertFalse(sheet.isDescendant(of: root), "前提: sheet は overlay root の外にあること")

        let p = CGPoint(x: size.width / 2, y: size.height / 2)
        let hit = window.hitTest(p, with: nil)
        XCTAssertNotNil(hit, "overlay root 外のシート上で window.hitTest が nil（素通しされてしまう）")
        XCTAssertTrue(hit === sheet || hit?.isDescendant(of: sheet) == true,
                      "シート上の hit が sheet（の子孫）でない: \(String(describing: hit.map { type(of: $0) }))")
    }
}
#endif
